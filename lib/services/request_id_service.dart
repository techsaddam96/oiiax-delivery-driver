import 'dart:convert';
import 'dart:math';

import 'user_session_state.dart';

class RequestLease {
  RequestLease._({
    required this.operation,
    required this.cacheKey,
    required this.requestId,
    required this.clientActionAt,
  });

  final String operation;
  final String cacheKey;
  final String requestId;
  final String clientActionAt;

  Map<String, String> headers([Map<String, String>? extraHeaders]) => {
    'X-Request-ID': requestId,
    'X-Client-Action-At': clientActionAt,
    if (extraHeaders != null) ...extraHeaders,
  };

  void complete({bool keepForRetry = false}) {
    RequestIdService.release(cacheKey, keepForRetry: keepForRetry);
  }
}

class RequestIdService {
  RequestIdService._();

  static final Map<String, _PendingRequestState> _pending = {};
  static final Random _random = Random.secure();

  /// Idempotency leases belong to one driver session and must not be reused
  /// across accounts.
  static void clearUserState() => _pending.clear();

  static RequestLease acquire({
    required String operation,
    required Map<String, dynamic> payload,
  }) {
    // Session generation is part of the key so a lease can never be shared
    // between two driver accounts.
    final cacheKey =
        '${UserSessionState.generation}|$operation|${_stableEncode(payload)}';
    final existing = _pending[cacheKey];
    if (existing != null) {
      return RequestLease._(
        operation: operation,
        cacheKey: cacheKey,
        requestId: existing.requestId,
        clientActionAt: existing.clientActionAt,
      );
    }

    final state = _PendingRequestState(
      requestId: _generateRequestId(),
      clientActionAt: DateTime.now().toUtc().toIso8601String(),
    );
    _pending[cacheKey] = state;
    return RequestLease._(
      operation: operation,
      cacheKey: cacheKey,
      requestId: state.requestId,
      clientActionAt: state.clientActionAt,
    );
  }

  static void release(String cacheKey, {required bool keepForRetry}) {
    if (!keepForRetry) {
      _pending.remove(cacheKey);
    }
  }

  static String _generateRequestId() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    final hex =
        bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-'
        '${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-'
        '${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }

  static String _stableEncode(dynamic value) {
    return jsonEncode(_normalize(value));
  }

  static dynamic _normalize(dynamic value) {
    if (value is Map) {
      final entries =
          value.entries.toList()
            ..sort((a, b) => a.key.toString().compareTo(b.key.toString()));
      return {
        for (final entry in entries)
          entry.key.toString(): _normalize(entry.value),
      };
    }
    if (value is Iterable) {
      return value.map(_normalize).toList(growable: false);
    }
    return value;
  }
}

class _PendingRequestState {
  const _PendingRequestState({
    required this.requestId,
    required this.clientActionAt,
  });

  final String requestId;
  final String clientActionAt;
}
