import 'dart:convert';

import 'package:dio/dio.dart';

import 'auth_services.dart';
import 'user_session_state.dart';

/// Network-layer half of the session boundary.
///
/// Every request is stamped with the session generation that issued it. If the
/// driver session changes while the request is in flight, the response is
/// rejected here instead of reaching provider state. This backstops the
/// per-provider generation checks so a missed guard cannot leak data.
Dio sessionDio([BaseOptions? options]) => protectSessionDio(Dio(options));

Dio protectSessionDio(Dio dio) {
  if (dio.interceptors.any((item) => item is _SessionInterceptor)) return dio;
  dio.interceptors.add(_SessionInterceptor());
  return dio;
}

/// Marks a request whose own response must never end the session.
///
/// The logout/token-revoke call is the one request made *during* teardown, with
/// a credential the backend has already refused elsewhere. Without this flag its
/// 401 or 403 would re-enter the interceptor, start another teardown, and revoke
/// again — indefinitely. Set it via
/// `Options(extra: {sessionExemptFromInvalidation: true})`.
const String sessionExemptFromInvalidation =
    'blockatie.driver.sessionExemptFromInvalidation';

class _SessionInterceptor extends Interceptor {
  static const _generation = 'blockatie.driver.sessionGeneration';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra[_generation] = UserSessionState.generation;
    handler.next(options);
  }

  bool _stale(RequestOptions options) =>
      options.extra.containsKey(_generation) &&
      options.extra[_generation] != UserSessionState.generation;

  /// Backend code meaning the account itself may no longer hold a session.
  ///
  /// Returned once an Admin disables or deletes the driver, at which point the
  /// stored API key must stop working even though it is still well-formed.
  static const _accountEndedCode = 'DRIVER_INACTIVE';

  /// Backend code for a key the server no longer accepts. Some endpoints send
  /// it with 403 rather than 401; after a password change rotated the key it
  /// must end the session the same way.
  static const _keyRefusedCode = 'INVALID_API_KEY';

  /// Reads the Backend `code` field whether the body arrived parsed or as text.
  static String? _responseCode(dynamic data) {
    var body = data;
    if (body is String) {
      if (body.isEmpty) return null;
      try {
        body = jsonDecode(body);
      } catch (_) {
        return null;
      }
    }
    if (body is Map) {
      final code = body['code'];
      if (code is String) return code;
    }
    return null;
  }

  /// How a response ends the session, or null if it does not end it.
  ///
  /// A 401 always qualifies: the key was not accepted at all. A 403 qualifies
  /// only for [_accountEndedCode], because the app also receives 403 for
  /// per-request authorization failures — a shipment belonging to another
  /// driver, a mismatched driver_id, an inactive subscription — and signing the
  /// driver out on those would be wrong.
  ///
  /// The two are kept apart because the credential's remaining usefulness
  /// differs: after a 401 the key is dead, while [_accountEndedCode] means the
  /// key still authenticates a disabled account — enough to release this
  /// device's FCM token before the credential is erased.
  static SessionResetReason? _endReason(Response<dynamic>? response) {
    final status = response?.statusCode;
    if (status == 401) return SessionResetReason.invalidSession;
    if (status != 403) return null;
    final code = _responseCode(response?.data);
    if (code == _keyRefusedCode) return SessionResetReason.invalidSession;
    return code == _accountEndedCode ? SessionResetReason.accountInactive : null;
  }

  /// Invalidates the session only if this response answers the current one.
  Future<void> _check(
    Response<dynamic>? response,
    RequestOptions options,
  ) async {
    // The teardown request itself must not start another teardown.
    if (options.extra[sessionExemptFromInvalidation] == true) return;

    final generation = options.extra[_generation];
    final reason = _endReason(response);
    if (generation is int && reason != null) {
      await AuthService.invalidateSessionIfCurrent(generation, reason: reason);
    }
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) async {
    try {
      await _check(response, response.requestOptions);
    } catch (_) {
      // Invalidation is best effort; it must not mask the response path.
    }
    if (_stale(response.requestOptions)) {
      handler.reject(
        DioException(
          requestOptions: response.requestOptions,
          type: DioExceptionType.cancel,
          error: const SessionChanged(),
        ),
      );
      return;
    }
    handler.next(response);
  }

  @override
  void onError(DioException error, ErrorInterceptorHandler handler) async {
    try {
      await _check(error.response, error.requestOptions);
    } catch (_) {
      // Ignore: the original error still propagates below.
    }
    handler.next(error);
  }
}
