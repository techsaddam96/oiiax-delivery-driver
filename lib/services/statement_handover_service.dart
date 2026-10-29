import 'package:dio/dio.dart';
import '../constants/app_urls.dart';
import 'auth_services.dart';
import 'session_dio.dart';
import 'user_session_state.dart';

class HandoverException implements Exception {
  const HandoverException(this.code);
  final String code;
}

class CashHandover {
  const CashHandover(this.id, this.number, this.clientName, this.amount);
  final int id;
  final String number;
  final String clientName;
  final String amount;
}

class HandoverPage {
  const HandoverPage(this.items, this.hasMore);
  final List<CashHandover> items;
  final bool hasMore;
}

class StatementHandoverService {
  StatementHandoverService({Dio? dio})
    : _dio =
          dio ??
          sessionDio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 12),
              receiveTimeout: const Duration(seconds: 20),
              sendTimeout: const Duration(seconds: 12),
            ),
          );
  final Dio _dio;

  Future<Map<String, dynamic>> _request(
    String endpoint, {
    Map<String, dynamic>? body,
    Map<String, dynamic>? query,
  }) async {
    final generation = UserSessionState.generation;
    final key = (await AuthService.getApiKey())?.trim() ?? '';
    if (generation != UserSessionState.generation) throw const SessionChanged();
    if (key.isEmpty) throw const HandoverException('AUTH_REQUIRED');
    try {
      final response = await _dio.request<dynamic>(
        '${AppUrls.baseUrl}/$endpoint',
        data: body,
        queryParameters: query,
        options: Options(
          method: body == null ? 'GET' : 'POST',
          contentType: Headers.formUrlEncodedContentType,
          headers: {'X-API-KEY': key, 'Accept': 'application/json'},
        ),
      );
      if (generation != UserSessionState.generation) {
        throw const SessionChanged();
      }
      final result = response.data;
      if (response.statusCode != 200 ||
          result is! Map ||
          result['success'] != true ||
          result['data'] is! Map) {
        throw const HandoverException('SERVER_ERROR');
      }
      return Map<String, dynamic>.from(result['data'] as Map);
    } on DioException catch (error) {
      if (generation != UserSessionState.generation) {
        throw const SessionChanged();
      }
      // Only propagate known codes, never raw response text or request details.
      final data = error.response?.data;
      final code = data is Map ? data['code'] : null;
      throw HandoverException(
        const [
              'HANDOVER_INVALID_CODE',
              'HANDOVER_RETRY_LATER',
              'HANDOVER_UNAVAILABLE',
              'NOT_FOUND',
              'AUTH_REQUIRED',
            ].contains(code)
            ? code as String
            : 'SERVER_ERROR',
      );
    }
  }

  Future<HandoverPage> fetch(int page) async {
    final data = await _request(
      'api_driver_statement_handovers.php',
      query: {'page': page},
    );
    return HandoverPage(
      (data['statements'] as List)
          .map(
            (dynamic row) => CashHandover(
              int.parse(row['statement_id'].toString()),
              row['statement_number'].toString(),
              row['client_name'].toString(),
              row['remaining_amount'].toString(),
            ),
          )
          .toList(),
      data['has_more'] == true,
    );
  }

  Future<void> complete(int id, String code) async {
    if (id <= 0 || !RegExp(r'^[0-9]{6}$').hasMatch(code)) {
      throw const HandoverException('HANDOVER_INVALID_CODE');
    }
    final data = await _request(
      'api_driver_statement_handover.php',
      body: {'statement_id': id, 'code': code},
    );
    if (data['statement_id'] != id || data['status'] != 'paid') {
      throw const HandoverException('SERVER_ERROR');
    }
  }
}
