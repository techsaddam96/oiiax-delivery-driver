import 'dart:async';

import 'package:app_badge_plus/app_badge_plus.dart';
import 'package:blockatie/constants/app_urls.dart';
import 'package:blockatie/models/notifications.dart';
import 'package:blockatie/services/auth_services.dart';
import 'package:blockatie/services/session_dio.dart';
import 'package:blockatie/services/user_session_state.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

/// Why a notification read failed, in terms the app owns.
///
/// Never a message: the endpoint's prose used to be forwarded straight to the
/// screen, and it once carried the words "Database prepare error." The page
/// writes the sentence.
enum NotificationsError { session, network, server, unknown }

class NotificationProvider extends UserScopedNotifier {
  static final Dio _dio = sessionDio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 10),
      responseType: ResponseType.json,
      validateStatus: (_) => true,
    ),
  );

  /// How many notifications one page holds.
  static const int pageSize = 20;

  NotificationResponse? notificationData;
  bool isLoading = false;
  bool isLoadingMore = false;
  bool isMarkingAllRead = false;

  /// The whole list could not be read.
  NotificationsError? error;

  /// A later page could not be read. The rows already on screen are still
  /// good, so this is reported beside them rather than replacing them.
  NotificationsError? loadMoreError;

  /// The last read or mark-read that failed, for a one-off message.
  NotificationsError? actionError;
  int unreadCount = 0;

  final Set<int> _readingIds = {};
  bool _isFetching = false;
  bool _isRefreshingUnread = false;
  DateTime? _lastUnreadRefreshAt;
  int _page = 1;
  bool _hasMore = false;

  static const Duration _unreadRefreshCooldown = Duration(seconds: 4);

  List<NotificationItem> get notifications =>
      notificationData?.notifications ?? [];

  bool get hasMore => _hasMore;
  int get currentPage => _page;

  bool isReading(int id) => _readingIds.contains(id);

  /// Reads just the badge number.
  ///
  /// `count_only` asks the server for one integer; this used to download every
  /// notification body to compute it.
  Future<void> refreshUnreadCount({bool force = false}) async {
    if (_isFetching || _isRefreshingUnread) return;

    final now = DateTime.now();
    final lastRefresh = _lastUnreadRefreshAt;
    if (!force &&
        lastRefresh != null &&
        now.difference(lastRefresh) < _unreadRefreshCooldown) {
      return;
    }

    final generation = stateGeneration;
    _isRefreshingUnread = true;
    _lastUnreadRefreshAt = now;

    try {
      final session = await AuthService.getSessionSnapshot();
      if (!acceptsState(generation)) return;

      if (!session.isAuthenticated) {
        await clearState();
        return;
      }

      final response = await _post({
        'driver_id': session.driverId,
        'count_only': 1,
      }, session.apiKey);
      // A reply addressed to the previous driver must never set this driver's
      // badge.
      if (!acceptsState(generation)) return;

      final data = response.data;
      if (response.statusCode == 200 && data is Map && _isSuccess(data)) {
        final parsed = NotificationResponse.fromJson(
          Map<String, dynamic>.from(data),
        );
        unreadCount = parsed.unreadCount;
        await _updateAppBadge(unreadCount);
        notifyListeners();
      } else if (_isUnauthorized(response.statusCode)) {
        await clearState();
      }
    } catch (e) {
      debugPrint('Unread notification refresh failed: ${e.runtimeType}');
    } finally {
      if (acceptsState(generation)) {
        _isRefreshingUnread = false;
      }
    }
  }

  /// Synchronous part of the reset, invoked at the session boundary.
  /// The app badge is cleared separately because it is an async platform call.
  @override
  void clearUserState() {
    notificationData = null;
    isLoading = false;
    isLoadingMore = false;
    isMarkingAllRead = false;
    error = null;
    loadMoreError = null;
    actionError = null;
    unreadCount = 0;
    _readingIds.clear();
    _isFetching = false;
    _isRefreshingUnread = false;
    _lastUnreadRefreshAt = null;
    _page = 1;
    _hasMore = false;
    unawaited(_updateAppBadge(0));
  }

  Future<void> clearState() async {
    clearUserState();
    await _updateAppBadge(0);
    notifyListeners();
  }

  /// The first page. A refresh always starts again from page 1.
  Future<void> fetchDriverNotifications({bool force = false}) async {
    if (_isFetching && !force) return;

    final generation = stateGeneration;
    _isFetching = true;
    isLoading = true;
    error = null;
    loadMoreError = null;
    notifyListeners();

    try {
      final session = await AuthService.getSessionSnapshot();
      if (!acceptsState(generation)) return;

      if (!session.isAuthenticated) {
        error = NotificationsError.session;
        notificationData = null;
        unreadCount = 0;
        return;
      }

      final response = await _post({
        'driver_id': session.driverId,
        'page': 1,
        'limit': pageSize,
      }, session.apiKey);
      if (!acceptsState(generation)) return;

      final data = response.data;
      if (response.statusCode == 200 && data is Map && _isSuccess(data)) {
        notificationData = NotificationResponse.fromJson(
          Map<String, dynamic>.from(data),
        );
        _page = notificationData!.page;
        _hasMore = notificationData!.hasMore;
        unreadCount = _deriveUnreadCount(notificationData!);
        _lastUnreadRefreshAt = DateTime.now();
        error = null;
        await _updateAppBadge(unreadCount);
      } else if (_isUnauthorized(response.statusCode)) {
        error = NotificationsError.session;
        await clearState();
      } else {
        error = _errorFor(data, response.statusCode);
      }
    } catch (e) {
      debugPrint('Notifications fetch failed: ${e.runtimeType}');
      if (acceptsState(generation)) error = NotificationsError.network;
    } finally {
      if (acceptsState(generation)) {
        isLoading = false;
        _isFetching = false;
        notifyListeners();
      }
    }
  }

  /// The next page, appended.
  ///
  /// The page only advances on success, and a row already held is never added
  /// twice — two notifications written in the same second could otherwise
  /// straddle a page boundary.
  Future<void> loadMore() async {
    if (isLoadingMore || isLoading || !_hasMore) return;
    // A page that just failed is not retried by the scroll listener on every
    // frame; the driver asks for it again.
    if (loadMoreError != null) return;

    final generation = stateGeneration;
    isLoadingMore = true;
    notifyListeners();

    try {
      final session = await AuthService.getSessionSnapshot();
      if (!acceptsState(generation)) return;
      if (!session.isAuthenticated) {
        loadMoreError = NotificationsError.session;
        return;
      }

      final response = await _post({
        'driver_id': session.driverId,
        'page': _page + 1,
        'limit': pageSize,
      }, session.apiKey);
      if (!acceptsState(generation)) return;

      final data = response.data;
      if (response.statusCode == 200 && data is Map && _isSuccess(data)) {
        final next = NotificationResponse.fromJson(
          Map<String, dynamic>.from(data),
        );
        final existing = notificationData;
        final seen = {for (final item in notifications) item.id};
        final merged = [
          ...notifications,
          ...next.notifications.where((item) => !seen.contains(item.id)),
        ];
        notificationData = (existing ?? next).copyWith(
          notifications: merged,
          page: next.page,
          pages: next.pages,
          total: next.total,
          hasMore: next.hasMore,
          unreadCount: next.unreadCount,
        );
        _page = next.page;
        _hasMore = next.hasMore;
        loadMoreError = null;
      } else {
        // The rows and the page stay exactly as they were.
        loadMoreError = _errorFor(data, response.statusCode);
      }
    } catch (e) {
      debugPrint('Notifications page fetch failed: ${e.runtimeType}');
      if (acceptsState(generation)) loadMoreError = NotificationsError.network;
    } finally {
      if (acceptsState(generation)) {
        isLoadingMore = false;
        notifyListeners();
      }
    }
  }

  /// Retries the page that failed, from the driver's own tap.
  Future<void> retryLoadMore() async {
    if (isLoadingMore) return;
    loadMoreError = null;
    notifyListeners();
    await loadMore();
  }

  Future<bool> readNotification({required int idNotification}) async {
    if (idNotification <= 0) return false;
    if (_readingIds.contains(idNotification)) return false;

    final currentItem = _findNotification(idNotification);
    if (currentItem != null && !currentItem.isUnread) return true;

    final generation = stateGeneration;
    _readingIds.add(idNotification);
    actionError = null;
    notifyListeners();

    try {
      final session = await AuthService.getSessionSnapshot();
      if (!acceptsState(generation)) return false;
      if (!session.isAuthenticated) {
        actionError = NotificationsError.session;
        return false;
      }

      final response = await _dio.post(
        AppUrls.readNotification,
        options: Options(
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
            'X-API-KEY': session.apiKey,
          },
        ),
        data: {'id': idNotification},
      );
      // Driver A's mark-read must not mutate Driver B's inbox.
      if (!acceptsState(generation)) return false;

      final data = response.data;
      if (response.statusCode == 200 && data is Map && _isSuccess(data)) {
        _markReadLocally(idNotification);
        await _updateAppBadge(unreadCount);
        unawaited(refreshUnreadCount(force: true));
        return true;
      } else if (_isUnauthorized(response.statusCode)) {
        await clearState();
      } else {
        actionError = _errorFor(data, response.statusCode);
      }
    } catch (e) {
      debugPrint('Notification read failed: ${e.runtimeType}');
      if (acceptsState(generation)) actionError = NotificationsError.network;
    } finally {
      if (acceptsState(generation)) {
        _readingIds.remove(idNotification);
        notifyListeners();
      }
    }

    return false;
  }

  Future<bool> markAllAsRead() async {
    if (isMarkingAllRead) return false;
    if (unreadCount <= 0 && notifications.every((item) => !item.isUnread)) {
      return true;
    }

    final generation = stateGeneration;
    isMarkingAllRead = true;
    actionError = null;
    notifyListeners();

    try {
      final session = await AuthService.getSessionSnapshot();
      if (!acceptsState(generation)) return false;
      if (!session.isAuthenticated) {
        actionError = NotificationsError.session;
        return false;
      }

      final response = await _dio.post(
        AppUrls.markAllDriverNotificationsRead,
        options: Options(
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
            'X-API-KEY': session.apiKey,
          },
        ),
        data: {'driver_id': session.driverId},
      );
      if (!acceptsState(generation)) return false;

      final data = response.data;
      if (response.statusCode == 200 && data is Map && _isSuccess(data)) {
        // The badge reaches zero only once the server has said so.
        _markAllReadLocally();
        await _updateAppBadge(0);
        return true;
      } else if (_isUnauthorized(response.statusCode)) {
        await clearState();
      } else {
        actionError = _errorFor(data, response.statusCode);
      }
    } catch (e) {
      debugPrint('Mark all notifications read failed: ${e.runtimeType}');
      if (acceptsState(generation)) actionError = NotificationsError.network;
    } finally {
      if (acceptsState(generation)) {
        isMarkingAllRead = false;
        notifyListeners();
      }
    }

    return false;
  }

  Future<Response<dynamic>> _post(Map<String, dynamic> body, String? apiKey) {
    return _dio.post(
      AppUrls.getNotificatios,
      options: Options(
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'X-API-KEY': apiKey,
        },
      ),
      data: body,
    );
  }

  /// The server's stable code, or the transport, mapped onto the app's own
  /// vocabulary. Prose is never carried.
  NotificationsError _errorFor(dynamic data, int? statusCode) {
    if (_isUnauthorized(statusCode)) return NotificationsError.session;

    final code = data is Map ? data['code']?.toString().toUpperCase() : null;
    return switch (code) {
      'API_KEY_REQUIRED' ||
      'INVALID_API_KEY' ||
      'DRIVER_INACTIVE' ||
      'UNAUTHORIZED_DRIVER' => NotificationsError.session,
      'SERVER_ERROR' || 'INVALID_REQUEST' => NotificationsError.server,
      _ => NotificationsError.unknown,
    };
  }

  NotificationItem? _findNotification(int id) {
    for (final notification in notifications) {
      if (notification.id == id) return notification;
    }
    return null;
  }

  void _markReadLocally(int id) {
    final data = notificationData;
    if (data == null) return;
    final wasUnread = data.notifications.any(
      (notification) => notification.id == id && notification.isUnread,
    );

    final updatedNotifications =
        data.notifications.map((notification) {
          if (notification.id != id) return notification;
          return notification.copyWith(
            isRead: 1,
            readAt: DateTime.now().toIso8601String(),
          );
        }).toList();

    notificationData = data.copyWith(notifications: updatedNotifications);
    final localUnread =
        updatedNotifications.where((item) => item.isUnread).length;
    final decrementedUnread =
        wasUnread && unreadCount > 0 ? unreadCount - 1 : unreadCount;
    unreadCount =
        decrementedUnread > localUnread ? decrementedUnread : localUnread;
  }

  void _markAllReadLocally() {
    final data = notificationData;
    final readAt = DateTime.now().toIso8601String();

    if (data == null) {
      unreadCount = 0;
      return;
    }

    final updatedNotifications =
        data.notifications.map((notification) {
          if (!notification.isUnread) return notification;
          return notification.copyWith(isRead: 1, readAt: readAt);
        }).toList();

    notificationData = data.copyWith(
      unreadCount: 0,
      notifications: updatedNotifications,
    );
    unreadCount = 0;
  }

  int _deriveUnreadCount(NotificationResponse data) {
    final localUnread =
        data.notifications.where((item) => item.isUnread).length;
    return data.unreadCount > localUnread ? data.unreadCount : localUnread;
  }

  Future<void> _updateAppBadge(int count) async {
    try {
      if (await AppBadgePlus.isSupported()) {
        await AppBadgePlus.updateBadge(count);
      }
    } catch (e) {
      debugPrint('Notification badge update failed: ${e.runtimeType}');
    }
  }

  bool _isSuccess(Map<dynamic, dynamic> data) {
    return _isTruthy(data['success']) || _isTruthy(data['status']);
  }

  bool _isTruthy(dynamic value) {
    if (value == true) return true;
    final normalized = value?.toString().trim().toLowerCase();
    return normalized == 'true' || normalized == '1' || normalized == 'success';
  }

  bool _isUnauthorized(int? statusCode) =>
      statusCode == 401 || statusCode == 403;
}
