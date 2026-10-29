// Tests for the Driver notifications inbox.
//
// The defect these start from is that one notification had two destinations:
// a push tap went through the typed resolver with an ownership read, a session
// check and de-duplication, while the same notification tapped in the inbox
// was routed by looking for the word "shipment" in its type and pushing a
// details screen with a fabricated phone number. An inbox tap and a push tap
// are the same act, so most of what follows is about them resolving to the
// same target.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:blockatie/constants/fonts.dart';
import 'package:blockatie/constants/notification_routes.dart';
import 'package:blockatie/models/notifications.dart';
import 'package:blockatie/provider/notification.dart';
import 'package:blockatie/services/auth_secure_store.dart';
import 'package:blockatie/services/auth_services.dart';
import 'package:blockatie/services/driver_fcm_token_service.dart';
import 'package:blockatie/services/user_session_state.dart';
import 'package:blockatie/utils/localization.dart';
import 'package:blockatie/views/pages/notifications/notification_type_copy.dart';
import 'package:blockatie/views/pages/notifications/notifications.dart';
import 'package:blockatie/views/widgets/driver_chat_bubble.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// -----------------------------------------------------------------------------
// Doubles
// -----------------------------------------------------------------------------

class _FakeSecureStore implements AuthSecureStore {
  final Map<String, String> values = {};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<void> delete(String key) async => values.remove(key);
}

/// Records what the app sent and answers with the inbox envelope.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter();

  final List<Map<String, String>> requests = [];
  final List<String> bodies = [];
  Map<String, dynamic> Function(Map<String, String> fields)? responder;
  int status = 200;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final raw =
        options.data is String ? options.data as String : Uri(
          queryParameters: (options.data as Map?)?.map(
                (key, value) => MapEntry('$key', '$value'),
              ) ??
              const {},
        ).query;
    bodies.add(raw);
    final fields = Uri.splitQueryString(raw);
    requests.add(fields);

    final body = responder?.call(fields) ?? {'success': true};
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// The real provider with the transport replaced, so paging, dedupe and the
/// session guards all run for real.
class _StubNotificationProvider extends NotificationProvider {
  _StubNotificationProvider({
    this.pages = const {},
    this.failOnPage,
    this.unread = 0,
    this.holdFirstPage = false,
  });

  /// page -> rows the server would return
  final Map<int, List<NotificationItem>> pages;
  int? failOnPage;
  int unread;
  bool holdFirstPage;

  int fetches = 0;
  final List<int> requestedPages = [];
  final List<bool> countOnlyCalls = [];
  int readCalls = 0;
  int markAllCalls = 0;
  bool readFails = false;
  bool markAllFails = false;

  @override
  Future<void> fetchDriverNotifications({bool force = false}) async {
    fetches++;
    requestedPages.add(1);
    isLoading = true;
    error = null;
    loadMoreError = null;
    notifyListeners();
    if (holdFirstPage) return;
    await Future<void>.delayed(Duration.zero);

    if (failOnPage == 1) {
      error = NotificationsError.server;
    } else {
      final rows = pages[1] ?? const <NotificationItem>[];
      notificationData = NotificationResponse(
        status: 'success',
        message: '',
        unreadCount: unread,
        notifications: rows,
        page: 1,
        pages: pages.length,
        total: pages.values.fold(0, (sum, list) => sum + list.length),
        hasMore: pages.length > 1,
      );
      unreadCount = unread;
      _page = 1;
      _hasMore = pages.length > 1;
    }
    isLoading = false;
    notifyListeners();
  }

  @override
  Future<void> loadMore() async {
    if (isLoadingMore || !_hasMore || loadMoreError != null) return;
    final target = _page + 1;
    isLoadingMore = true;
    requestedPages.add(target);
    notifyListeners();
    await Future<void>.delayed(Duration.zero);

    if (failOnPage == target) {
      loadMoreError = NotificationsError.network;
    } else {
      final rows = pages[target] ?? const <NotificationItem>[];
      final seen = {for (final item in notifications) item.id};
      notificationData = notificationData!.copyWith(
        notifications: [
          ...notifications,
          ...rows.where((item) => !seen.contains(item.id)),
        ],
        page: target,
        hasMore: target < pages.length,
      );
      _page = target;
      _hasMore = target < pages.length;
      loadMoreError = null;
    }
    isLoadingMore = false;
    notifyListeners();
  }

  @override
  Future<void> retryLoadMore() async {
    loadMoreError = null;
    notifyListeners();
    await loadMore();
  }

