import 'package:blockatie/constants/app_urls.dart';
import 'package:blockatie/services/auth_services.dart';
import 'package:dio/dio.dart';

import 'session_dio.dart';
import 'package:flutter/material.dart';

/// One page of withdrawal history, as the server paged it.
class WithdrawalRequestsPage {
  const WithdrawalRequestsPage({
    required this.requests,
    required this.page,
    required this.pages,
    required this.total,
    required this.hasMore,
  });

  final List<WithdrawalRequest> requests;
  final int page;
  final int pages;
  final int total;
  final bool hasMore;

  static const WithdrawalRequestsPage empty = WithdrawalRequestsPage(
    requests: [],
    page: 1,
    pages: 0,
    total: 0,
    hasMore: false,
  );
}

class WithdrawalRequest {
  final int id;
  final int driverId;
  final String amount;
  final String currency;
  final int status;
  final String withdrawalMethod;
  final String note;
  final String requestedAt;
  final String processedAt;

  WithdrawalRequest({
    required this.id,
    required this.driverId,
    required this.amount,
    required this.currency,
    required this.status,
    required this.withdrawalMethod,
    required this.note,
    required this.requestedAt,
    required this.processedAt,
  });

  factory WithdrawalRequest.fromJson(Map<String, dynamic> json) {
    return WithdrawalRequest(
      id: _asInt(json['id']),
      driverId: _asInt(json['driver_id'] ?? json['driverId']),
      amount: _asAmount(json['amount']),
      currency: json['currency']?.toString() ?? 'JOD',
      status: _asInt(json['status'] ?? json['request_status']),
      withdrawalMethod: json['withdrawal_method']?.toString() ?? '',
      // The admin's own note on the decision — the rejection reason. Payout
      // account details and the admin id are not read at all.
      note:
          (json['remarks'] ?? json['note'] ?? json['notes'])?.toString() ?? '',
      requestedAt:
          (json['requested_at'] ?? json['created_at'] ?? json['date'])
              ?.toString() ??
          '',
      processedAt: json['processed_at']?.toString() ?? '',
    );
  }

  /// Mapped from the status value, never from words in a string.
  ///
  /// The driver workflow is 0 pending, 2 rejected, 3 completed; 1 is a
  /// client-only step that a driver request should never reach, so it gets a
  /// safe label and no action anywhere in the UI.
  String statusLabel(BuildContext context) {
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';

    switch (status) {
      case 0:
        return isArabic ? 'قيد الانتظار' : 'Pending';
      case 1:
        return isArabic ? 'قيد المعالجة' : 'In review';
      case 2:
        return isArabic ? 'مرفوض' : 'Rejected';
      case 3:
        return isArabic ? 'مكتمل' : 'Completed';
      default:
        return isArabic ? 'غير متوفر' : 'Not available';
    }
  }

  Color get statusColor {
    switch (status) {
      case 0:
        return const Color(0xffF59E0B);
      case 1:
        return const Color(0xff0B63CE);
      case 2:
        return const Color(0xffDC2626);
      case 3:
        return const Color(0xff16A06D);
      default:
        return const Color(0xff64748B);
    }
  }
}

class RequestsService {
  static final Dio _dio = sessionDio();

  /// One page of history. The server pages it now; the app used to ask for
  /// everything, silently receive the first fifty rows and page those locally.
  static Future<Map<String, dynamic>> fetchWithdrawalRequests({
    int page = 1,
    int limit = 10,
  }) async {
    try {
      final apiKey = await AuthService.getApiKey();
      final driverId = await AuthService.getuserId();

      if (apiKey == null || driverId == null) {
        return {'success': false, 'code': 'SESSION_MISSING'};
      }

      final response = await _dio.post(
        AppUrls.getWithdrawal,
        options: Options(
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
            'X-API-KEY': apiKey,
          },
        ),
        data: {'driver_id': driverId, 'page': page, 'limit': limit},
      );

      final data = response.data;
      if (response.statusCode == 200 && data is Map) {
        final map = Map<String, dynamic>.from(data);
        if (_isSuccess(map['success']) || _isSuccess(map['status'])) {
          final rawRequests = map['requests'] ?? map['data'];
          final requests =
              rawRequests is List
                  ? rawRequests.whereType<Map>().map((item) {
                    return WithdrawalRequest.fromJson(
                      Map<String, dynamic>.from(item),
                    );
                  }).toList()
                  : <WithdrawalRequest>[];

          final total = _asInt(map['total']);
          // A server that does not page still answers; the whole response is
          // then one page.
          final pages =
              map.containsKey('pages')
                  ? _asInt(map['pages'])
                  : (requests.isEmpty ? 0 : 1);

          return {
            'success': true,
            'page': WithdrawalRequestsPage(
              requests: requests,
              page: map.containsKey('page') ? _asInt(map['page']) : page,
              pages: pages,
              total: total == 0 ? requests.length : total,
              hasMore:
                  map.containsKey('has_more')
                      ? map['has_more'] == true
                      : (map.containsKey('pages') ? page < pages : false),
            ),
          };
        }

        // Only the stable code travels. The envelope's `message` is documented
        // as English kept for backward compatibility, so forwarding it would
        // put an English sentence inside an Arabic card; `message_ar` is not
        // forwarded either, because the Wallet owns its own wording and the
        // DB_* text must never reach a driver at all.
        debugPrint('Withdrawal requests rejected: ${map['code']}');
        return {'success': false, 'code': map['code']?.toString() ?? ''};
      }

      debugPrint('Withdrawal requests HTTP ${response.statusCode}');
      return {'success': false, 'code': 'SERVER_ERROR'};
    } on DioException catch (e) {
      debugPrint(
        'Withdrawal requests Dio error: ${e.response?.statusCode ?? e.type}',
      );
      return {'success': false, 'code': 'NETWORK_ERROR'};
    } catch (e) {
      debugPrint('Withdrawal requests failed: ${e.runtimeType}');
      return {'success': false, 'code': 'UNKNOWN_ERROR'};
    }
  }
}

bool _isSuccess(dynamic value) {
  if (value == true) return true;
  final normalized = value?.toString().trim().toLowerCase();
  return normalized == 'true' || normalized == '1' || normalized == 'success';
}

int _asInt(dynamic value) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

String _asAmount(dynamic value) {
  if (value is num) return value.toStringAsFixed(2);
  final parsed = double.tryParse(value?.toString() ?? '');
  return parsed == null ? '0.00' : parsed.toStringAsFixed(2);
}
