import 'dart:io';

import 'package:blockatie/constants/app_urls.dart';
import 'package:blockatie/models/settlements/driver_financial_summary.dart';
import 'package:blockatie/models/settlements/driver_performance_summary.dart';
import 'package:blockatie/models/settlements/driver_settlement.dart';
import 'package:blockatie/models/settlements/driver_settlement_details.dart';
import 'package:blockatie/models/settlements/settlement_pagination.dart';
import 'package:blockatie/services/auth_services.dart';
import 'package:blockatie/services/session_dio.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class DriverSettlementException implements Exception {
  const DriverSettlementException(this.code);
  final String code;
}

class DriverSettlementPageData {
  const DriverSettlementPageData(this.items, this.pagination);
  final List<DriverSettlement> items;
  final SettlementPagination pagination;
}

class DriverSettlementService {
  DriverSettlementService({Dio? dio}) : _dio = dio ?? _sharedDio;
  static final Dio _sharedDio = sessionDio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 20),
      responseType: ResponseType.json,
    ),
  );
  final Dio _dio;

  Future<DriverSettlementPageData> fetchSettlements({
    int page = 1,
    int limit = 15,
    String? status,
  }) async {
    final data = await _get(
      AppUrls.driverSettlements,
      query: {
        'page': page,
        'limit': limit,
        if (status != null && status.isNotEmpty) 'status': status,
      },
    );
    final raw =
        data['settlements'] is List ? data['settlements'] as List : const [];
    return DriverSettlementPageData(
      raw
          .whereType<Map>()
          .map(
            (item) =>
                DriverSettlement.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(growable: false),
      SettlementPagination.fromJson(
        data['pagination'] is Map
            ? Map<String, dynamic>.from(data['pagination'] as Map)
            : null,
      ),
    );
  }

  Future<DriverFinancialSummary> fetchFinancialSummary() async =>
      DriverFinancialSummary.fromJson(
        await _get(AppUrls.driverFinancialSummary),
      );
  Future<DriverPerformanceSummary> fetchPerformanceSummary() async =>
      DriverPerformanceSummary.fromJson(
        await _get(AppUrls.driverPerformanceSummary),
      );
  Future<DriverSettlementDetails> fetchSettlementDetails(
    int settlementId, {
    int page = 1,
    int limit = 20,
  }) async => DriverSettlementDetails.fromJson(
    await _get(
      AppUrls.driverSettlementDetails,
      query: {'settlement_id': settlementId, 'page': page, 'limit': limit},
    ),
  );

  Future<File> downloadSettlementPdf(int settlementId, String reference) async {
    final apiKey = await _apiKey();
    try {
      final response = await _dio.get<List<int>>(
        AppUrls.driverSettlementPdf,
        queryParameters: {'settlement_id': settlementId},
        options: Options(
          responseType: ResponseType.bytes,
          headers: {'X-API-KEY': apiKey, 'Accept': 'application/pdf'},
        ),
      );
      if (response.statusCode != 200 ||
          response.data == null ||
          response.data!.isEmpty) {
        _log(
          AppUrls.driverSettlementPdf,
          status: response.statusCode,
          code: 'PDF_FAILED',
        );
        throw const DriverSettlementException('PDF_FAILED');
      }
      final directory = await getTemporaryDirectory();
      final safeReference = reference.replaceAll(
        RegExp(r'[^A-Za-z0-9_-]'),
        '_',
      );
      final file = File(
        '${directory.path}${Platform.pathSeparator}driver_settlement_${safeReference.isEmpty ? settlementId : safeReference}.pdf',
      );
      return file.writeAsBytes(response.data!, flush: true);
    } on DriverSettlementException {
      rethrow;
    } on DioException catch (error) {
      throw _mapDio(error);
    } on FileSystemException {
      throw const DriverSettlementException('PDF_FAILED');
    }
  }

  /// Reads one settlement endpoint and returns its payload.
  ///
  /// Every settlement endpoint answers with an envelope —
  /// `{success, status, code, message_en, message_ar, data:{…}}` — and the
  /// payload lives under `data`. Unwrapping happens here, exactly once: callers
  /// that indexed the envelope directly were reading a level that has no
  /// `settlements`, no `settlement` and no `cash_in_hand`, so a perfectly good
  /// response parsed into an empty list, a blank settlement and a JOD 0.00
  /// summary that looked authoritative.
  Future<Map<String, dynamic>> _get(
    String url, {
    Map<String, dynamic>? query,
  }) async {
    final apiKey = await _apiKey();
    try {
      final response = await _dio.get(
        url,
        queryParameters: query,
        options: Options(
          headers: {'X-API-KEY': apiKey, 'Accept': 'application/json'},
        ),
      );
      if (response.data is! Map) {
        // A non-JSON body is what a server-side fatal looks like from here: the
        // endpoint dies before it can emit its error envelope, so the app sees
        // a status and an empty or HTML body and nothing else.
        _log(url, status: response.statusCode, note: 'body is not JSON');
        throw const DriverSettlementException('INVALID_RESPONSE');
      }
      final envelope = Map<String, dynamic>.from(response.data as Map);
      if (response.statusCode != 200 || envelope['success'] != true) {
        final code = '${envelope['code'] ?? 'SERVER_ERROR'}';
        _log(url, status: response.statusCode, code: code);
        throw DriverSettlementException(code);
      }
      return _payload(envelope);
    } on DriverSettlementException {
      rethrow;
    } on DioException catch (error) {
      final mapped = _mapDio(error);
      _log(
        url,
        status: error.response?.statusCode,
        code: mapped.code,
        note: error.type.name,
      );
      throw mapped;
    }
  }

  /// Why a settlement read failed, in the console, without any credential.
  ///
  /// Every failure on this screen used to be swallowed into a typed code with
  /// nothing written anywhere, so a server that answered 500 and the driver
  /// simply having no settlements were indistinguishable while debugging — the
  /// console stayed empty either way.
  ///
  /// Deliberately logs only the endpoint file name, the HTTP status and the
  /// app's own error code. Never the API key, never request headers, never the
  /// response body, which on these endpoints carries financial figures.
  void _log(String url, {int? status, String? code, String? note}) {
    final endpoint = url.split('/').last;
    final parts = <String>[
      'settlement request failed: $endpoint',
      if (status != null) 'status=$status',
      if (code != null) 'code=$code',
      if (note != null) '($note)',
    ];
    debugPrint(parts.join(' '));
  }

  /// The inner payload of a successful envelope.
  ///
  /// A success whose `data` is present but not a map is malformed, and is
  /// reported as such rather than parsed into a zeroed model: on a financial
  /// screen an invented zero is worse than an error. A success with no `data`
  /// key at all is treated as a flat payload, which keeps any endpoint that
  /// answers without the envelope working.
  Map<String, dynamic> _payload(Map<String, dynamic> envelope) {
    if (!envelope.containsKey('data')) {
      return envelope;
    }
    final data = envelope['data'];
    if (data is Map) return Map<String, dynamic>.from(data);
    throw const DriverSettlementException('INVALID_RESPONSE');
  }

  /// Exposed so the response contract can be tested without a transport.
  @visibleForTesting
  Map<String, dynamic> debugPayload(Map<String, dynamic> envelope) =>
      _payload(envelope);

  Future<String> _apiKey() async {
    final apiKey = await AuthService.getApiKey();
    if (apiKey == null || apiKey.trim().isEmpty)
      throw const DriverSettlementException('UNAUTHORIZED');
    return apiKey;
  }

  DriverSettlementException _mapDio(DioException error) {
    final status = error.response?.statusCode;
    if (status == 401) return const DriverSettlementException('UNAUTHORIZED');
    if (status == 403) return const DriverSettlementException('FORBIDDEN');
    if (status == 404) return const DriverSettlementException('NOT_FOUND');
    if (status == 400)
      return const DriverSettlementException('INVALID_REQUEST');
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.connectionError)
      return const DriverSettlementException('NETWORK');
    return const DriverSettlementException('SERVER_ERROR');
  }
}