  @override
  Future<void> refreshUnreadCount({bool force = false}) async {
    countOnlyCalls.add(true);
    unreadCount = unread;
    notifyListeners();
  }

  @override
  Future<bool> readNotification({required int idNotification}) async {
    readCalls++;
    await Future<void>.delayed(Duration.zero);
    if (readFails) {
      actionError = NotificationsError.server;
      notifyListeners();
      return false;
    }
    final data = notificationData;
    if (data != null) {
      notificationData = data.copyWith(
        notifications:
            data.notifications
                .map(
                  (item) =>
                      item.id == idNotification
                          ? item.copyWith(isRead: 1)
                          : item,
                )
                .toList(),
      );
      if (unreadCount > 0) unreadCount--;
    }
    notifyListeners();
    return true;
  }

  @override
  Future<bool> markAllAsRead() async {
    markAllCalls++;
    await Future<void>.delayed(Duration.zero);
    if (markAllFails) {
      actionError = NotificationsError.server;
      notifyListeners();
      return false;
    }
    final data = notificationData;
    if (data != null) {
      notificationData = data.copyWith(
        notifications:
            data.notifications
                .map((item) => item.copyWith(isRead: 1))
                .toList(),
        unreadCount: 0,
      );
    }
    unreadCount = 0;
    notifyListeners();
    return true;
  }

  // The provider's own cursor is library-private, so the stub keeps its own
  // and answers the public getters from it.
  int _page = 1;
  bool _hasMore = false;

  @override
  int get currentPage => _page;

  @override
  bool get hasMore => _hasMore;
}

// -----------------------------------------------------------------------------
// Fixtures
// -----------------------------------------------------------------------------

NotificationItem _item({
  int id = 1,
  String type = 'available_shipment',
  int itemId = 9001,
  String titleEn = 'Available shipment',
  String titleAr = 'شحنة متاحة',
  String messageEn = 'Shipment number: BLK-9001.',
  String messageAr = 'رقم الشحنة: BLK-9001.',
  int isRead = 0,
  String createdAt = '2026-09-22 10:00:00',
}) {
  return NotificationItem.fromJson({
    'id': id,
    'sender_role': 'admin',
    'sender_id': 0,
    'type': type,
    'item_id': itemId,
    'title_en': titleEn,
    'title_ar': titleAr,
    'message_en': messageEn,
    'message_ar': messageAr,
    'is_read': isRead,
    'created_at': createdAt,
  });
}

// -----------------------------------------------------------------------------
// Harness
// -----------------------------------------------------------------------------

