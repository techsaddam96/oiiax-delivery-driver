import 'dart:convert';
import 'dart:math';

import 'package:blockatie/constants/app_urls.dart';
import 'package:blockatie/models/driver_tour.dart';
import 'package:blockatie/services/auth_services.dart';
import 'package:blockatie/services/session_dio.dart';
import 'package:blockatie/services/user_session_state.dart';
import 'package:dio/dio.dart';

typedef DriverTourApiKeyLoader = Future<String?> Function();

abstract interface class DriverToursRepository {
  Future<List<DriverTour>> current();

  Future<DriverTourDetails> details(int tourId);

  Future<DriverTourCommandResult> command({
    required String action,
    required int tourId,
    required int expectedStateVersion,
    String? reason,
  });
}

enum DriverTourFailureKind {
  authentication,
  authorization,
  conflict,
  validation,
  network,
  unavailable,
  invalidResponse,
}

/// Safe, app-owned failure detail. Backend prose and request data never leave
/// this service.
class DriverTourException implements Exception {
  const DriverTourException({
    required this.kind,
    required this.code,
    this.statusCode,
    this.isRetryable = false,
  });

  final DriverTourFailureKind kind;
  final String code;
  final int? statusCode;
  final bool isRetryable;

  @override
  String toString() => 'DriverTourException($code, $statusCode)';
}

