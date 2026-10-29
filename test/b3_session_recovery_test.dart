// B3 release blocker closure: dead-key session recovery.
//
// Device testing in B3 (B3_RELEASE_CANDIDATE_QA_REPORT.md, B3-F1/F2) showed
// that after a key rotation or deactivation the app kept the rejected key,
// never reached Login, and could not log out, because the teardown awaited an
// FCM topic unsubscribe (which waits indefinitely without connectivity) before
// erasing the credentials. These tests pin the fixed behaviour:
//  - credentials are erased without waiting for FCM; topic cleanup is bounded;
//  - a server-ended session goes to Login exactly once;
//  - only a server-confirmed dead session ends it (401, 403 INVALID_API_KEY,
//    403 DRIVER_INACTIVE) - never a subscription refusal, a 500 or a timeout;
//  - nothing keyed to the old session keeps polling or restores it.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:blockatie/provider/chat/driver_chat_launcher_provider.dart';
import 'package:blockatie/provider/order_location.dart';
import 'package:blockatie/services/auth_secure_store.dart';
import 'package:blockatie/services/auth_services.dart';
import 'package:blockatie/services/session_dio.dart';
import 'package:blockatie/services/user_session_state.dart';
import 'package:blockatie/utils/nav.dart';
import 'package:blockatie/utils/session_redirect.dart';
import 'package:blockatie/views/bottmsheets/logout_sheet.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeSecureStore implements AuthSecureStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