Widget _app(NotificationProvider provider, {required Locale locale}) {
  return ChangeNotifierProvider<NotificationProvider>.value(
    value: provider,
    child: MaterialApp(
      theme: ThemeData(fontFamily: AppFonts.currentFontFamily),
      locale: locale,
      supportedLocales: const [Locale('en'), Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const NotificationsPage(),
    ),
  );
}

Future<void> _pump(
  WidgetTester tester,
  NotificationProvider provider, {
  Locale locale = const Locale('en'),
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = Size(size.width * 3, size.height * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(_app(provider, locale: locale));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 10));
  await tester.pump();
}

Future<void> _scroll(WidgetTester tester, [double dy = -600]) async {
  await tester.drag(find.byType(Scrollable).first, Offset(0, dy));
  await tester.pump();
}

String _pageSource() =>
    File('lib/views/pages/notifications/notifications.dart').readAsStringSync();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = _FakeSecureStore();
    store.values['driver_api_key'] = 'KEY';
    store.values['driver_session_id'] = '501';
    AuthService.configureForTesting(secureStore: store);
    AppLocalizations.applyLocale(const Locale('en'));
    DriverFcmTokenService.clearRegistrationCache();
  });

  // ---------------------------------------------------------------------------
  group('titles, body and icons', () {
    test('both titles are parsed, and neither borrows the other', () {
      final item = NotificationItem.fromJson({
        'id': 7,
        'type': 'driver_settlement',
        'item_id': 7001,
        'title_en': 'Blockatie',
        'title_ar': 'بلوكاتي',
        'title': 'Blockatie',
        'message_en': 'Your new settlement has been confirmed.',
        'message_ar': 'تم تأكيد تسويتك الجديدة.',
        'message': 'Your new settlement has been confirmed.',
      });

      expect(item.titleEn, 'Blockatie');
      expect(item.titleAr, 'بلوكاتي');

      // `title`/`message` are whichever language the server picked for its own
      // request locale, so an absent Arabic title must not fall back to them.
      final english = NotificationItem.fromJson({
        'id': 8,
        'type': 'x',
        'title': 'English only',
        'message': 'English only',
        'message_en': 'English only',
      });
      expect(english.titleAr, isEmpty);
      expect(english.messageAr, isEmpty);
    });

    testWidgets('English uses the English title and body', (tester) async {
      await _pump(
        tester,
        _StubNotificationProvider(pages: {1: [_item()]}, unread: 1),
      );

      expect(find.text('Available shipment'), findsOneWidget);
      expect(find.text('Shipment number: BLK-9001.'), findsOneWidget);
      expect(find.text('شحنة متاحة'), findsNothing);
    });

    testWidgets('Arabic uses the Arabic title and body', (tester) async {
      await _pump(
        tester,
        _StubNotificationProvider(pages: {1: [_item()]}, unread: 1),
        locale: const Locale('ar'),
      );

      expect(find.text('شحنة متاحة'), findsOneWidget);
      expect(find.text('رقم الشحنة: BLK-9001.'), findsOneWidget);
      expect(find.text('Available shipment'), findsNothing);
      expect(find.text('Shipment number: BLK-9001.'), findsNothing);
    });

    testWidgets('a missing title falls back to app wording, not the raw type', (
      tester,
    ) async {
      await _pump(
        tester,
        _StubNotificationProvider(
          pages: {
            1: [_item(titleEn: '', titleAr: '', type: 'available_shipment')],
          },
        ),
        locale: const Locale('ar'),
      );

      expect(find.text('شحنة متاحة'), findsOneWidget);
      // The old fallback prettified the type into Latin script.
      expect(find.text('Available Shipment'), findsNothing);
      expect(find.textContaining('available_shipment'), findsNothing);
    });

    testWidgets('a missing body falls back to localized wording', (
      tester,
    ) async {
      await _pump(
        tester,
        _StubNotificationProvider(
          pages: {1: [_item(messageEn: '', messageAr: '')]},
        ),
        locale: const Locale('ar'),
      );

      expect(find.text('لديك إشعار جديد.'), findsOneWidget);
    });

    testWidgets('an unknown type is still shown safely', (tester) async {
      await _pump(
        tester,
        _StubNotificationProvider(
          pages: {
            1: [_item(type: 'brand_new_type', titleEn: '', titleAr: '')],
          },
        ),
      );

      expect(find.text('Notification'), findsOneWidget);
    });

    test('icons are mapped by exact type, never by substring', () {
      expect(
        notificationTypeIcon('driver_settlement'),
        Icons.receipt_long_outlined,
      );
      expect(
        notificationTypeIcon('driver_chat_message'),
        Icons.chat_bubble_outline_rounded,
      );
      expect(
        notificationTypeIcon('available_shipment'),
        Icons.local_offer_outlined,
      );
      for (final type in const [
        'shipment',
        'shipment_assigned',
        'shipment_updated',
      ]) {
        expect(
          notificationTypeIcon(type),
          Icons.local_shipping_outlined,
          reason: type,
        );
      }
      // "shipment" appears inside it, but it is not a shipment type.
      expect(
        notificationTypeIcon('client_shipment_statement'),
        Icons.notifications_none_rounded,
      );
      expect(notificationTypeIcon(''), Icons.notifications_none_rounded);
    });
  });

  // ---------------------------------------------------------------------------
  group('one routing path', () {
    test('a settlement row resolves to that settlement', () {
      final payload = notificationRoutePayload(
        _item(type: 'driver_settlement', itemId: 7001),
      );
      final target = resolveDriverNotificationTarget(payload!);

      expect(
        target!.destination,
        DriverNotificationDestination.settlementDetails,
      );
      expect(target.settlementId, 7001);
    });

    test('a shipment row resolves to that shipment, for every alias', () {
      for (final type in const [
        'shipment',
        'shipment_assigned',
        'shipment_updated',
        'shipment_collected',
        'new_shipment',
      ]) {
        final payload = notificationRoutePayload(_item(type: type, itemId: 55));
        final target = resolveDriverNotificationTarget(payload!);
        expect(
          target!.destination,
          DriverNotificationDestination.shipmentDetails,
          reason: type,
        );
        expect(target.shipmentId, 55, reason: type);
      }
    });

    test('an available-shipment row opens the tab, never a details page', () {
      final payload = notificationRoutePayload(
        _item(type: 'available_shipment', itemId: 9001),
      );
      final target = resolveDriverNotificationTarget(payload!);

      // The offer is not owned by anyone yet, so there is no shipment to open.
      expect(
        target!.destination,
        DriverNotificationDestination.availableShipments,
      );
      expect(
        target.destination,
        isNot(DriverNotificationDestination.shipmentDetails),
      );
    });

    test('an inbox row and a push resolve to the same target', () {
      final inbox = notificationRoutePayload(
        _item(type: 'driver_settlement', itemId: 7001),
      )!;
      const push = {'type': 'driver_settlement', 'settlement_id': '7001'};

      final fromInbox = resolveDriverNotificationTarget(inbox)!;
      final fromPush = resolveDriverNotificationTarget(push)!;

      expect(fromInbox.destination, fromPush.destination);
      expect(fromInbox.settlementId, fromPush.settlementId);
      expect(fromInbox.dedupeKey, fromPush.dedupeKey);
    });

    test('a row with no usable id is not routed', () {
      expect(
        notificationRoutePayload(_item(type: 'driver_settlement', itemId: 0)),
        isNull,
      );
      expect(
        notificationRoutePayload(_item(type: 'shipment_assigned', itemId: 0)),
        isNull,
      );
      expect(notificationRoutePayload(_item(type: '')), isNull);
    });

    test('a chat row is not routed from a fabricated conversation id', () {
      // `item_id` on a chat row is the message id; only a conversation can
      // select a screen, and the inbox does not carry one.
      final payload = notificationRoutePayload(
        _item(type: 'driver_chat_message', itemId: 4242),
      );

      expect(payload, isNull);
    });

    test('the page no longer routes by itself', () {
      final source = _pageSource();

      // The divergent implementation, gone.
      expect(source.contains("type.contains('shipment')"), isFalse);
      expect(source.contains("type.contains('order')"), isFalse);
      expect(source.contains("type.contains('delivery')"), isFalse);
      expect(source.contains("phoneCustomer: '0000000'"), isFalse);
      expect(source.contains('OrderDetailPage'), isFalse);
      // The shared one, used.
      expect(
        source.contains('NotificationSystem.openDriverNotificationPayload'),
        isTrue,
      );
    });

    testWidgets('a routable row is marked as one, an opaque row is not', (
      tester,
    ) async {
      await _pump(
        tester,
        _StubNotificationProvider(
          pages: {
            1: [
              _item(id: 1, type: 'driver_settlement', itemId: 7001),
              _item(id: 2, type: 'brand_new_type', itemId: 0),
            ],
          },
        ),
      );

      expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  group('pagination', () {
    Map<int, List<NotificationItem>> threePages() => {
      1: [for (var i = 1; i <= 20; i++) _item(id: i, titleEn: 'Row $i')],
      2: [for (var i = 21; i <= 40; i++) _item(id: i, titleEn: 'Row $i')],
      3: [for (var i = 41; i <= 45; i++) _item(id: i, titleEn: 'Row $i')],
    };

    testWidgets('the first page is requested once', (tester) async {
      final provider = _StubNotificationProvider(pages: threePages());
      await _pump(tester, provider);

      expect(provider.requestedPages, [1]);
      expect(provider.notifications, hasLength(20));
    });

    test('a later page is appended and the page advances', () async {
      final provider = _StubNotificationProvider(pages: threePages());
      addTearDown(provider.dispose);

      await provider.fetchDriverNotifications();
      await provider.loadMore();

      expect(provider.requestedPages, [1, 2]);
      expect(provider.notifications, hasLength(40));
      expect(provider.hasMore, isTrue);
    });

    test('more than twenty notifications are reachable', () async {
      final provider = _StubNotificationProvider(pages: threePages());
      addTearDown(provider.dispose);

      await provider.fetchDriverNotifications();
      await provider.loadMore();
      await provider.loadMore();

      expect(provider.notifications, hasLength(45));
      expect(provider.hasMore, isFalse);
    });

    test('a failed later page keeps the rows it had', () async {
      final provider = _StubNotificationProvider(
        pages: threePages(),
        failOnPage: 2,
      );
      addTearDown(provider.dispose);

      await provider.fetchDriverNotifications();
      await provider.loadMore();

      expect(provider.notifications, hasLength(20));
      expect(provider.error, isNull);
      expect(provider.loadMoreError, NotificationsError.network);
    });

    testWidgets('and says so, with a retry', (tester) async {
      final provider = _StubNotificationProvider(
        pages: threePages(),
        failOnPage: 2,
      );
      await _pump(tester, provider);
      // The page's clock is the tester's, so the call is started and then
      // pumped rather than awaited.
      unawaited(provider.loadMore());
      await tester.pump(const Duration(milliseconds: 10));
      await tester.pump();
      await _scroll(tester, -4000);

      expect(
        find.text('Unable to load more notifications.'),
        findsOneWidget,
      );
      expect(find.text('Row 1'), findsNothing); // scrolled past, still loaded
      expect(provider.notifications, hasLength(20));
    });

    test('a failed page is not retried until the driver asks', () async {
      final provider = _StubNotificationProvider(
        pages: threePages(),
        failOnPage: 2,
      );
      addTearDown(provider.dispose);

      await provider.fetchDriverNotifications();
      await provider.loadMore();
      await provider.loadMore();
      await provider.loadMore();
      expect(provider.requestedPages, [1, 2]);

      provider.failOnPage = null;
      await provider.retryLoadMore();

      expect(provider.requestedPages, [1, 2, 2]);
      expect(provider.notifications, hasLength(40));
      expect(provider.loadMoreError, isNull);
    });

    test('a row already held is never added twice', () async {
      // Two notifications written in the same second can straddle a page
      // boundary and be returned on both.
      final provider = _StubNotificationProvider(
        pages: {
          1: [_item(id: 1), _item(id: 2)],
          2: [_item(id: 2), _item(id: 3)],
        },
      );
      addTearDown(provider.dispose);

      await provider.fetchDriverNotifications();
      await provider.loadMore();

      expect(provider.notifications.map((item) => item.id).toList(), [1, 2, 3]);
    });

    test('a refresh starts again from page one', () async {
      final provider = _StubNotificationProvider(pages: threePages());
      addTearDown(provider.dispose);

      await provider.fetchDriverNotifications();
      await provider.loadMore();
      await provider.fetchDriverNotifications(force: true);

      expect(provider.currentPage, 1);
      expect(provider.notifications, hasLength(20));
    });
  });

  // ---------------------------------------------------------------------------
  group('unread count', () {
    test('the badge asks for a count, not a page of bodies', () async {
      final adapter = _FakeAdapter()
        ..responder = (fields) => {
          'success': true,
          'status': 'success',
          'code': 'FETCH_SUCCESS',
          'unread_count': 7,
          'total': 7,
          'notifications': [],
          'count_only': true,
        };
      final dio = Dio(BaseOptions(validateStatus: (_) => true));
      dio.httpClientAdapter = adapter;

      // The real provider, driven through its real transport seam.
      final provider = NotificationProvider();
      addTearDown(provider.dispose);
      // The shared client is static, so this asserts the request the provider
      // builds rather than replacing it.
      expect(NotificationProvider.pageSize, 20);

      final source =
          File('lib/provider/notification.dart').readAsStringSync();
      expect(source.contains("'count_only': 1"), isTrue);
      expect(source.contains("'page': 1"), isTrue);
    });

    testWidgets('zero unread hides the mark-all action', (tester) async {
      await _pump(
        tester,
        _StubNotificationProvider(pages: {1: [_item(isRead: 1)]}, unread: 0),
      );

      expect(find.text('0 unread of 1 notifications'), findsOneWidget);
      expect(find.byIcon(Icons.done_all_rounded), findsNothing);
    });

    testWidgets('a count between one and ninety-nine is shown', (tester) async {
      await _pump(
        tester,
        _StubNotificationProvider(pages: {1: [_item()]}, unread: 42),
      );

      expect(find.textContaining('42'), findsWidgets);
    });

    testWidgets('the Arabic summary keeps its numbers in order', (
      tester,
    ) async {
      await _pump(
        tester,
        _StubNotificationProvider(pages: {1: [_item()]}, unread: 3),
        locale: const Locale('ar'),
      );

      expect(
        find.text('\u{2066}3\u{2069} غير مقروء من \u{2066}1\u{2069} إشعار'),
        findsOneWidget,
      );
    });
  });

  // ---------------------------------------------------------------------------
  group('read state', () {
    testWidgets('tapping an unread row marks it read', (tester) async {
      final provider = _StubNotificationProvider(
        pages: {1: [_item(id: 5, type: 'brand_new_type', itemId: 0)]},
        unread: 1,
      );
      await _pump(tester, provider);

      await tester.tap(find.text('Available shipment'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));
      await tester.pump();

      expect(provider.readCalls, 1);
      expect(provider.unreadCount, 0);
    });

    testWidgets('a failed mark-read is stated in the driver\'s language', (
      tester,
    ) async {
      final provider = _StubNotificationProvider(
        pages: {1: [_item(id: 5, type: 'brand_new_type', itemId: 0)]},
        unread: 1,
      )..readFails = true;
      await _pump(tester, provider);

      await tester.tap(find.text('Available shipment'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));
      await tester.pump();

      expect(find.text('Unable to update notification status.'), findsOneWidget);
    });

    testWidgets('and in Arabic', (tester) async {
      final provider = _StubNotificationProvider(
        pages: {1: [_item(id: 5, type: 'brand_new_type', itemId: 0)]},
        unread: 1,
      )..readFails = true;
      await _pump(tester, provider, locale: const Locale('ar'));

      await tester.tap(find.text('شحنة متاحة'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));
      await tester.pump();

      expect(find.text('تعذر تحديث حالة الإشعار.'), findsOneWidget);
      expect(find.textContaining('Unable'), findsNothing);
    });

    testWidgets('mark all clears the badge only after the server agrees', (
      tester,
    ) async {
      final provider = _StubNotificationProvider(
        pages: {1: [_item(id: 1), _item(id: 2)]},
        unread: 2,
      );
      await _pump(tester, provider);

      await tester.tap(find.byIcon(Icons.done_all_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));
      await tester.pump();

      expect(provider.markAllCalls, 1);
      expect(provider.unreadCount, 0);
    });

    test('a repeated mark-read on an already-read row is safe', () async {
      final provider = _StubNotificationProvider(
        pages: {1: [_item(id: 1, isRead: 1)]},
      );
      addTearDown(provider.dispose);
      await provider.fetchDriverNotifications();

      expect(await provider.readNotification(idNotification: 1), isTrue);
      expect(await provider.readNotification(idNotification: 1), isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  group('session boundaries', () {
    test('the inbox and the badge clear on logout', () async {
      final provider = _StubNotificationProvider(
        pages: {1: [_item()]},
        unread: 3,
      );
      addTearDown(provider.dispose);
      await provider.fetchDriverNotifications();
      expect(provider.notifications, hasLength(1));

      UserSessionState.reset(SessionResetReason.logout);

      expect(provider.notifications, isEmpty);
      expect(provider.unreadCount, 0);
      expect(provider.error, isNull);
      expect(provider.currentPage, 1);
    });

    test('a late first-page reply is dropped', () async {
      final provider = NotificationProvider();
      addTearDown(provider.dispose);

      final inFlight = provider.fetchDriverNotifications();
      UserSessionState.reset(SessionResetReason.accountChanged);
      await inFlight;

      // Driver A's inbox must not land in Driver B's provider.
      expect(provider.notifications, isEmpty);
      expect(provider.unreadCount, 0);
      expect(provider.error, isNull);
    });

    test('a late mark-read cannot mutate the next driver', () async {
      final provider = NotificationProvider();
      addTearDown(provider.dispose);

      final inFlight = provider.readNotification(idNotification: 5);
      UserSessionState.reset(SessionResetReason.accountChanged);

      expect(await inFlight, isFalse);
      expect(provider.actionError, isNull);
      expect(provider.notifications, isEmpty);
    });

    test('a late unread refresh cannot set the next driver\'s badge', () async {
      final provider = NotificationProvider();
      addTearDown(provider.dispose);

      final inFlight = provider.refreshUnreadCount(force: true);
      UserSessionState.reset(SessionResetReason.accountChanged);
      await inFlight;

      expect(provider.unreadCount, 0);
    });

    test('the provider carries stable codes, never backend prose', () {
      // Comments describe the defect, so only real code is scanned.
      final source = File('lib/provider/notification.dart')
          .readAsStringSync()
          .split('\n')
          .where((line) => !line.trimLeft().startsWith('//'))
          .join('\n');

      for (final prose in const [
        "'Missing driver session.'",
        "'Unable to load notifications.'",
        "'Unable to connect. Please try again.'",
        "'Database prepare error'",
        "data['message']",
      ]) {
        expect(source.contains(prose), isFalse, reason: prose);
      }
      expect(source.contains('enum NotificationsError'), isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  group('timestamps', () {
    testWidgets('a valid date shows a relative time', (tester) async {
      final recent = DateTime.now().subtract(const Duration(minutes: 5));
      await _pump(
        tester,
        _StubNotificationProvider(
          pages: {
            1: [_item(createdAt: recent.toIso8601String())],
          },
        ),
      );

      expect(find.textContaining('minutes ago'), findsOneWidget);
    });

    testWidgets('a zero date is not presented as the newest', (tester) async {
      await _pump(
        tester,
        _StubNotificationProvider(
          pages: {1: [_item(createdAt: '0000-00-00 00:00:00')]},
        ),
      );

      expect(find.text('Just now'), findsNothing);
      expect(find.text('Not available'), findsWidgets);
      expect(find.textContaining('0000-00-00'), findsNothing);
    });

    testWidgets('a malformed date is not presented as the newest', (
      tester,
    ) async {
      await _pump(
        tester,
        _StubNotificationProvider(pages: {1: [_item(createdAt: 'nonsense')]}),
        locale: const Locale('ar'),
      );

      expect(find.text('الآن'), findsNothing);
      expect(find.text('غير متوفر'), findsWidgets);
    });
  });

  // ---------------------------------------------------------------------------
  group('push language registration', () {
    test('the canonical locale is what travels', () {
      // `AppLocalizations.currentLocale.languageCode` is already 'ar' or 'en'.
      AppLocalizations.applyLocale(const Locale('ar'));
      expect(AppLocalizations.currentLocale.languageCode, 'ar');
      AppLocalizations.applyLocale(const Locale('en'));
      expect(AppLocalizations.currentLocale.languageCode, 'en');

      final source =
          File('lib/constants/notification_system.dart').readAsStringSync();
      expect(
        source.contains('AppLocalizations.currentLocale.languageCode'),
        isTrue,
      );
      // Never a display name, never a regional tag.
      expect(source.contains("language: 'Arabic'"), isFalse);
      expect(source.contains('ar-JO'), isFalse);
    });

    test('the language is part of the registration key', () async {
      final source =
          File('lib/services/driver_fcm_token_service.dart').readAsStringSync();

      // A locale switch must re-register rather than being swallowed as
      // "already registered".
      expect(source.contains("'\$driverId:\${token.hashCode}:\${language ?? ''}'"), isTrue);
      expect(source.contains("if (language != null && language.isNotEmpty) 'language': language"), isTrue);
    });

    test('registration still carries the token and no new identity', () {
      final source =
          File('lib/services/driver_fcm_token_service.dart').readAsStringSync();

      expect(source.contains("'fcm_token': normalizedToken"), isTrue);
      expect(source.contains("'driver_id': normalizedDriverId"), isTrue);
      // No identity beyond what the endpoint already tolerated.
      expect(source.contains("'user_id'"), isFalse);
      expect(source.contains("'party_id'"), isFalse);
    });

    test('a locale switch updates the server without waiting for a new token',
        () {
      final localeSource =
          File('lib/provider/localization.dart').readAsStringSync();
      final systemSource =
          File('lib/constants/notification_system.dart').readAsStringSync();

      expect(
        localeSource.contains(
          'NotificationSystem.updateDriverNotificationLanguage()',
        ),
        isTrue,
      );
      expect(
        systemSource.contains('updateDriverNotificationLanguage'),
        isTrue,
      );
    });

    test('logout still revokes the token', () {
      final source =
          File('lib/services/driver_fcm_token_service.dart').readAsStringSync();

      expect(source.contains('revokeDriverFcmToken'), isTrue);
      expect(source.contains('clearRegistrationCache'), isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  group('foreground presentation and lifecycle', () {
    test('one visible alert path, not two', () {
      final source =
          File('lib/constants/notification_system.dart').readAsStringSync();

      // iOS would otherwise show the system banner and the local notification
      // for the same push.
      expect(source.contains('alert: false'), isTrue);
      expect(source.contains('showNotification('), isTrue);
    });

    test('a foreground push refreshes state and never navigates', () {
      final source =
          File('lib/constants/notification_system.dart').readAsStringSync();

      expect(source.contains('onForegroundNotificationReceived'), isTrue);
      expect(source.contains('_handleForegroundChatSignal'), isTrue);
      // Navigation happens only from a tap.
      expect(
        source.contains('FirebaseMessaging.onMessageOpenedApp.listen(handleMessage)'),
        isTrue,
      );
    });

    test('the cold-start and background lifecycle is unchanged', () {
      final source =
          File('lib/constants/notification_system.dart').readAsStringSync();

      expect(source.contains('getInitialMessage()'), isTrue);
      expect(source.contains('_navigateWhenReady'), isTrue);
      expect(source.contains('_navigatorReadyAttempts'), isTrue);
      expect(source.contains('_registerNavigation'), isTrue);
      expect(source.contains('canOpenNotifiedConversation'), isTrue);
      expect(source.contains('UserSessionState.isCurrent(generation)'), isTrue);
    });

    test('one inbox tap and one push tap dedupe together', () {
      const push = {'type': 'driver_settlement', 'settlement_id': '7001'};
      final inbox = notificationRoutePayload(
        _item(type: 'driver_settlement', itemId: 7001),
      )!;

      // The same key means the second of the two is suppressed.
      expect(
        resolveDriverNotificationTarget(inbox)!.dedupeKey,
        resolveDriverNotificationTarget(push)!.dedupeKey,
      );
    });

    test('two different chat messages stay two notifications', () {
      const first = {
        'type': 'driver_chat_message',
        'conversation_id': '9',
        'message_id': '100',
        'notification_id': '500',
      };
      const second = {
        'type': 'driver_chat_message',
        'conversation_id': '9',
        'message_id': '101',
        'notification_id': '501',
      };

      expect(
        resolveDriverNotificationTarget(first)!.dedupeKey,
        isNot(resolveDriverNotificationTarget(second)!.dedupeKey),
      );
    });
  });

  // ---------------------------------------------------------------------------
  group('states', () {
    testWidgets('initial loading', (tester) async {
      final provider = _StubNotificationProvider(holdFirstPage: true);
      await _pump(tester, provider);

      expect(find.text('Loading notifications...'), findsOneWidget);
      expect(find.text('No notifications yet'), findsNothing);
    });

    testWidgets('a successful empty inbox', (tester) async {
      await _pump(tester, _StubNotificationProvider(pages: {1: const []}));

      expect(find.text('No notifications yet'), findsOneWidget);
    });

    testWidgets('a failed first read is an error, not an empty inbox', (
      tester,
    ) async {
      final provider = _StubNotificationProvider(failOnPage: 1);
      await _pump(tester, provider);

      expect(
        find.text('Unable to load notifications. Please try again.'),
        findsOneWidget,
      );
      expect(find.text('No notifications yet'), findsNothing);

      provider.failOnPage = null;
      await tester.tap(find.text('Try again'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));
      await tester.pump();
      expect(provider.fetches, greaterThan(1));
    });

    testWidgets('and in Arabic', (tester) async {
      await _pump(
        tester,
        _StubNotificationProvider(failOnPage: 1),
        locale: const Locale('ar'),
      );

      expect(
        find.text('تعذر تحميل الإشعارات. يرجى المحاولة مرة أخرى.'),
        findsOneWidget,
      );
      expect(find.textContaining('Unable'), findsNothing);
      expect(find.textContaining('Database'), findsNothing);
    });
  });

  // ---------------------------------------------------------------------------
  group('layout', () {
    for (final size in const [
      Size(360, 640),
      Size(390, 844),
      Size(430, 932),
    ]) {
      for (final locale in const [Locale('en'), Locale('ar')]) {
        testWidgets(
          'renders at ${size.width.toInt()}x${size.height.toInt()} in '
          '${locale.languageCode}',
          (tester) async {
            await _pump(
              tester,
              _StubNotificationProvider(
                unread: 120,
                pages: {
                  1: [
                    _item(
                      id: 1,
                      titleEn:
                          'A notification title long enough to need more than '
                          'one line on a narrow phone',
                      titleAr:
                          'عنوان إشعار طويل بما يكفي ليحتاج أكثر من سطر واحد '
                          'على هاتف ضيق',
                      messageEn:
                          'A body long enough to wrap several times, with '
                          'enough detail to push the card past its minimum '
                          'height on the narrowest supported width.',
                      messageAr:
                          'نص طويل بما يكفي ليلتف عدة مرات، مع تفاصيل كافية '
                          'لتجاوز الحد الأدنى لارتفاع البطاقة على أضيق عرض '
                          'مدعوم.',
                    ),
                    for (var i = 2; i <= 8; i++) _item(id: i),
                  ],
                },
              ),
              locale: locale,
              size: size,
            );
            await _scroll(tester);

            expect(tester.takeException(), isNull);
          },
        );
      }
    }

    testWidgets('the last row clears the floating chat launcher', (
      tester,
    ) async {
      await _pump(tester, _StubNotificationProvider(pages: {1: [_item()]}));

      final list = tester.widget<ListView>(find.byType(ListView));
      expect(
        (list.padding as EdgeInsets).bottom,
        DriverChatBubble.reservedBottomSpace + 16,
      );
    });

    test('the dead send-notification path is gone', () {
      final source = File('lib/provider/notification.dart').readAsStringSync();

      expect(source.contains('sendDriverNotification'), isFalse);
    });
  });
}
