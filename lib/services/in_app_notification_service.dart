import 'package:blockatie/constants/app_urls.dart';
import 'package:blockatie/constants/colors.dart';
import 'package:blockatie/services/auth_services.dart';
import 'package:dio/dio.dart';

import 'session_dio.dart';
import 'package:flutter/material.dart';

class InAppNotificationMessage {
  const InAppNotificationMessage({
    required this.notificationId,
    required this.displayMode,
    required this.priority,
    required this.requiresAck,
    required this.titleAr,
    required this.titleEn,
    required this.messageAr,
    required this.messageEn,
  });

  final int notificationId;
  final String displayMode;
  final String priority;
  final bool requiresAck;
  final String titleAr;
  final String titleEn;
  final String messageAr;
  final String messageEn;

  factory InAppNotificationMessage.fromJson(Map<String, dynamic> json) {
    return InAppNotificationMessage(
      notificationId: _asInt(json['notification_id']),
      displayMode: json['display_mode']?.toString() ?? 'notification_only',
      priority: json['priority']?.toString() ?? 'normal',
      requiresAck: _asBool(json['requires_ack']),
      titleAr: json['title_ar']?.toString() ?? '',
      titleEn: json['title_en']?.toString() ?? '',
      messageAr: json['message_ar']?.toString() ?? '',
      messageEn: json['message_en']?.toString() ?? '',
    );
  }

  String titleFor(String languageCode) {
    final preferred = languageCode == 'ar' ? titleAr : titleEn;
    final fallback = languageCode == 'ar' ? titleEn : titleAr;
    return preferred.trim().isNotEmpty
        ? preferred.trim()
        : fallback.trim().isNotEmpty
        ? fallback.trim()
        : languageCode == 'ar'
        ? 'إشعار مهم'
        : 'Important notification';
  }

  String messageFor(String languageCode) {
    final preferred = languageCode == 'ar' ? messageAr : messageEn;
    final fallback = languageCode == 'ar' ? messageEn : messageAr;
    return preferred.trim().isNotEmpty
        ? preferred.trim()
        : fallback.trim().isNotEmpty
        ? fallback.trim()
        : languageCode == 'ar'
        ? 'يرجى مراجعة هذا التحديث.'
        : 'Please review this update.';
  }
}

class InAppNotificationService {
  final Dio _dio = sessionDio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      sendTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      responseType: ResponseType.json,
      validateStatus: (_) => true,
    ),
  );
  final Set<int> _handledNotificationIds = {};
  bool _isChecking = false;

  Future<void> checkAndDisplay(BuildContext context) async {
    if (_isChecking) return;
    _isChecking = true;

    try {
      final session = await AuthService.getSessionSnapshot();
      if (!context.mounted || !session.isAuthenticated) return;

      final response = await _dio.post(
        AppUrls.getInAppNotifications,
        options: Options(
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
            'X-API-KEY': session.apiKey,
          },
        ),
        data: {
          'user_role': 'driver',
          'user_id': session.driverId,
          'driver_id': session.driverId,
        },
      );

      final data = response.data;
      if (response.statusCode != 200 || data is! Map) {
        debugPrint(
          'In-app notification fetch failed: '
          'status=${response.statusCode} code=${_safeCode(data)}',
        );
        return;
      }

      final rawNotifications = data['notifications'];
      if (rawNotifications is! List) return;

      for (final raw in rawNotifications) {
        if (!context.mounted) return;
        if (raw is! Map) continue;

        final message = InAppNotificationMessage.fromJson(
          Map<String, dynamic>.from(raw),
        );
        if (message.notificationId <= 0 ||
            _handledNotificationIds.contains(message.notificationId)) {
          continue;
        }

        _handledNotificationIds.add(message.notificationId);
        await _display(context, message);
      }
    } catch (e) {
      debugPrint('In-app notification fetch failed: ${e.runtimeType}');
    } finally {
      _isChecking = false;
    }
  }

  Future<void> _display(
    BuildContext context,
    InAppNotificationMessage message,
  ) async {
    if (message.displayMode == 'in_app_banner') {
      _showBanner(context, message);
      return;
    }

    if (message.displayMode == 'in_app_modal' ||
        message.displayMode == 'force_modal') {
      await _showModal(context, message);
    }
  }

  void _showBanner(BuildContext context, InAppNotificationMessage message) {
    final languageCode = Localizations.localeOf(context).languageCode;
    ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
    ScaffoldMessenger.of(context).showMaterialBanner(
      MaterialBanner(
        backgroundColor: Colors.white,
        elevation: 2,
        leading: _MessageIcon(priority: message.priority),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message.titleFor(languageCode),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(message.messageFor(languageCode)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
              await _acknowledge(message.notificationId);
            },
            child: Text(languageCode == 'ar' ? 'فهمت' : 'Got it'),
          ),
        ],
      ),
    );
  }

  Future<void> _showModal(
    BuildContext context,
    InAppNotificationMessage message,
  ) async {
    final languageCode = Localizations.localeOf(context).languageCode;
    final isForce = message.displayMode == 'force_modal';

    final acknowledged = await showDialog<bool>(
      context: context,
      barrierDismissible: !isForce,
      builder: (dialogContext) {
        return PopScope(
          canPop: !isForce,
          child: AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            title: Row(
              children: [
                _MessageIcon(priority: message.priority),
                const SizedBox(width: 10),
                Expanded(child: Text(message.titleFor(languageCode))),
              ],
            ),
            content: Text(message.messageFor(languageCode)),
            actions: [
              if (!isForce)
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: Text(languageCode == 'ar' ? 'لاحقاً' : 'Later'),
                ),
              ElevatedButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
                child: Text(languageCode == 'ar' ? 'فهمت' : 'Got it'),
              ),
            ],
          ),
        );
      },
    );

    if (acknowledged == true) {
      await _acknowledge(message.notificationId);
    }
  }

  Future<void> _acknowledge(int notificationId) async {
    try {
      final session = await AuthService.getSessionSnapshot();
      if (!session.isAuthenticated) return;

      await _dio.post(
        AppUrls.acknowledgeNotification,
        options: Options(
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
            'X-API-KEY': session.apiKey,
          },
        ),
        data: {
          'user_role': 'driver',
          'user_id': session.driverId,
          'driver_id': session.driverId,
          'notification_id': notificationId,
        },
      );
    } catch (e) {
      debugPrint('In-app notification acknowledge failed: ${e.runtimeType}');
    }
  }
}

class _MessageIcon extends StatelessWidget {
  const _MessageIcon({required this.priority});

  final String priority;

  @override
  Widget build(BuildContext context) {
    final isCritical = priority == 'critical';
    final isImportant = priority == 'important';
    final color =
        isCritical
            ? Colors.red
            : isImportant
            ? Colors.orange
            : AppColors.primary;

    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(
        isCritical ? Icons.priority_high_rounded : Icons.notifications_rounded,
        color: color,
      ),
    );
  }
}

int _asInt(dynamic value) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

bool _asBool(dynamic value) {
  if (value is bool) return value;
  final normalized = value?.toString().trim().toLowerCase();
  return normalized == '1' || normalized == 'true' || normalized == 'yes';
}

String _safeCode(dynamic data) {
  if (data is! Map) return 'unknown';
  return data['code']?.toString() ?? data['status']?.toString() ?? 'unknown';
}