/// Answers every request with the next scripted reply (status + JSON body),
/// or a timeout when the status is 0.
class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this.replies);

  final List<(int, Map<String, Object?>)> replies;
  int requests = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests++;
    final (status, body) =
        replies.length > 1 ? replies.removeAt(0) : replies.first;
    if (status == 0) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.receiveTimeout,
      );
    }
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Map<String, Object?> _code(String code) => {'success': false, 'code': code};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeSecureStore store;
  late int redirects;
  late List<String> cleanedTopicsFor;
  late Completer<void> fcm;

  Future<void> signIn() async {
    await AuthService.saveDriverSession(
      apiKey: 'b3-key-9301',
      id: '9301',
      dname: 'B3 Synthetic Driver',
    );
  }

  bool signedIn() =>
      store.values['driver_api_key'] != null ||
      store.values['driver_session_id'] != null;

  /// A Dio with the app's session interceptor and a scripted backend.
  Dio dioWith(List<(int, Map<String, Object?>)> replies) =>
      protectSessionDio(Dio()..httpClientAdapter = _ScriptedAdapter(replies));

  Future<void> call(Dio dio) async {
    try {
      await dio.post('https://staging.invalid/services/any.php');
    } on DioException {
      // The interceptor acts on the response; the caller's error is expected.
    }
  }

  setUp(() async {
    store = _FakeSecureStore();
    SharedPreferences.setMockInitialValues({'selected_language': 'Arabic'});
    AuthService.configureForTesting(secureStore: store);
    SessionRedirect.resetForTesting();
    redirects = 0;
    SessionRedirect.navigateForTesting = () => redirects++;
    cleanedTopicsFor = [];
    // FCM that never answers, like a device with no route to Google.
    fcm = Completer<void>();
    AuthService.topicCleanupForTesting = (driverId) {
      cleanedTopicsFor.add(driverId);
      return fcm.future;
    };
    await signIn();
  });

  tearDown(() {
    AuthService.resetForTesting();
    SessionRedirect.resetForTesting();
  });

  group('teardown never waits for FCM', () {
    test(
      'R1. a rejected key is erased and Login opens once although FCM never answers',
      () async {
        final generation = UserSessionState.generation;

        await AuthService.invalidateSessionIfCurrent(
          generation,
        ).timeout(const Duration(seconds: 2));

        expect(signedIn(), isFalse);
        expect(
          (await AuthService.getSessionSnapshot()).isAuthenticated,
          isFalse,
        );
        expect(redirects, 1);
        expect(cleanedTopicsFor, ['9301']);
        expect(UserSessionState.generation, generation + 1);
        expect(UserSessionState.lastReason, SessionResetReason.invalidSession);
        // A device preference survives the teardown.
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('selected_language'), 'Arabic');
      },
    );

    test(
      'R2. an explicit logout completes offline; its own screen navigates',
      () async {
        final logout = await AuthService.clearSession().timeout(
          const Duration(seconds: 20),
        );
        // The logout sheet starts this only after Login navigation.
        logout.startDetachedCleanup();

        expect(signedIn(), isFalse);
        expect(redirects, 0, reason: 'the logout sheet owns this redirect');
        expect(cleanedTopicsFor, ['9301']);
      },
    );

    test(
      'R3. a topic cleanup that throws does not disturb the teardown',
      () async {
        AuthService.topicCleanupForTesting =
            (_) => Future<void>.error(StateError('fcm down'));

        await AuthService.invalidateSessionIfCurrent(
          UserSessionState.generation,
        );

        expect(signedIn(), isFalse);
        expect(redirects, 1);
      },
    );

    test('R4. a cleanup that throws synchronously is also contained', () async {
      AuthService.topicCleanupForTesting = (_) => throw StateError('sync');

      await AuthService.invalidateSessionIfCurrent(UserSessionState.generation);

      expect(signedIn(), isFalse);
      expect(redirects, 1);
    });

    test('R5. the cleanup is abandoned after its bound (real 5 s)', () async {
      final logs = <String>[];
      final original = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) logs.add(message);
      };
      addTearDown(() => debugPrint = original);

      await AuthService.invalidateSessionIfCurrent(UserSessionState.generation);
      expect(signedIn(), isFalse);
      Iterable<String> abandoned() =>
          logs.where((l) => l.startsWith('Topic cleanup abandoned'));
      expect(abandoned(), isEmpty);

      await Future<void>.delayed(const Duration(seconds: 6));
      // Earlier tests' cleanups (same isolate) may also expire in this wait.
      expect(abandoned(), isNotEmpty);
      expect(abandoned().every((l) => l.contains('TimeoutException')), isTrue);
    });
  });

  group('one teardown, one redirect', () {
    test(
      'C1. concurrent rejections share one teardown and one redirect',
      () async {
        final generation = UserSessionState.generation;

        await Future.wait([
          AuthService.invalidateSessionIfCurrent(generation),
          AuthService.invalidateSessionIfCurrent(generation),
          AuthService.invalidateSessionIfCurrent(
            generation,
            reason: SessionResetReason.accountInactive,
          ),
        ]).timeout(const Duration(seconds: 20));

        expect(signedIn(), isFalse);
        expect(UserSessionState.generation, generation + 1);
        expect(redirects, 1);
        expect(cleanedTopicsFor, ['9301']);
      },
    );

    test(
      'C1b. a rejection arriving during an explicit logout joins it',
      () async {
        final generation = UserSessionState.generation;

        final logout = AuthService.clearSession();
        final rejection = AuthService.invalidateSessionIfCurrent(generation);
        await Future.wait([
          logout,
          rejection,
        ]).timeout(const Duration(seconds: 20));
        (await logout).startDetachedCleanup();

        expect(signedIn(), isFalse);
        expect(UserSessionState.generation, generation + 1);
        // The logout's own screen navigates (L3 covers the sheet), so the
        // network layer adds no second redirect.
        expect(redirects, 0);
        expect(cleanedTopicsFor, ['9301']);
      },
    );

    test('C2. rapid repeated logouts end the session once', () async {
      final generation = UserSessionState.generation;

      final logouts = await Future.wait([
        for (var i = 0; i < 5; i++) AuthService.clearSession(),
      ]).timeout(const Duration(seconds: 20));
      logouts.first.startDetachedCleanup();

      expect(signedIn(), isFalse);
      expect(UserSessionState.generation, generation + 1);
      expect(cleanedTopicsFor, ['9301']);
    });

    test(
      'C3. a keyless request after the teardown starts nothing new',
      () async {
        await AuthService.invalidateSessionIfCurrent(
          UserSessionState.generation,
        );
        final after = UserSessionState.generation;

        // A request sent after the erase carries no key; its 401 must not end
        // the (already ended) session again or redirect a second time.
        await AuthService.invalidateSessionIfCurrent(after);

        expect(UserSessionState.generation, after);
        expect(redirects, 1);
      },
    );

    test('C4. a late rejection of an older session is ignored', () async {
      final stale = UserSessionState.generation - 1;

      await AuthService.invalidateSessionIfCurrent(stale);

      expect(signedIn(), isTrue);
      expect(redirects, 0);
    });

    test(
      'C5. the next driver may be sent to Login again after their own session ends',
      () async {
        await AuthService.invalidateSessionIfCurrent(
          UserSessionState.generation,
        );
        expect(redirects, 1);

        // Login resets driver state before publishing the new session.
        AuthService.resetAccountStateOnly(SessionResetReason.accountChanged);
        await signIn();
        await AuthService.invalidateSessionIfCurrent(
          UserSessionState.generation,
        );

        expect(redirects, 2);
      },
    );

    test(
      'C6. a slow cleanup finishing after a new login leaves it intact',
      () async {
        await AuthService.invalidateSessionIfCurrent(
          UserSessionState.generation,
        );
        AuthService.resetAccountStateOnly(SessionResetReason.accountChanged);
        await signIn();

        fcm.complete();
        await Future<void>.delayed(Duration.zero);

        expect(await AuthService.getApiKey(), 'b3-key-9301');
        expect(await AuthService.getuserId(), '9301');
      },
    );
  });

  group('only a server-confirmed dead session ends it', () {
    test(
      'N1. revoked key on launch: concurrent 401s, one teardown, one redirect',
      () async {
        final adapter = _ScriptedAdapter([(401, _code('INVALID_DRIVER_AUTH'))]);
        final dio = protectSessionDio(Dio()..httpClientAdapter = adapter);

        await Future.wait([call(dio), call(dio), call(dio)]);
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(signedIn(), isFalse);
        expect(redirects, 1);
        expect(UserSessionState.lastReason, SessionResetReason.invalidSession);
      },
    );

    test('N2. key rotation: 403 INVALID_API_KEY ends the session', () async {
      await call(dioWith([(403, _code('INVALID_API_KEY'))]));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(signedIn(), isFalse);
      expect(redirects, 1);
    });

    test(
      'N3. 403 DRIVER_INACTIVE ends the session as accountInactive',
      () async {
        await call(dioWith([(403, _code('DRIVER_INACTIVE'))]));
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(signedIn(), isFalse);
        expect(redirects, 1);
        expect(UserSessionState.lastReason, SessionResetReason.accountInactive);
      },
    );

    for (final (label, status, body) in [
      ('inactive subscription', 403, _code('DRIVER_SUBSCRIPTION_INACTIVE')),
      ('not assigned', 403, _code('NOT_ASSIGNED')),
      ('HTTP 500', 500, _code('SERVER_ERROR')),
      ('HTTP 503', 503, <String, Object?>{'message': 'maintenance'}),
      ('a timeout', 0, <String, Object?>{}),
    ]) {
      test('N4. $label keeps the driver signed in', () async {
        final generation = UserSessionState.generation;

        await call(dioWith([(status, body)]));
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(signedIn(), isTrue);
        expect(UserSessionState.generation, generation);
        expect(redirects, 0);
      });
    }

    test('N5. after the teardown, further 401s stay quiet', () async {
      await call(dioWith([(401, _code('INVALID_DRIVER_AUTH'))]));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final generation = UserSessionState.generation;

      await call(dioWith([(401, _code('API_KEY_MISSING'))]));
      await call(dioWith([(401, _code('API_KEY_MISSING'))]));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(UserSessionState.generation, generation);
      expect(redirects, 1);
    });
  });

  group('no authorized work survives the teardown', () {
    test(
      'P1. the chat launcher sees the erased session and stops the poller',
      () async {
        final launcher = DriverChatLauncherProvider();
        addTearDown(launcher.dispose);
        await launcher.syncSession();
        expect(launcher.isAuthenticated, isTrue);

        await AuthService.invalidateSessionIfCurrent(
          UserSessionState.generation,
        );
        await launcher.syncSession();

        expect(launcher.isAuthenticated, isFalse);
      },
    );

    test('P2. the location timer is stopped by the reset', () async {
      final location = OrderLocationProvider();
      addTearDown(location.dispose);

      await AuthService.invalidateSessionIfCurrent(UserSessionState.generation);

      expect(location.isTracking, isFalse);
    });
  });

  group('logout sheet', () {
    Widget host() => MultiProvider(
      providers: [
        ChangeNotifierProvider<OrderLocationProvider>(
          create: (_) => OrderLocationProvider(),
        ),
      ],
      child: MaterialApp(
        navigatorKey: Nav.key,
        home: Builder(
          builder:
              (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => showLogoutSheet(context),
                    child: const Text('open'),
                  ),
                ),
              ),
        ),
      ),
    );

    /// Interleaves the real async work (the revoke HTTP call, the secure
    /// store) with fake frames until the sheet's teardown is over, then moves
    /// fake time past the revoke (6 s) and topic-cleanup (5 s) bounds so no
    /// timer is left pending.
    Future<void> runTeardown(WidgetTester tester) async {
      for (var i = 0; i < 40; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump(const Duration(milliseconds: 50));
        if (!signedIn() &&
            find.text('Do you want to log out?').evaluate().isEmpty) {
          break;
        }
      }
      await tester.pump(const Duration(seconds: 7));
    }

    Future<void> openSheet(WidgetTester tester) async {
      await tester.pumpWidget(host());
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('L1. logout with FCM unreachable finishes and redirects once', (
      tester,
    ) async {
      await openSheet(tester);

      await tester.tap(find.bySemanticsLabel('Confirm sign out').first);
      await runTeardown(tester);

      expect(signedIn(), isFalse);
      expect(redirects, 1);
      expect(find.text('Do you want to log out?'), findsNothing);
    });

    testWidgets('L2. tapping Logout repeatedly still redirects once', (
      tester,
    ) async {
      await openSheet(tester);

      final confirm = find.bySemanticsLabel('Confirm sign out').first;
      await tester.tap(confirm);
      await tester.tap(confirm, warnIfMissed: false);
      await tester.tap(confirm, warnIfMissed: false);
      await runTeardown(tester);

      expect(signedIn(), isFalse);
      expect(redirects, 1);
    });

    testWidgets('L3. Logout during a server-ended teardown redirects once', (
      tester,
    ) async {
      await openSheet(tester);

      // The network layer ends the session while the sheet is open.
      unawaited(
        AuthService.invalidateSessionIfCurrent(UserSessionState.generation),
      );
      await tester.tap(
        find.bySemanticsLabel('Confirm sign out').first,
        warnIfMissed: false,
      );
      await runTeardown(tester);

      expect(signedIn(), isFalse);
      expect(redirects, 1);
    });
  });
}
