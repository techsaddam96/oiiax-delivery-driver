import 'dart:async';

import 'package:blockatie/constants/colors.dart';
import 'package:blockatie/constants/notification_routes.dart';
import 'package:blockatie/constants/notification_system.dart';
import 'package:blockatie/models/notifications.dart';
import 'package:blockatie/provider/notification.dart';
import 'package:blockatie/utils/text_direction.dart';
import 'package:blockatie/utils/time/jordan_time.dart';
import 'package:blockatie/views/pages/notifications/notification_type_copy.dart';
import 'package:blockatie/views/widgets/driver_chat_bubble.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage>
    with AutomaticKeepAliveClientMixin {
  final _scrollController = ScrollController();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_loadMoreWhenNeeded);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<NotificationProvider>().fetchDriverNotifications();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _loadMoreWhenNeeded() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.extentAfter > 260) return;
    unawaited(context.read<NotificationProvider>().loadMore());
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Scaffold(
      backgroundColor: const Color(0xffF6F8FC),
      body: SafeArea(
        child: Column(
          children: [
            _NotificationsHeader(
              title: _copy('Notifications', 'الإشعارات'),
              subtitle: _copy(
                'Delivery updates and account alerts',
                'تحديثات التوصيل وتنبيهات الحساب',
              ),
            ),
            Expanded(
              child: Consumer<NotificationProvider>(
                builder: (context, provider, _) {
                  return RefreshIndicator(
                    color: AppColors.primary,
                    onRefresh:
                        () => provider.fetchDriverNotifications(force: true),
                    child: _buildBody(provider),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  EdgeInsets get _listPadding => EdgeInsets.fromLTRB(
    16,
    16,
    16,
    // Clears the floating chat launcher, so the last notification stays
    // tappable.
    DriverChatBubble.reservedBottomSpace + 16,
  );

  Widget _buildBody(NotificationProvider provider) {
    // The four states are exclusive, and a failure is never drawn as an empty
    // inbox.
    if (provider.isLoading && provider.notifications.isEmpty) {
      return ListView(
        padding: _listPadding,
        children: [
          _StateCard(
            icon: Icons.notifications_active_outlined,
            title: _copy('Loading notifications...', 'جارٍ تحميل الإشعارات...'),
            message: _copy('Please wait a moment.', 'يرجى الانتظار لحظات.'),
            isLoading: true,
          ),
        ],
      );
    }

    if (provider.error != null && provider.notifications.isEmpty) {
      return ListView(
        padding: _listPadding,
        children: [
          _StateCard(
            icon: Icons.error_outline_rounded,
            title: _copy(
              'Unable to load notifications',
              'تعذر تحميل الإشعارات',
            ),
            message: _errorCopy(provider.error),
            actionLabel: _copy('Try again', 'حاول مرة أخرى'),
            onAction: () => provider.fetchDriverNotifications(force: true),
          ),
        ],
      );
    }

    if (provider.notifications.isEmpty) {
      return ListView(
        padding: _listPadding,
        children: [
          _StateCard(
            icon: Icons.notifications_none_rounded,
            title: _copy('No notifications yet', 'لا توجد إشعارات حالياً'),
            message: _copy(
              'New delivery updates will appear here.',
              'ستظهر تحديثات التوصيل الجديدة هنا.',
            ),
          ),
        ],
      );
    }

    final trailing =
        (provider.isLoadingMore || provider.loadMoreError != null) ? 1 : 0;

    return ListView.separated(
      controller: _scrollController,
      padding: _listPadding,
      itemCount: provider.notifications.length + 1 + trailing,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        if (index == provider.notifications.length + 1) {
          if (provider.loadMoreError != null && !provider.isLoadingMore) {
            return _LoadMoreError(
              message: _loadMoreErrorCopy(provider.loadMoreError),
              retryLabel: _copy('Try again', 'حاول مرة أخرى'),
              onRetry: () => unawaited(provider.retryLoadMore()),
            );
          }
          return const Padding(
            padding: EdgeInsets.all(18),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (index == 0) {
          return _NotificationSummary(
            unreadCount: provider.unreadCount,
            totalCount: provider.notifications.length,
            isMarkingAllRead: provider.isMarkingAllRead,
            copy: _copy,
            onMarkAllRead: () async {
              final success = await provider.markAllAsRead();
              if (!mounted) return;
              _showSnack(
                success
                    ? _copy(
                      'All notifications marked as read.',
                      'تم تعليم جميع الإشعارات كمقروءة.',
                    )
                    : _copy(
                      'Unable to mark notifications as read.',
                      'تعذر تعليم الإشعارات كمقروءة.',
                    ),
                isError: !success,
              );
            },
          );
        }

        final notification = provider.notifications[index - 1];
        return _NotificationCard(
          notification: notification,
          isReading: provider.isReading(notification.id),
          title: _titleFor(notification),
          message: _messageFor(notification),
          relativeTime:
              _relativeTime(notification) ??
              _copy('Not available', 'غير متوفر'),
          copy: _copy,
          onTap: () => _handleNotificationTap(notification),
        );
      },
    );
  }

  /// One notification, one destination — whichever way it was opened.
  ///
  /// The row is turned into the same structured payload a push carries and
  /// handed to the same resolver, so an inbox tap gets the typed routing, the
  /// authoritative ownership read, the session check and the de-duplication
  /// that FCM taps already had. It used to look for the word "shipment" in the
  /// type and push a details screen with a fabricated phone number.
  Future<void> _handleNotificationTap(NotificationItem notification) async {
    final provider = context.read<NotificationProvider>();
    var displayNotification = notification;

    if (notification.isUnread) {
      final readSucceeded = await provider.readNotification(
        idNotification: notification.id,
      );
      if (!mounted) return;
      if (!readSucceeded) {
        // Reading is a bookkeeping failure, not a reason to refuse to open the
        // notification.
        _showSnack(_actionErrorCopy(provider.actionError), isError: true);
      } else {
        displayNotification = notification.copyWith(
          isRead: 1,
          readAt: DateTime.now().toIso8601String(),
        );
      }
    }

    final payload = notificationRoutePayload(notification);
    if (payload != null &&
        resolveDriverNotificationTarget(payload) != null) {
      await NotificationSystem.openDriverNotificationPayload(payload);
      return;
    }

    // Nothing routable: show what the notification says rather than guessing a
    // screen.
    if (!mounted) return;
    _showNotificationDetails(displayNotification);
  }

  void _showNotificationDetails(NotificationItem notification) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return _NotificationDetailsSheet(
          title: _titleFor(notification),
          message: _messageFor(notification),
          time:
              _relativeTime(notification) ??
              _copy('Not available', 'غير متوفر'),
          isUnread: notification.isUnread,
          copy: _copy,
        );
      },
    );
  }

  /// The server sends both languages; the screen takes its own and no other.
  String _titleFor(NotificationItem notification) {
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    final localizedTitle =
        isArabic ? notification.titleAr : notification.titleEn;
    if (localizedTitle.trim().isNotEmpty) return localizedTitle.trim();

    // No title from the server: the app's own wording for the type, never the
    // raw `available_shipment` prettified into English inside an Arabic page.
    return notificationTypeTitle(context, notification.type);
  }

  String _messageFor(NotificationItem notification) {
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    final localized =
        isArabic ? notification.messageAr : notification.messageEn;
    if (localized.trim().isNotEmpty) return localized.trim();

    // Deliberately not `message`: that is whichever language the server picked
    // for its own request locale, so borrowing it puts English into Arabic.
    return _copy('You have a new notification.', 'لديك إشعار جديد.');
  }

  /// Relative time for a date that can be trusted, and nothing at all for one
  /// that cannot.
  ///
  /// A zero or unparseable date used to read "Just now", which made the oldest
  /// possible value look like the newest.
  String? _relativeTime(NotificationItem notification) {
    final createdAt = JordanTime.parse(
      notification.createdAtJordan ??
          notification.createdAtUtc ??
          notification.createdAt,
    );
    if (createdAt == null) return null;

    timeago.setLocaleMessages('ar', timeago.ArMessages());
    final locale =
        Localizations.localeOf(context).languageCode == 'ar' ? 'ar' : 'en';
    return timeago.format(createdAt, locale: locale);
  }

  String _errorCopy(NotificationsError? error) {
    if (error == NotificationsError.session) {
      return _copy(
        'Session expired. Please login again.',
        'انتهت الجلسة. يرجى تسجيل الدخول مرة أخرى.',
      );
    }
    return _copy(
      'Unable to load notifications. Please try again.',
      'تعذر تحميل الإشعارات. يرجى المحاولة مرة أخرى.',
    );
  }

  String _loadMoreErrorCopy(NotificationsError? error) {
    return _copy(
      'Unable to load more notifications.',
      'تعذر تحميل المزيد من الإشعارات.',
    );
  }

  String _actionErrorCopy(NotificationsError? error) {
    if (error == NotificationsError.session) {
      return _copy(
        'Session expired. Please login again.',
        'انتهت الجلسة. يرجى تسجيل الدخول مرة أخرى.',
      );
    }
    return _copy(
      'Unable to update notification status.',
      'تعذر تحديث حالة الإشعار.',
    );
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor:
            isError ? const Color(0xffDC2626) : const Color(0xff16A06D),
      ),
    );
  }

  String _copy(String en, String ar) {
    return Localizations.localeOf(context).languageCode == 'ar' ? ar : en;
  }
}

class _NotificationsHeader extends StatelessWidget {
  const _NotificationsHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 2),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xffE5EAF2)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xff0F172A).withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(
              Icons.notifications_none_rounded,
              color: AppColors.primary,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment:
                  isArabic ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: isArabic ? TextAlign.right : TextAlign.left,
                  style: const TextStyle(
                    color: Color(0xff0F172A),
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: isArabic ? TextAlign.right : TextAlign.left,
                  style: const TextStyle(
                    color: Color(0xff64748B),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NotificationSummary extends StatelessWidget {
  const _NotificationSummary({
    required this.unreadCount,
    required this.totalCount,
    required this.isMarkingAllRead,
    required this.copy,
    required this.onMarkAllRead,
  });

  final int unreadCount;
  final int totalCount;
  final bool isMarkingAllRead;
  final String Function(String en, String ar) copy;
  final Future<void> Function() onMarkAllRead;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, AppColors.primary, AppColors.primary],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.18),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
            ),
            child: const Icon(
              Icons.notifications_active_rounded,
              color: Colors.white,
              size: 25,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  copy('Notification Center', 'مركز الإشعارات'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  copy(
                    '$unreadCount unread of $totalCount notifications',
                    // The digits are isolated so the Arabic paragraph cannot
                    // reorder them around the words.
                    '${isolateIdentifier('$unreadCount')} غير مقروء من '
                        '${isolateIdentifier('$totalCount')} إشعار',
                  ),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.74),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          if (unreadCount > 0) ...[
            const SizedBox(width: 10),
            Tooltip(
              message: copy('Mark all as read', 'تعليم الكل كمقروء'),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap:
                    isMarkingAllRead
                        ? null
                        : () {
                          onMarkAllRead();
                        },
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.18),
                    ),
                  ),
                  child:
                      isMarkingAllRead
                          ? const Center(
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            ),
                          )
                          : const Icon(
                            Icons.done_all_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({
    required this.notification,
    required this.isReading,
    required this.title,
    required this.message,
    required this.relativeTime,
    required this.copy,
    required this.onTap,
  });

  final NotificationItem notification;
  final bool isReading;
  final String title;
  final String message;
  final String relativeTime;
  final String Function(String en, String ar) copy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final unread = notification.isUnread;
    final accent = unread ? AppColors.primary : const Color(0xff94A3B8);

    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: unread ? const Color(0xffF0F7FF) : Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: unread ? const Color(0xffB9D9FF) : const Color(0xffE5EAF2),
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xff0F172A).withValues(alpha: 0.06),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: unread ? 0.14 : 0.10),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(_iconFor(notification), color: accent, size: 23),
                ),
                if (unread)
                  Positioned(
                    right: -1,
                    top: -1,
                    child: Container(
                      width: 11,
                      height: 11,
                      decoration: BoxDecoration(
                        color: const Color(0xff16A06D),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: const Color(0xff0F172A),
                            fontSize: 15,
                            fontWeight:
                                unread ? FontWeight.w900 : FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (isReading)
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.primary,
                          ),
                        )
                      else
                        _StatusPill(
                          label:
                              unread
                                  ? copy('Unread', 'غير مقروء')
                                  : copy('Read', 'مقروء'),
                          unread: unread,
                        ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  Text(
                    message,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xff475569),
                      fontSize: 12.5,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Icon(
                        Icons.schedule_rounded,
                        size: 15,
                        color: Color(0xff94A3B8),
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          relativeTime,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xff64748B),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (_isRoutable(notification))
                        Icon(
                          Icons.chevron_right_rounded,
                          color: AppColors.primary,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconFor(NotificationItem notification) =>
      notificationTypeIcon(notification.type);

  /// Whether tapping this row opens a screen, answered by the same resolver
  /// that would do the opening.
  bool _isRoutable(NotificationItem notification) {
    final payload = notificationRoutePayload(notification);
    return payload != null &&
        resolveDriverNotificationTarget(payload) != null;
  }
}

/// Shown under the rows when the next page could not be loaded.
class _LoadMoreError extends StatelessWidget {
  const _LoadMoreError({
    required this.message,
    required this.retryLabel,
    required this.onRetry,
  });

  final String message;
  final String retryLabel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xffFEF4E4),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xffF6DDB4)),
    ),
    child: Column(
      children: [
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: Color(0xff7A4E05),
          ),
        ),
        TextButton(onPressed: onRetry, child: Text(retryLabel)),
      ],
    ),
  );
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.unread});

  final String label;
  final bool unread;

  @override
  Widget build(BuildContext context) {
    final color = unread ? AppColors.primary : const Color(0xff64748B);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.14)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10.5,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _StateCard extends StatelessWidget {
  const _StateCard({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.isLoading = false,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: _cardDecoration(),
      child: Column(
        children: [
          if (isLoading)
            SizedBox(
              width: 34,
              height: 34,
              child: CircularProgressIndicator(
                strokeWidth: 2.8,
                color: AppColors.primary,
              ),
            )
          else
            Icon(icon, color: AppColors.primary, size: 36),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xff0F172A),
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xff64748B),
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: onAction,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(actionLabel!),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: BorderSide(color: AppColors.primary),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _NotificationDetailsSheet extends StatelessWidget {
  const _NotificationDetailsSheet({
    required this.title,
    required this.message,
    required this.time,
    required this.isUnread,
    required this.copy,
  });

  final String title;
  final String message;
  final String time;
  final bool isUnread;
  final String Function(String en, String ar) copy;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 28,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    Icons.notifications_none_rounded,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: Color(0xff0F172A),
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              message,
              style: const TextStyle(
                color: Color(0xff334155),
                fontSize: 14,
                height: 1.45,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(
                  Icons.schedule_rounded,
                  size: 17,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    time,
                    style: const TextStyle(
                      color: Color(0xff64748B),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                _StatusPill(
                  label:
                      isUnread
                          ? copy('Unread', 'غير مقروء')
                          : copy('Read', 'مقروء'),
                  unread: isUnread,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

BoxDecoration _cardDecoration() {
  return BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(22),
    border: Border.all(color: const Color(0xffE5EAF2)),
    boxShadow: [
      BoxShadow(
        color: const Color(0xff0F172A).withValues(alpha: 0.06),
        blurRadius: 22,
        offset: const Offset(0, 12),
      ),
    ],
  );
}
