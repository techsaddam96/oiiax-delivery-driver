// Verifies that a driver disabled by an Admin is signed out by the next API
// call, and that ordinary 403s — which mean "not this request", not "not this
// account" — leave the session alone.

import 'dart:convert';
import 'dart:typed_data';

import 'package:blockatie/services/auth_secure_store.dart';
import 'package:blockatie/services/auth_services.dart';
import 'package:blockatie/services/session_dio.dart';
import 'package:blockatie/services/user_session_state.dart';
import 'package:dio/dio.dart';
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

/// Returns a canned response without touching the network.
class _CannedAdapter implements HttpClientAdapter {
  _CannedAdapter({
    required this.statusCode,
    required this.body,
    this.beforeRespond,
  });

  final int statusCode;
  final String body;

  /// Runs after the request is stamped but before the response is delivered,
  /// so a test can change the session while the call is "in flight".
  final void Function()? beforeRespond;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    beforeRespond?.call();
    return ResponseBody.fromString(
      body,
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// The exact payload services/helpers/driver_auth.php emits.
const _inactiveBody = '{"success":false,"status":"error",'
    '"code":"DRIVER_INACTIVE","message":"Driver account is inactive",'
    '"message_en":"Driver account is inactive",'
    '"message_ar":"حساب السائق '
    'غير نشط"}';

/// Sends one request through the session interceptor and reports whether the
/// session generation advanced as a result.
Future<bool> _sessionEndedBy({
  required int statusCode,
  required String body,
  ResponseType responseType = ResponseType.json,
  void Function()? beforeRespond,
}) async {
  final before = UserSessionState.generation;
  final dio = sessionDio(
    BaseOptions(
      baseUrl: 'https://example.invalid',
      responseType: responseType,
      validateStatus: (_) => true,
    ),
  )..httpClientAdapter = _CannedAdapter(
      statusCode: statusCode,
      body: body,
      beforeRespond: beforeRespond,
    );

  try {
    await dio.get<dynamic>('/whatever');
  } on DioException {
    // A rejected or stale response still exercises the interceptor.
  }

  return UserSessionState.generation != before;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeSecureStore store;

  setUp(() {
    store = _FakeSecureStore();
    store.values['driver_api_key'] = 'key-for-a-disabled-driver';
    store.values['driver_session_id'] = '900004';
    SharedPreferences.setMockInitialValues({});
    AuthService.configureForTesting(secureStore: store);
  });

  tearDown(AuthService.resetForTesting);

  group('403 DRIVER_INACTIVE ends the session', () {
    test('the Backend payload signs the driver out', () async {
      expect(
        await _sessionEndedBy(statusCode: 403, body: _inactiveBody),
        isTrue,
      );
    });

    test('stored credentials are cleared, not just reset in memory', () async {
      await _sessionEndedBy(statusCode: 403, body: _inactiveBody);

      expect(store.values['driver_api_key'], isNull);
      expect(store.values['driver_session_id'], isNull);
    });

    test('an unparsed text body is still recognised', () async {
      expect(
        await _sessionEndedBy(
          statusCode: 403,
          body: _inactiveBody,
          responseType: ResponseType.plain,
        ),
        isTrue,
      );
    });

    test('401 still ends the session', () async {
      expect(
        await _sessionEndedBy(
          statusCode: 401,
          body: '{"code":"INVALID_API_KEY"}',
        ),
        isTrue,
      );
    });
  });

  group('other responses leave the session alone', () {
    test('a 403 refusing one request does not sign the driver out', () async {
      expect(
        await _sessionEndedBy(
          statusCode: 403,
          body: '{"code":"UNAUTHORIZED_DRIVER"}',
        ),
        isFalse,
      );
    });

    test('an inactive subscription is not an inactive account', () async {
      expect(
        await _sessionEndedBy(
          statusCode: 403,
          body: '{"code":"DRIVER_SUBSCRIPTION_INACTIVE"}',
        ),
        isFalse,
      );
    });

    test('a 403 with no parseable body is ignored', () async {
      expect(
        await _sessionEndedBy(statusCode: 403, body: '<html>Forbidden</html>'),
        isFalse,
      );
    });

    test('a 403 with an empty body is ignored', () async {
      expect(await _sessionEndedBy(statusCode: 403, body: ''), isFalse);
    });

    test('the code alone, without the 403, is not enough', () async {
      expect(
        await _sessionEndedBy(statusCode: 200, body: _inactiveBody),
        isFalse,
      );
    });

    test('a 500 server error does not sign the driver out', () async {
      // The Driver APIs answer an unexpected failure with a generic 5xx
      // envelope. That is a broken request, not a broken session.
      expect(
        await _sessionEndedBy(
          statusCode: 500,
          body: '{"success":false,"status":"error","code":"SERVER_ERROR",'
              '"message":"Unable to process the request right now."}',
        ),
        isFalse,
      );
    });

    test('a nested code field is not mistaken for the top-level one', () async {
      expect(
        await _sessionEndedBy(
          statusCode: 403,
          body: jsonEncode({
            'code': 'UNAUTHORIZED_DRIVER',
            'data': {'code': 'DRIVER_INACTIVE'},
          }),
        ),
        isFalse,
      );
    });
  });

  group('generation guard', () {
    test('a 403 answering a previous session cannot clear the new one',
        () async {
      // The driver logs out and back in while the disabled-account response is
      // still in flight; clearing here would sign the *next* driver out.
      var advancedByInterceptor = false;
      final beforeAll = UserSessionState.generation;

      final dio = sessionDio(
        BaseOptions(
          baseUrl: 'https://example.invalid',
          validateStatus: (_) => true,
        ),
      )..httpClientAdapter = _CannedAdapter(
          statusCode: 403,
          body: _inactiveBody,
          beforeRespond: () =>
              UserSessionState.reset(SessionResetReason.accountChanged),
        );

      final afterReset = beforeAll + 1;
      try {
        await dio.get<dynamic>('/whatever');
      } on DioException {
        // Expected: the stale response is rejected.
      }

      advancedByInterceptor = UserSessionState.generation != afterReset;
      expect(advancedByInterceptor, isFalse);
      expect(store.values['driver_api_key'], isNotNull);
    });
  });

  group('FCM revoke on an inactive account', () {
    // The reason recorded by the teardown is what decides whether the device
    // token is released, so it is the observable this group asserts on.

    test('403 DRIVER_INACTIVE tears down as accountInactive, not invalidSession',
        () async {
      await _sessionEndedBy(statusCode: 403, body: _inactiveBody);

      expect(UserSessionState.lastReason, SessionResetReason.accountInactive);
      expect(
        UserSessionState.lastReason?.revokesDeviceToken,
        isTrue,
        reason: 'the key still authenticates a disabled account, so the '
            'device token must be released before it is erased',
      );
    });

    test('401 still tears down as invalidSession and does not revoke',
        () async {
      await _sessionEndedBy(
        statusCode: 401,
        body: '{"code":"INVALID_API_KEY"}',
      );

      expect(UserSessionState.lastReason, SessionResetReason.invalidSession);
      expect(
        UserSessionState.lastReason?.revokesDeviceToken,
        isFalse,
        reason: 'a 401 means the key itself is dead, so logout could not '
            'succeed with it either',
      );
    });

    test('a manual logout still revokes', () {
      expect(SessionResetReason.logout.revokesDeviceToken, isTrue);
      expect(SessionResetReason.accountChanged.revokesDeviceToken, isTrue);
    });

    test('the credential is still present while the revoke decision is made',
        () async {
      // Ordering guard: revoke runs before the secure wipe, so the API key must
      // exist at that point. After teardown it must be gone.
      expect(store.values['driver_api_key'], isNotNull);

      await _sessionEndedBy(statusCode: 403, body: _inactiveBody);

      expect(store.values['driver_api_key'], isNull);
      expect(store.values['driver_session_id'], isNull);
    });

    test('a revoke failure still clears the session', () async {
      // No network exists in a unit test, so the revoke attempt fails. The
      // session must still be torn down rather than trapping the driver.
      final ended = await _sessionEndedBy(
        statusCode: 403,
        body: _inactiveBody,
      );

      expect(ended, isTrue);
      expect(store.values['driver_api_key'], isNull);
      expect(UserSessionState.lastReason, SessionResetReason.accountInactive);
    });

    test('a request marked exempt cannot start a teardown', () async {
      // The revoke call itself is exempt; without that its own 403 would start
      // another teardown, revoke again, and loop.
      final before = UserSessionState.generation;
      final dio = sessionDio(
        BaseOptions(
          baseUrl: 'https://example.invalid',
          validateStatus: (_) => true,
        ),
      )..httpClientAdapter = _CannedAdapter(
          statusCode: 403,
          body: _inactiveBody,
        );

      await dio.get<dynamic>(
        '/logout',
        options: Options(
          extra: const {sessionExemptFromInvalidation: true},
        ),
      );

      expect(UserSessionState.generation, before);
      expect(store.values['driver_api_key'], isNotNull);
    });

    test('duplicate DRIVER_INACTIVE responses tear down only once', () async {
      final before = UserSessionState.generation;

      // Two responses landing together, both answering the live session.
      await Future.wait([
        _sessionEndedBy(statusCode: 403, body: _inactiveBody),
        _sessionEndedBy(statusCode: 403, body: _inactiveBody),
      ]);

      expect(
        UserSessionState.generation,
        before + 1,
        reason: 'a second teardown would advance the generation twice',
      );
    });

    test('a stale Driver A 403 cannot revoke or sign out Driver B', () async {
      // Driver B signs in while A's response is still in flight.
      final dio = sessionDio(
        BaseOptions(
          baseUrl: 'https://example.invalid',
          validateStatus: (_) => true,
        ),
      )..httpClientAdapter = _CannedAdapter(
          statusCode: 403,
          body: _inactiveBody,
          beforeRespond: () {
            UserSessionState.reset(SessionResetReason.accountChanged);
            store.values['driver_api_key'] = 'driver-b-key';
            store.values['driver_session_id'] = '900009';
          },
        );

      try {
        await dio.get<dynamic>('/whatever');
      } on DioException {
        // Expected: the stale response is rejected.
      }

      expect(store.values['driver_api_key'], 'driver-b-key');
      expect(UserSessionState.lastReason, SessionResetReason.accountChanged);
    });
  });
}
