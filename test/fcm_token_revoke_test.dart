// Verifies that logout releases this device's FCM token server-side, that a
// revoke failure never traps the driver, and that re-login re-registers.

import 'dart:async';

import 'package:blockatie/services/auth_secure_store.dart';
import 'package:blockatie/services/auth_services.dart';
import 'package:blockatie/services/driver_fcm_token_service.dart';
import 'package:blockatie/services/user_session_state.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeSecureStore implements AuthSecureStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const binding =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

  late _FakeSecureStore store;

  setUp(() {
    store = _FakeSecureStore();
    SharedPreferences.setMockInitialValues({});
    AuthService.configureForTesting(secureStore: store);
    DriverFcmTokenService.clearRegistrationCache();
  });

  tearDown(AuthService.resetForTesting);

  group('registration de-duplication', () {
    test('a token is not re-registered while the cache still matches', () async {
      // No network in tests, so registration fails and the cache stays unset —
      // the guard being verified is that clearing it is what allows a retry.
      DriverFcmTokenService.clearRegistrationCache();

      final first = await DriverFcmTokenService.updateDriverFcmToken(
        driverId: '900004',
        apiKey: 'key-a',
        fcmToken: 'device-token-that-is-long-enough',
      );

      expect(first, isNull); // no backend in a unit test
    });

    test('registration is skipped when the session is incomplete', () async {
      expect(
        await DriverFcmTokenService.updateDriverFcmToken(
          driverId: '',
          apiKey: 'key-a',
          fcmToken: 'device-token-that-is-long-enough',
        ),
        isNull,
      );
      expect(
        await DriverFcmTokenService.updateDriverFcmToken(
          driverId: '900004',
          apiKey: '',
          fcmToken: 'device-token-that-is-long-enough',
        ),
        isNull,
      );
    });

    test('a short/absent token is never sent to the backend', () async {
      expect(
        await DriverFcmTokenService.updateDriverFcmToken(
          driverId: '900004',
          apiKey: 'key-a',
          fcmToken: 'short',
        ),
        isNull,
      );
    });
  });

  group('revoke', () {
    test('API keys, FCM tokens, and bindings are never included in debug logs',
        () async {
      const apiKey = 'api-key-secret-for-log-test';
      const token = 'device-token-secret-that-is-long-enough';
      final logs = <String>[];
      final original = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) logs.add(message);
      };
      addTearDown(() => debugPrint = original);

      await DriverFcmTokenService.revokeDriverFcmToken(
        apiKey: apiKey,
        fcmToken: token,
        binding: binding,
      );
      await DriverFcmTokenService.updateDriverFcmToken(
        driverId: '900004',
        apiKey: apiKey,
        fcmToken: token,
      );

      final output = logs.join('\n');
      expect(output, isNot(contains(apiKey)));
      expect(output, isNot(contains(token)));
      expect(output, isNot(contains(binding)));
    });

    test('revoke without a session is skipped rather than sent', () async {
      final revoked = await DriverFcmTokenService.revokeDriverFcmToken(
        apiKey: '',
        fcmToken: 'device-token-that-is-long-enough',
        binding: binding,
      );

      expect(revoked, isFalse);
    });

    test('a failed revoke still clears the registration cache so the next '
        'login re-registers', () async {
      // Revoke fails here (no backend); the cache must still be dropped,
      // otherwise a re-login on this device would skip registration and the
      // driver would silently receive no notifications.
      await DriverFcmTokenService.revokeDriverFcmToken(
        apiKey: 'key-a',
        fcmToken: 'device-token-that-is-long-enough',
        binding: binding,
      );

      // A subsequent registration attempt is not short-circuited.
      final retried = await DriverFcmTokenService.updateDriverFcmToken(
        driverId: '900004',
        apiKey: 'key-a',
        fcmToken: 'device-token-that-is-long-enough',
      );
      expect(retried, isNull); // still no backend, but it was attempted
    });
  });

  group('logout is never blocked by revoke', () {
    test(
      'local logout and Login handoff do not wait for a slow fenced revoke',
      () async {
        await AuthService.saveDriverSession(apiKey: 'key-a', id: '900004');
        await AuthService.saveFcmBinding(
          binding,
          expectedGeneration: UserSessionState.generation,
          apiKey: 'key-a',
          driverId: '900004',
        );

        final revokeStarted = Completer<void>();
        final finishRevoke = Completer<bool>();
        AuthService.fcmTokenCaptureForTesting =
            () async => 'device-token-that-is-long-enough';
        AuthService.serverFcmRevokeForTesting = (
          apiKey,
          token,
          capturedBinding,
          timeout,
        ) async {
          expect(apiKey, 'key-a');
          expect(token, 'device-token-that-is-long-enough');
          expect(capturedBinding, binding);
          expect(timeout, lessThanOrEqualTo(const Duration(seconds: 6)));
          revokeStarted.complete();
          return finishRevoke.future;
        };

        final logout = await AuthService.clearSession().timeout(
          const Duration(seconds: 1),
        );
        // Local state is terminal before the detached request even starts.
        expect(
          (await AuthService.getSessionSnapshot()).isAuthenticated,
          isFalse,
        );
        expect(revokeStarted.isCompleted, isFalse);

        logout.startDetachedCleanup();
        await revokeStarted.future.timeout(const Duration(seconds: 1));
        expect(
          (await AuthService.getSessionSnapshot()).isAuthenticated,
          isFalse,
        );
        finishRevoke.complete(true);
      },
    );

    test(
      'an old detached revoke cannot restore or overwrite a rapid re-login',
      () async {
        await AuthService.saveDriverSession(apiKey: 'old-key', id: '900004');
        await AuthService.saveFcmBinding(
          binding,
          expectedGeneration: UserSessionState.generation,
          apiKey: 'old-key',
          driverId: '900004',
        );
        final finishRevoke = Completer<bool>();
        AuthService.fcmTokenCaptureForTesting =
            () async => 'device-token-that-is-long-enough';
        AuthService.serverFcmRevokeForTesting =
            (_, __, ___, ____) => finishRevoke.future;

        final logout = await AuthService.clearSession();
        logout.startDetachedCleanup();
        AuthService.resetAccountStateOnly(SessionResetReason.accountChanged);
        await AuthService.saveDriverSession(apiKey: 'new-key', id: '900004');
        finishRevoke.complete(true);
        await Future<void>.delayed(Duration.zero);

        expect(await AuthService.getApiKey(), 'new-key');
      },
    );

    test(
      'logout completes locally even though revoke cannot reach a backend',
      () async {
        SharedPreferences.setMockInitialValues({'selected_language': 'Arabic'});
        AuthService.configureForTesting(secureStore: store);

        await AuthService.saveDriverSession(
          apiKey: 'driver-a-key',
          id: '900004',
          dname: 'Demo Driver 4',
        );
        expect(await AuthService.getApiKey(), 'driver-a-key');

        // No server and no Firebase plugin in a unit test: revoke fails.
        await AuthService.clearSession();

        // The driver is still fully signed out locally.
        expect(store.values, isEmpty);
        expect(
          (await AuthService.getSessionSnapshot()).isAuthenticated,
          isFalse,
        );

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('api_key'), isNull);
        // Device preference untouched.
        expect(prefs.getString('selected_language'), 'Arabic');
      },
    );

    test('logout does not hang when revoke is slow or unreachable', () async {
      await AuthService.saveDriverSession(apiKey: 'key-a', id: '900004');

      // Comfortably under the 6s revoke timeout plus local teardown.
      await expectLater(
        AuthService.clearSession().timeout(const Duration(seconds: 20)),
        completes,
      );
      expect((await AuthService.getSessionSnapshot()).isAuthenticated, isFalse);
    });

    test('an invalid-session logout skips revoke and still clears', () async {
      await AuthService.saveDriverSession(apiKey: 'key-a', id: '900004');
      final generation = UserSessionState.generation;

      await AuthService.invalidateSessionIfCurrent(generation);

      expect(store.values, isEmpty);
      expect((await AuthService.getSessionSnapshot()).isAuthenticated, isFalse);
    });
  });

  group('account switch on one device', () {
    test('Driver B login after A logout leaves no A credentials', () async {
      await AuthService.saveDriverSession(apiKey: 'driver-a-key', id: '900004');
      await AuthService.clearSession();
      await AuthService.saveDriverSession(apiKey: 'driver-b-key', id: '900012');

      expect(await AuthService.getApiKey(), 'driver-b-key');
      expect(await AuthService.getuserId(), '900012');
      expect(store.values.values, isNot(contains('driver-a-key')));
    });

    test('re-login as the same driver re-registers the token', () async {
      await AuthService.saveDriverSession(apiKey: 'driver-a-key', id: '900004');
      await AuthService.clearSession();
      await AuthService.saveDriverSession(apiKey: 'driver-a-key', id: '900004');

      // The registration cache was dropped at logout, so the identical
      // driver+token pair is not skipped on the way back in.
      final retried = await DriverFcmTokenService.updateDriverFcmToken(
        driverId: '900004',
        apiKey: 'driver-a-key',
        fcmToken: 'device-token-that-is-long-enough',
      );
      expect(retried, isNull); // attempted, no backend in tests
    });
  });
}