/// The authenticated Driver Tours API adapter.
///
/// It intentionally sends no driver, employee or actor identifier. Identity
/// and ownership come solely from `X-API-KEY` on the server. Every write is
/// JSON, carries an RFC 4122 v4 UUID as `Idempotency-Key`, and reuses that UUID
/// only while a result is not definitive.
class DriverTourService implements DriverToursRepository {
  DriverTourService({Dio? dio, DriverTourApiKeyLoader? apiKeyLoader})
    : _dio =
          dio ??
          sessionDio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 12),
              receiveTimeout: const Duration(seconds: 15),
              sendTimeout: const Duration(seconds: 15),
              headers: const {'Accept': 'application/json'},
              validateStatus: (_) => true,
            ),
          ),
      _apiKeyLoader = apiKeyLoader ?? AuthService.getApiKey;

  final Dio _dio;
  final DriverTourApiKeyLoader _apiKeyLoader;

  static const _actions = <String>{'start', 'interrupt', 'resume', 'complete'};
  static final Random _random = Random.secure();
  static final Map<String, String> _pendingKeys = <String, String>{};

  @override
  Future<List<DriverTour>> current() async {
    final data = await _request(
      method: 'GET',
      query: const <String, dynamic>{'action': 'current'},
    );
    final rawTours = data['tours'];
    if (rawTours is! List) {
      throw const DriverTourException(
        kind: DriverTourFailureKind.invalidResponse,
        code: 'INVALID_CURRENT_RESPONSE',
      );
    }
    try {
      return rawTours
          .map((row) => _jsonMap(row))
          .map((row) {
            if (row == null) throw const FormatException('tour');
            return DriverTour.fromJson(row);
          })
          .toList(growable: false);
    } on DriverTourContractException {
      throw const DriverTourException(
        kind: DriverTourFailureKind.invalidResponse,
        code: 'INVALID_CURRENT_RESPONSE',
      );
    } on FormatException {
      throw const DriverTourException(
        kind: DriverTourFailureKind.invalidResponse,
        code: 'INVALID_CURRENT_RESPONSE',
      );
    }
  }

  @override
  Future<DriverTourDetails> details(int tourId) async {
    _assertPositive(tourId, 'TOUR_ID');
    final data = await _request(
      method: 'GET',
      query: <String, dynamic>{'action': 'details', 'tour_id': tourId},
    );
    try {
      final details = DriverTourDetails.fromJson(data);
      if (details.tour.id != tourId) {
        throw const DriverTourContractException('TOUR_ID_MISMATCH');
      }
      return details;
    } on DriverTourContractException {
      throw const DriverTourException(
        kind: DriverTourFailureKind.invalidResponse,
        code: 'INVALID_DETAILS_RESPONSE',
      );
    }
  }

  @override
  Future<DriverTourCommandResult> command({
    required String action,
    required int tourId,
    required int expectedStateVersion,
    String? reason,
  }) async {
    if (!_actions.contains(action)) {
      throw const DriverTourException(
        kind: DriverTourFailureKind.validation,
        code: 'INVALID_TOUR_ACTION',
      );
    }
    _assertPositive(tourId, 'TOUR_ID');
    _assertPositive(expectedStateVersion, 'STATE_VERSION');

    final normalizedReason = _normalizeReason(action, reason);
    final payload = <String, dynamic>{
      'action': action,
      'tour_id': tourId,
      'expected_state_version': expectedStateVersion,
      if (normalizedReason != null) 'reason': normalizedReason,
    };
    final retryKey = _retryKey(payload);
    final idempotencyKey = _pendingKeys.putIfAbsent(retryKey, _newUuidV4);
    try {
      final data = await _request(
        method: 'POST',
        body: payload,
        idempotencyKey: idempotencyKey,
      );
      final result = DriverTourCommandResult.fromJson(data);
      if (result.tourId != tourId) {
        throw const DriverTourContractException('TOUR_ID_MISMATCH');
      }
      _pendingKeys.remove(retryKey);
      return result;
    } on DriverTourException catch (error) {
      // Only an interrupted/unknown server outcome needs the same UUID on a
      // manual retry. Conflicts and validation refusals are definitive.
      if (!error.isRetryable) _pendingKeys.remove(retryKey);
      rethrow;
    } on DriverTourContractException {
      _pendingKeys.remove(retryKey);
      throw const DriverTourException(
        kind: DriverTourFailureKind.invalidResponse,
        code: 'INVALID_COMMAND_RESPONSE',
      );
    }
  }

  Future<Map<String, dynamic>> _request({
    required String method,
    Map<String, dynamic>? query,
    Map<String, dynamic>? body,
    String? idempotencyKey,
  }) async {
    final apiKey = (await _apiKeyLoader())?.trim() ?? '';
    if (apiKey.isEmpty) {
      throw const DriverTourException(
        kind: DriverTourFailureKind.authentication,
        code: 'AUTH_REQUIRED',
      );
    }

    try {
      final response = await _dio.request<dynamic>(
        AppUrls.driverTours,
        queryParameters: query,
        data: body,
        options: Options(
          method: method,
          contentType: method == 'POST' ? Headers.jsonContentType : null,
          headers: <String, String>{
            'Accept': 'application/json',
            'X-API-KEY': apiKey,
            if (idempotencyKey != null) 'Idempotency-Key': idempotencyKey,
          },
        ),
      );
      final envelope = _jsonMap(_decode(response.data));
      if (envelope == null) {
        throw const DriverTourException(
          kind: DriverTourFailureKind.invalidResponse,
          code: 'INVALID_TOUR_RESPONSE',
        );
      }
      final success = envelope['success'] == true;
      final data = _jsonMap(envelope['data']);
      final status = response.statusCode;
      if (status == null ||
          status < 200 ||
          status >= 300 ||
          !success ||
          data == null) {
        throw _responseException(status, envelope);
      }
      return data;
    } on DriverTourException {
      rethrow;
    } on DioException catch (_) {
      throw const DriverTourException(
        kind: DriverTourFailureKind.network,
        code: 'TOUR_NETWORK_ERROR',
        isRetryable: true,
      );
    } on FormatException {
      throw const DriverTourException(
        kind: DriverTourFailureKind.invalidResponse,
        code: 'INVALID_TOUR_RESPONSE',
      );
    } catch (_) {
      throw const DriverTourException(
        kind: DriverTourFailureKind.unavailable,
        code: 'TOUR_SERVICE_UNAVAILABLE',
        isRetryable: true,
      );
    }
  }

  static DriverTourException _responseException(
    int? status,
    Map<String, dynamic> envelope,
  ) {
    final code = envelope['code']?.toString().trim();
    final safeCode =
        code == null || code.isEmpty ? 'TOUR_REQUEST_REJECTED' : code;
    return switch (status) {
      401 => DriverTourException(
        kind: DriverTourFailureKind.authentication,
        code: safeCode,
        statusCode: status,
      ),
      403 => DriverTourException(
        kind: DriverTourFailureKind.authorization,
        code: safeCode,
        statusCode: status,
      ),
      409 => DriverTourException(
        kind: DriverTourFailureKind.conflict,
        code: safeCode,
        statusCode: status,
      ),
      400 || 404 || 405 => DriverTourException(
        kind: DriverTourFailureKind.validation,
        code: safeCode,
        statusCode: status,
      ),
      _ => DriverTourException(
        kind: DriverTourFailureKind.unavailable,
        code: safeCode,
        statusCode: status,
        isRetryable: true,
      ),
    };
  }

  static dynamic _decode(dynamic value) {
    if (value is! String) return value;
    final text = value.trim();
    if (text.isEmpty) throw const FormatException('empty response');
    return jsonDecode(text);
  }

  static Map<String, dynamic>? _jsonMap(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : null;

  static void _assertPositive(int value, String field) {
    if (value <= 0) {
      throw DriverTourException(
        kind: DriverTourFailureKind.validation,
        code: 'INVALID_$field',
      );
    }
  }

  static String? _normalizeReason(String action, String? reason) {
    final normalized = reason?.trim() ?? '';
    if (action != 'interrupt') return null;
    if (normalized.isEmpty ||
        normalized.runes.length > 255 ||
        RegExp(r'[\x00-\x1F\x7F]').hasMatch(normalized)) {
      throw const DriverTourException(
        kind: DriverTourFailureKind.validation,
        code: 'INVALID_INTERRUPT_REASON',
      );
    }
    return normalized;
  }

  static String _retryKey(Map<String, dynamic> payload) {
    final values =
        payload.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    return '${UserSessionState.generation}|'
        '${values.map((item) => '${item.key}=${item.value}').join('&')}';
  }

  static String _newUuidV4() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex =
        bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-'
        '${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-'
        '${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }
}
