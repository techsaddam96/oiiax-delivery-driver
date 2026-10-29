import 'package:blockatie/constants/app_urls.dart';
import 'package:blockatie/services/session_dio.dart';
import 'package:dio/dio.dart';

/// Normalized results for the additive Batch 2A endpoint. The service never
/// stores, logs, or retries a capability; lifecycle ownership stays with the
/// user-scoped provider.
enum DriverWorkSessionRemoteState {
  started,
  ended,
  active,
  inactive,
  disabled,
  unavailable,
  unauthorized,
  failed,
}

class DriverWorkSessionRemoteResult {
  const DriverWorkSessionRemoteResult(this.state, {this.capability});

  final DriverWorkSessionRemoteState state;
  final String? capability;

  bool get terminalEnd =>
      state == DriverWorkSessionRemoteState.ended ||
      state == DriverWorkSessionRemoteState.inactive;

  bool get mayUseLegacyLocationFlow =>
      state == DriverWorkSessionRemoteState.disabled ||
      state == DriverWorkSessionRemoteState.unavailable;
}

abstract interface class DriverWorkSessionTransport {
  Future<DriverWorkSessionRemoteResult> start(String apiKey);

  Future<DriverWorkSessionRemoteResult> end(
    String apiKey,
    String capability, {
    required String reason,
  });

  Future<DriverWorkSessionRemoteResult> status(
    String apiKey,
    String capability,
  );
}

class DioDriverWorkSessionTransport implements DriverWorkSessionTransport {
  Dio _client() => sessionDio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      sendTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 12),
      responseType: ResponseType.json,
      validateStatus: (_) => true,
    ),
  );

  Options _options(String apiKey, {String? capability}) => Options(
    headers: {
      'Accept': 'application/json',
      'Content-Type': 'application/x-www-form-urlencoded',
      'X-API-KEY': apiKey,
      if (capability != null && capability.isNotEmpty)
        'X-DRIVER-WORK-SESSION': capability,
    },
  );

  @override
  Future<DriverWorkSessionRemoteResult> start(String apiKey) async {
    try {
      final response = await _client().post(
        AppUrls.driverWorkSession,
        data: const {'action': 'start'},
        options: _options(apiKey),
      );
      final data = response.data;
      final capability = _capability(data);
      if (response.statusCode == 200 &&
          _isSuccess(data) &&
          _isCapability(capability)) {
        return DriverWorkSessionRemoteResult(
          DriverWorkSessionRemoteState.started,
          capability: capability,
        );
      }
      return DriverWorkSessionRemoteResult(
        _stateFor(response.statusCode, data),
      );
    } on DioException {
      return const DriverWorkSessionRemoteResult(
        DriverWorkSessionRemoteState.unavailable,
      );
    } catch (_) {
      return const DriverWorkSessionRemoteResult(
        DriverWorkSessionRemoteState.failed,
      );
    }
  }

  @override
  Future<DriverWorkSessionRemoteResult> end(
    String apiKey,
    String capability, {
    required String reason,
  }) async {
    try {
      final response = await _client().post(
        AppUrls.driverWorkSession,
        data: {'action': 'end', 'reason': reason},
        options: _options(apiKey, capability: capability),
      );
      final data = response.data;
      if (response.statusCode == 200 && _isSuccess(data)) {
        return const DriverWorkSessionRemoteResult(
          DriverWorkSessionRemoteState.ended,
        );
      }
      return DriverWorkSessionRemoteResult(
        _stateFor(response.statusCode, data),
      );
    } on DioException {
      return const DriverWorkSessionRemoteResult(
        DriverWorkSessionRemoteState.unavailable,
      );
    } catch (_) {
      return const DriverWorkSessionRemoteResult(
        DriverWorkSessionRemoteState.failed,
      );
    }
  }

  @override
  Future<DriverWorkSessionRemoteResult> status(
    String apiKey,
    String capability,
  ) async {
    try {
      final response = await _client().post(
        AppUrls.driverWorkSession,
        data: const {'action': 'status'},
        options: _options(apiKey, capability: capability),
      );
      final data = response.data;
      if (response.statusCode == 200 && _isSuccess(data)) {
        return DriverWorkSessionRemoteResult(
          data is Map && data['is_working'] == true
              ? DriverWorkSessionRemoteState.active
              : DriverWorkSessionRemoteState.inactive,
        );
      }
      return DriverWorkSessionRemoteResult(
        _stateFor(response.statusCode, data),
      );
    } on DioException {
      return const DriverWorkSessionRemoteResult(
        DriverWorkSessionRemoteState.unavailable,
      );
    } catch (_) {
      return const DriverWorkSessionRemoteResult(
        DriverWorkSessionRemoteState.failed,
      );
    }
  }

  static bool _isSuccess(dynamic data) =>
      data is Map && (data['success'] == true || data['status'] == 'success');

  static String _capability(dynamic data) =>
      data is Map ? data['session_key']?.toString().trim() ?? '' : '';

  static bool _isCapability(String value) =>
      RegExp(r'^[a-f0-9]{64}$', caseSensitive: false).hasMatch(value);

  static DriverWorkSessionRemoteState _stateFor(int? statusCode, dynamic data) {
    final code = data is Map ? data['code']?.toString() : null;
    if (statusCode == 401 || code == 'AUTH_REQUIRED') {
      return DriverWorkSessionRemoteState.unauthorized;
    }
    if (code == 'WORK_SESSION_DISABLED') {
      return DriverWorkSessionRemoteState.disabled;
    }
    if (code == 'WORK_SESSION_UNAVAILABLE' || statusCode == 503) {
      return DriverWorkSessionRemoteState.unavailable;
    }
    if (code == 'WORK_SESSION_NOT_ACTIVE' ||
        code == 'WORK_SESSION_REQUIRED' ||
        statusCode == 409) {
      return DriverWorkSessionRemoteState.inactive;
    }
    return DriverWorkSessionRemoteState.failed;
  }
}
