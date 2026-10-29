import 'package:blockatie/constants/app_urls.dart';
import 'package:dio/dio.dart';

import 'session_dio.dart';
import 'package:flutter/foundation.dart';

class DriverFcmTokenService {
  DriverFcmTokenService._();

  static final Dio _dio = sessionDio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      sendTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      responseType: ResponseType.json,
      validateStatus: (_) => true,
    ),
  );
  static String? _lastSuccessfulRegistrationKey;

  /// Registers this device's token, and optionally the driver's push language.
  ///
  /// [language] must already be canonical — 'ar' or 'en'. The backend refuses
  /// anything else, and it is the only thing that stops a push being written in
  /// whatever language the Admin happened to be using. Identity still comes
  /// from the API key; the language never widens what this call can do.
  static Future<DriverFcmRegistration?> updateDriverFcmToken({
    required String driverId,
    required String apiKey,
    required String fcmToken,
    String? language,
  }) async {
    final normalizedDriverId = driverId.trim();
    final normalizedApiKey = apiKey.trim();
    final normalizedToken = fcmToken.trim();

    if (normalizedDriverId.isEmpty ||
        normalizedApiKey.isEmpty ||
        normalizedToken.isEmpty) {
      debugPrint('FCM token registration skipped: missing session or token.');
      return null;
    }

    if (normalizedToken.length < 20) {
      debugPrint('FCM token registration skipped: token unavailable.');
      return null;
    }

    // The language is part of the key, so switching language re-registers
    // rather than being swallowed as "already registered".
    final registrationKey = _registrationKey(
      normalizedDriverId,
      normalizedToken,
      language,
    );
    if (_lastSuccessfulRegistrationKey == registrationKey) {
      return const DriverFcmRegistration.cached();
    }

    try {
      final response = await _dio.post(
        AppUrls.updateDriverFcmToken,
        options: Options(
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
            'X-API-KEY': normalizedApiKey,
          },
        ),
        data: {
          'driver_id': normalizedDriverId,
          'fcm_token': normalizedToken,
          if (language != null && language.isNotEmpty) 'language': language,
        },
      );

      final data = response.data;
      final binding = _bindingFromResponse(data);
      final success = response.statusCode == 200 && _isSuccess(data);
      if (success && binding != null) {
        _lastSuccessfulRegistrationKey = registrationKey;
        debugPrint('FCM token registration succeeded.');
        return DriverFcmRegistration(binding);
      } else if (success) {
        // A response from a server that has not yet received the binding
        // migration is not safe to treat as registered: logout would have no
        // fence and must never fall back to a blind revoke.
        debugPrint('FCM token registration rejected: binding unavailable.');
      } else {
        debugPrint(
          'FCM token registration failed: '
          'status=${response.statusCode} code=${_safeCode(data)}',
        );
      }
      return null;
    } catch (e) {
      debugPrint('FCM token registration failed: ${e.runtimeType}');
      return null;
    }
  }

  /// Releases this device's token from the authenticated driver, server-side.
  ///
  /// Best effort: a failure here must never block logout, so every error path
  /// returns false rather than throwing. The API key identifies the driver; no
  /// driver_id is sent and the endpoint rejects one.
  static Future<bool> revokeDriverFcmToken({
    required String apiKey,
    required String fcmToken,
    required String binding,
    Duration timeout = const Duration(seconds: 6),
  }) async {
    final normalizedApiKey = apiKey.trim();
    if (normalizedApiKey.isEmpty) {
      debugPrint('FCM token revoke skipped: missing session.');
      return false;
    }

    final normalizedToken = fcmToken.trim();
    final normalizedBinding = binding.trim();
    if (normalizedToken.isEmpty || !_isBinding(normalizedBinding)) {
      debugPrint('FCM token revoke skipped: binding context unavailable.');
      return false;
    }

    final cancelToken = CancelToken();
    try {
      final response = await _dio
          .post(
            AppUrls.driverLogout,
            options: Options(
              headers: {
                'Content-Type': 'application/x-www-form-urlencoded',
                'X-API-KEY': normalizedApiKey,
              },
              // This call runs during teardown, with a credential the backend has
              // already refused elsewhere. Its own 401/403 must not start another
              // teardown, which would revoke again, and again.
              extra: const {sessionExemptFromInvalidation: true},
            ),
            data: {
              'fcm_token': normalizedToken,
              'fcm_binding': normalizedBinding,
            },
            cancelToken: cancelToken,
          )
          .timeout(
            timeout,
            onTimeout: () {
              // Dio cancellation stops the pending HTTP request rather than
              // merely abandoning its Future. The server binding fence still
              // protects the rare request already on the wire.
              cancelToken.cancel('logout revoke timed out');
              return Response(
                requestOptions: RequestOptions(path: AppUrls.driverLogout),
                statusCode: 0,
              );
            },
          );

      final data = response.data;
      final success = response.statusCode == 200 && _isSuccess(data);
      debugPrint(
        success
            ? 'FCM token revoke succeeded.'
            : 'FCM token revoke failed: '
                'status=${response.statusCode} code=${_safeCode(data)}',
      );
      return success;
    } catch (e) {
      debugPrint('FCM token revoke failed: ${e.runtimeType}');
      return false;
    } finally {
      // The server row is now released, so the next login on this device must
      // re-register even if the driver and token are unchanged.
      clearRegistrationCache();
    }
  }

  /// Drops the de-duplication cache so a re-login re-registers the token.
  static void clearRegistrationCache() {
    _lastSuccessfulRegistrationKey = null;
  }

  static bool _isSuccess(dynamic data) {
    if (data is! Map) return false;

    final success = data['success']?.toString().trim().toLowerCase();
    final status = data['status']?.toString().trim().toLowerCase();
    final code = data['code']?.toString().trim().toUpperCase();

    return data['success'] == true ||
        success == 'true' ||
        success == '1' ||
        status == 'success' ||
        code == 'FCM_TOKEN_UPDATED' ||
        code == 'LOGGED_OUT';
  }

  static String? _bindingFromResponse(dynamic data) {
    if (data is! Map) return null;
    final binding = data['fcm_binding']?.toString().trim() ?? '';
    return _isBinding(binding) ? binding : null;
  }

  static bool _isBinding(String value) =>
      RegExp(r'^[a-f0-9]{64}$', caseSensitive: false).hasMatch(value);

  static String _registrationKey(
    String driverId,
    String token,
    String? language,
  ) {
    return '$driverId:${token.hashCode}:${language ?? ''}';
  }

  static String _safeCode(dynamic data) {
    if (data is! Map) return 'unknown';
    return data['code']?.toString() ?? data['status']?.toString() ?? 'unknown';
  }
}

/// Result of a successfully fenced server registration. The opaque binding is
/// stored only in encrypted local storage and sent back only for its matching
/// logout request; it is never written to logs.
class DriverFcmRegistration {
  const DriverFcmRegistration(this.binding) : isCached = false;
  const DriverFcmRegistration.cached() : binding = null, isCached = true;

  final String? binding;
  final bool isCached;
}
