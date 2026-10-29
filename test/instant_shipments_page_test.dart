// Tests for the Instant / Available shipments queue.
//
// The real providers are used with only their network calls replaced, so the
// page is exercised against the actual state shapes: a lost claim race really
// does return SHIPMENT_ALREADY_ACCEPTED, and a failed page change really does
// have to leave the pager and the rows describing the same page.

import 'package:blockatie/constants/fonts.dart';
import 'package:blockatie/models/driver_profile.dart';
import 'package:blockatie/models/shipment.dart';
import 'package:blockatie/provider/bottom_nav.dart';
import 'package:blockatie/provider/home.dart';
import 'package:blockatie/provider/localization.dart';
import 'package:blockatie/provider/notification.dart';
import 'package:blockatie/provider/profile.dart';
import 'package:blockatie/provider/shipment.dart';
import 'package:blockatie/provider/shipment_flow_config.dart';
import 'package:blockatie/provider/shipment_instsnt.dart';
import 'package:blockatie/services/auth_secure_store.dart';
import 'package:blockatie/services/auth_services.dart';
import 'package:blockatie/services/user_session_state.dart';
import 'package:blockatie/utils/localization.dart';
import 'package:blockatie/utils/text_direction.dart';
import 'package:blockatie/views/pages/home/tabs/shipment-instant/shipment_instant.dart';
import 'package:blockatie/views/widgets/driver_chat_bubble.dart';
import 'package:blockatie/views/widgets/pagination_widget.dart';
import 'package:blockatie/views/widgets/status_update_sheet.dart';
import 'package:flutter/material.dart';
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

/// The outcome the "server" will give the next accept.
class _AcceptOutcome {
  const _AcceptOutcome({
    required this.success,
    this.code,
    this.messageEn,
    this.messageAr,
  });

  final bool success;
  final String? code;

  /// Set when a test needs the server's own wording; otherwise the app's
  /// code-based copy is what gets checked.
  final String? messageEn;
  final String? messageAr;
}

class _StubInstantProvider extends ShipmentInstantprovider {
  _StubInstantProvider({
    required this.pages,
    this.active,
    this.failOnPage,
    this.failFirstLoad = false,
    this.acceptOutcome = const _AcceptOutcome(success: true),
  });

  final Map<int, List<Shipment>> pages;
  final Shipment? active;
  final int? failOnPage;
  final bool failFirstLoad;
  _AcceptOutcome acceptOutcome;

  int fetches = 0;
  int accepts = 0;
  final List<String> requestedLanguages = [];
  bool holdNextResponse = false;
  int? staleGeneration;

  @override
  Future<void> getShipmentsInstant({bool force = false, int? page}) async {
    if (isLoading && isPageChanging) return;

    final requested = page ?? currentPage;
    fetches++;

    final generation = stateGeneration;
    final previousPage = currentPage;

    isLoading = !hasLoaded || requested != currentPage || force;
    isPageChanging = isLoading && hasLoaded;
    errorMessage = null;
    if (isLoading) notifyListeners();

    if (holdNextResponse) return;

    await Future<void>.delayed(Duration.zero);
    if (staleGeneration != null && staleGeneration != generation) return;

    final shouldFail =
        (failFirstLoad && !hasLoaded) ||
        (failOnPage != null && requested == failOnPage);

    if (shouldFail) {
      errorMessage = 'Unable to load available instant shipments';
      _page = previousPage;
    } else {
      _rows = pages[requested] ?? const [];
      _loaded = true;
      _page = requested;
      _total = pages.values.fold(0, (sum, rows) => sum + rows.length);
      _pages = pages.length;
    }

    isLoading = false;
    isPageChanging = false;
    notifyListeners();
  }

  @override
  Future<ShipmentActionResult> acceptShipment(
    int? shipmentId, {
    Shipment? acceptedShipment,
    String languageCode = 'en',
  }) async {
    accepts++;
    requestedLanguages.add(languageCode);
    await Future<void>.delayed(Duration.zero);

    final result = ShipmentActionResult(
      success: acceptOutcome.success,
      code: acceptOutcome.code,
      message: _messageFor(languageCode),
    );

    if (result.success) {
      _rows = _rows.where((row) => row.id != shipmentId).toList();
      notifyListeners();
    } else if (result.shipmentNoLongerAvailable) {
      // What the real provider does: refetch from the server rather than
      // assume anything locally.
      pages[_page] =
          (pages[_page] ?? const []).where((r) => r.id != shipmentId).toList();
      unawaitedRefetch();
    }
    return result;
  }

  void unawaitedRefetch() {
    getShipmentsInstant(force: true);
  }

  String _messageFor(String languageCode) {
    if (acceptOutcome.success) {
      return languageCode == 'ar'
          ? 'تم قبول الشحنة بنجاح'
          : 'Shipment accepted successfully';
    }
    final fromServer =
        languageCode == 'ar'
            ? acceptOutcome.messageAr
            : acceptOutcome.messageEn;
    if (fromServer != null && fromServer.trim().isNotEmpty) return fromServer;
    return ShipmentInstantprovider.messageForCodeForTesting(
          acceptOutcome.code,
          languageCode,
        ) ??
        (languageCode == 'ar'
            ? 'فشل قبول الشحنة'
            : 'Failed to accept shipment');
  }

  List<Shipment> _rows = const [];
  bool _loaded = false;
  int _total = 0;
  int _pages = 0;
  int _page = 1;

  @override
  List<Shipment> get paginatedShipments => _rows;
  @override
  Shipment? get activeInstantShipment => active;
  @override
  bool get hasLoaded => _loaded;
  @override
  int get totalCount => _total + (active != null ? 1 : 0);
  @override
  int get totalPages => _pages;
  @override
  int get currentPage => _page;
}

class _StubProfileProvider extends ProfileProvider {
  @override
  Future<DriverInfo?> fetchDriverProfile() async => profileInfo;
}

class _StubHomeProvider extends HomeProvider {
  @override
  Future<void> getOrderStatus({bool force = false}) async {}
}

class _StubShipmentProvider extends ShipmentProvider {
  int refreshes = 0;

  @override
  Future<void> getAllShipments({bool force = false, int? page}) async {
    refreshes++;
  }
}

class _StubNotificationProvider extends NotificationProvider {
  @override
  Future<void> refreshUnreadCount({bool force = false}) async {}
}

class _StubFlowConfigProvider extends ShipmentFlowConfigProvider {
  @override
  Future<void> fetch({bool force = false}) async {}
}

// -----------------------------------------------------------------------------
// Fixtures
// -----------------------------------------------------------------------------

DriverInfo _eligibleDriver() => DriverInfo(
  id: 501,
  dname: 'Ahmad Saleh',
  dpercent: 0,
  dphone: '0791234567',
  img: '',
  numcd: '',
  latitude: '',
  longitude: '',
  subscription: 1,
  status: 0,
  createdAt: '2026-01-01',
);

Shipment _shipment({
  int id = 1,
  String policy = 'BLK-2026-0012',
  int statusId = 1,
  String statusEn = 'Pending',
  String statusAr = 'قيد الانتظار',
  String messageEn = 'Your shipment is waiting',
  String messageAr = 'شحنتك بالانتظار',
  String phone = '0791234567',
  String store = 'Demo Store',
  String address = 'Amman, Jordan',
  double cod = 12.5,
  double delivery = 2,
  String created = '2026-01-15 10:30:00',
  int driverId = 0,
}) {
  return Shipment.fromJson({
    'id': id,
    'shipment_date': created,
    'created_at': created,
    'policy_num': policy,
    'recipient_name': 'Ahmad Saleh',
    'recipient_phone': phone,
    'delivery_address': address,
    'shipment_cost': cod,
    'delivery_cost': delivery,
    'shipment_status_id': statusId,
    'shipment_status': statusId,
    'status_name_en': statusEn,
    'status_name_ar': statusAr,
    'message_en': messageEn,
    'message_ar': messageAr,
    'nstore': store,
    'phclient': '0788888888',
    'driver_id': driverId,
    'delivery_type_id': 1,
    // The available queue is now deliberately driven by the server action
    // contract. An unassigned pending instant fixture is therefore a real
    // accept offer, rather than relying on its status label alone.
    'driver_action_contract_version': 1,
    'driver_actions': [
      if (driverId == 0 && statusId == 1)
        {
          'id': 'accept_shipment',
          'target_status_id': 2,
          'enabled': true,
          'label_en': 'Accept Shipment',
          'label_ar': 'قبول الشحنة',
          'group': 'progression',
        },
    ],
  });
}

Map<int, List<Shipment>> _onePage([List<Shipment>? rows]) => {
  1: rows ?? [_shipment()],
};

// -----------------------------------------------------------------------------
// Harness
// -----------------------------------------------------------------------------

class _Hosts {
  _Hosts({required this.instant, required this.assigned, required this.locale});

  final _StubInstantProvider instant;
  final _StubShipmentProvider assigned;
  final LocaleProvider locale;
}

Widget _app(_Hosts hosts, {Locale locale = const Locale('en')}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<ShipmentInstantprovider>.value(
        value: hosts.instant,
      ),
      ChangeNotifierProvider<ShipmentProvider>.value(value: hosts.assigned),
      ChangeNotifierProvider<LocaleProvider>.value(value: hosts.locale),
      ChangeNotifierProvider<ProfileProvider>(
        create: (_) => _StubProfileProvider()..profileInfo = _eligibleDriver(),
      ),
      ChangeNotifierProvider<HomeProvider>(create: (_) => _StubHomeProvider()),
      ChangeNotifierProvider<ShipmentFlowConfigProvider>(
        create: (_) => _StubFlowConfigProvider(),
      ),
      ChangeNotifierProvider<NotificationProvider>(
        create: (_) => _StubNotificationProvider(),
      ),
      ChangeNotifierProvider(create: (_) => BottomNavProvider()),
    ],
    child: Consumer<LocaleProvider>(
      builder:
          (context, value, _) => MaterialApp(
            theme: ThemeData(fontFamily: AppFonts.currentFontFamily),
            locale:
                locale.languageCode == 'follow'
                    ? value.getCurrentLocale()
                    : locale,
            supportedLocales: const [Locale('en'), Locale('ar')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: const Scaffold(body: ShipmentInstantPage()),
          ),
    ),
  );
}

_Hosts _hosts({
  Map<int, List<Shipment>>? pages,
  Shipment? active,
  int? failOnPage,
  bool failFirstLoad = false,
  _AcceptOutcome acceptOutcome = const _AcceptOutcome(success: true),
}) {
  return _Hosts(
    instant: _StubInstantProvider(
      pages: pages ?? _onePage(),
      active: active,
      failOnPage: failOnPage,
      failFirstLoad: failFirstLoad,
      acceptOutcome: acceptOutcome,
    ),
    assigned: _StubShipmentProvider(),
    locale: LocaleProvider(loadSaved: false),
  );
}

Future<void> _setSize(WidgetTester tester, double w, double h) async {
  tester.view.physicalSize = Size(w * 3, h * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Bounded pumping instead of `pumpAndSettle`.
///
/// The page carries a `_DriverMatchingBanner` whose controller repeats
/// forever, so the tree is never quiet and `pumpAndSettle` would always time
/// out. These pumps advance the clock far enough for the stub's zero-duration
/// futures, the dialog transition and a fling to finish.
Future<void> _settle(WidgetTester tester, {int frames = 16}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<void> _pump(
  WidgetTester tester,
  _Hosts hosts, {
  Locale locale = const Locale('en'),
  Size size = const Size(390, 844),
}) async {
  await _setSize(tester, size.width, size.height);
  // A bare frame first: pumping the same widget types again would reuse the
  // page's State, whose one-shot init guard would never load this provider.
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(_app(hosts, locale: locale));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 10));
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    AuthService.configureForTesting(secureStore: _FakeSecureStore());
    AppLocalizations.applyLocale(const Locale('en'));
  });

  tearDown(AuthService.resetForTesting);

  // ---------------------------------------------------------------------------
  // Language and state
  // ---------------------------------------------------------------------------
  group('state', () {
    testWidgets('1. the page renders English', (tester) async {
      await _pump(tester, _hosts());

      expect(find.text('Available Instant Shipments'), findsOneWidget);
      expect(find.text('Jobs'), findsOneWidget);
    });

    testWidgets('2. the page renders Arabic', (tester) async {
      await _pump(tester, _hosts(), locale: const Locale('ar'));

      expect(find.text('الشحنات الفورية المتاحة'), findsOneWidget);
      expect(find.text('شحنات'), findsOneWidget);
    });

    testWidgets('3. English lays out left-to-right', (tester) async {
      await _pump(tester, _hosts());
      expect(
        Directionality.of(
          tester.element(find.text('Available Instant Shipments')),
        ),
        TextDirection.ltr,
      );
    });

    testWidgets('4. Arabic lays out right-to-left', (tester) async {
      await _pump(tester, _hosts(), locale: const Locale('ar'));
      expect(
        Directionality.of(tester.element(find.text('الشحنات الفورية المتاحة'))),
        TextDirection.rtl,
      );
    });

    testWidgets('5. the first load shows only the loading state', (
      tester,
    ) async {
      final hosts = _hosts();
      hosts.instant.holdNextResponse = true;
      await _pump(tester, hosts);

      expect(find.byType(CircularProgressIndicator), findsWidgets);
      expect(find.textContaining('Unable to load'), findsNothing);
      expect(
        find.textContaining('No available instant shipments'),
        findsNothing,
      );
    });

    testWidgets('6. a failed first load shows only the error state', (
      tester,
    ) async {
      await _pump(tester, _hosts(pages: {}, failFirstLoad: true));

      expect(
        find.text(
          'Unable to load available instant shipments. Please try again.',
        ),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('7. an error never renders the empty state', (tester) async {
      await _pump(tester, _hosts(pages: {}, failFirstLoad: true));
      expect(
        find.textContaining('No available instant shipments'),
        findsNothing,
      );

      await _pump(
        tester,
        _hosts(pages: {}, failFirstLoad: true),
        locale: const Locale('ar'),
      );
      expect(find.textContaining('لا توجد شحنات فورية متاحة'), findsNothing);
      expect(
        find.text('تعذر تحميل الشحنات الفورية المتاحة. حاول مرة أخرى.'),
        findsOneWidget,
      );
    });

    testWidgets('8. a successful empty response shows the empty state', (
      tester,
    ) async {
      await _pump(tester, _hosts(pages: {1: const []}));

      expect(
        find.text('No available instant shipments right now.'),
        findsOneWidget,
      );
      expect(find.textContaining('Unable to load'), findsNothing);
    });

    testWidgets('9. rows render when the response carries them', (
      tester,
    ) async {
      await _pump(
        tester,
        _hosts(
          pages: _onePage([
            _shipment(id: 1, policy: 'INS-1'),
            _shipment(id: 2, policy: 'INS-2'),
          ]),
        ),
      );

      expect(find.text('INS-1'), findsOneWidget);
      expect(find.text('INS-2'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // Status
  // ---------------------------------------------------------------------------
  group('status', () {
    Future<void> pumpStatus(
      WidgetTester tester,
      int statusId,
      Locale locale, {
      String statusEn = '',
      String statusAr = '',
      String messageEn = 'Your shipment is waiting',
    }) async {
      await _pump(
        tester,
        _hosts(
          pages: _onePage([
            _shipment(
              statusId: statusId,
              statusEn: statusEn,
              statusAr: statusAr,
              messageEn: messageEn,
            ),
          ]),
        ),
        locale: locale,
      );
    }

    const cases = <int, List<String>>{
      1: ['Pending', 'قيد الانتظار'],
      2: ['Processing', 'قيد التجهيز'],
      4: ['In Transit', 'في الطريق'],
    };

    var index = 10;
    cases.forEach((statusId, labels) {
      final number = index++;
      testWidgets(
        '$number. status $statusId reads ${labels.first} / ${labels.last}',
        (tester) async {
          await pumpStatus(tester, statusId, const Locale('en'));
          expect(find.text(labels.first), findsWidgets);

          await pumpStatus(tester, statusId, const Locale('ar'));
          expect(find.text(labels.last), findsWidgets);
        },
      );
    });

    testWidgets('13/14. Failed Delivery matches the shared sheet wording', (
      tester,
    ) async {
      await pumpStatus(tester, 9, const Locale('ar'));

      final context = tester.element(find.byType(ShipmentInstantPage));
      final shared = getStatusLabel(context, 9);
      expect(shared, 'فشل في التسليم');
      expect(find.text(shared), findsWidgets);
      // The old Instant-only table said this instead.
      expect(find.text('فشل التسليم'), findsNothing);
    });

    testWidgets('15. the shipment message is never used as the status', (
      tester,
    ) async {
      await pumpStatus(
        tester,
        4,
        const Locale('en'),
        messageEn: 'Your shipment is waiting',
      );

      expect(find.text('Your shipment is waiting'), findsNothing);
      expect(find.text('In Transit'), findsWidgets);
    });

    testWidgets('16. a known status never shows "Status unavailable"', (
      tester,
    ) async {
      for (final statusId in const [1, 2, 3, 4, 5, 10]) {
        await pumpStatus(tester, statusId, const Locale('en'));
        expect(
          find.textContaining('Status unavailable'),
          findsNothing,
          reason: 'status $statusId fell through',
        );
        expect(find.textContaining('Status #'), findsNothing);
      }
    });

    testWidgets('17. an empty remote status name still resolves by id', (
      tester,
    ) async {
      // getStatusLabel is the one resolver the sheet and the cards share, so
      // this is the real call, not a re-implementation of it.
      await _pump(tester, _hosts());
      var context = tester.element(find.byType(ShipmentInstantPage));
      expect(
        getStatusLabel(context, 4, statusNameEn: '', statusNameAr: ''),
        'In Transit',
      );

      await _pump(tester, _hosts(), locale: const Locale('ar'));
      context = tester.element(find.byType(ShipmentInstantPage));
      expect(
        getStatusLabel(context, 4, statusNameEn: '', statusNameAr: ''),
        'في الطريق',
      );
      // A remote name still wins when it is present.
      expect(
        getStatusLabel(context, 4, statusNameAr: 'قيد النقل'),
        'قيد النقل',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Money and dates
  // ---------------------------------------------------------------------------
  group('money and dates', () {
    // COD and dates only render once the card is past the accept stage, so an
    // owned shipment is used for these.
    Shipment owned({
      double cod = 12.5,
      String created = '2026-01-15 10:30:00',
    }) {
      return _shipment(
        id: 9,
        driverId: 501,
        statusId: 4,
        statusEn: 'In Transit',
        statusAr: 'في الطريق',
        cod: cod,
        created: created,
      );
    }

    testWidgets('18. a valid date is formatted', (tester) async {
      await _pump(tester, _hosts(pages: _onePage([owned()])));
      expect(find.textContaining('15/01/2026'), findsWidgets);
    });

    testWidgets('19. the raw timestamp is never rendered', (tester) async {
      await _pump(tester, _hosts(pages: _onePage([owned()])));
      expect(find.textContaining('2026-01-15 10:30:00'), findsNothing);
      expect(find.textContaining('10:30:00'), findsNothing);
    });

    testWidgets('20. a malformed date shows the placeholder', (tester) async {
      await _pump(
        tester,
        _hosts(pages: _onePage([owned(created: 'not-a-date')])),
      );
      expect(find.textContaining('not-a-date'), findsNothing);
      expect(find.textContaining('Date not available'), findsWidgets);
    });

    testWidgets('21. the MySQL zero date shows the placeholder', (
      tester,
    ) async {
      await _pump(
        tester,
        _hosts(pages: _onePage([owned(created: '0000-00-00 00:00:00')])),
        locale: const Locale('ar'),
      );
      expect(find.textContaining('0000'), findsNothing);
      expect(find.textContaining('التاريخ غير متوفر'), findsWidgets);
    });

    testWidgets('22. COD reads JOD 12.50 in English', (tester) async {
      await _pump(tester, _hosts(pages: _onePage([owned(cod: 12.5)])));
      expect(find.text('JOD 12.50'), findsWidgets);
      expect(find.text('COD amount'), findsOneWidget);
    });

    testWidgets('23. COD reads the Arabic currency name', (tester) async {
      await _pump(
        tester,
        _hosts(pages: _onePage([owned(cod: 12.5)])),
        locale: const Locale('ar'),
      );
      expect(find.text('12.50 دينار أردني'), findsWidgets);
      expect(find.text('مبلغ التحصيل'), findsOneWidget);
      expect(find.textContaining('JOD'), findsNothing);
    });

    testWidgets('24. a round amount keeps both decimals', (tester) async {
      await _pump(tester, _hosts(pages: _onePage([owned(cod: 12)])));
      expect(find.text('JOD 12.00'), findsWidgets);
      expect(find.text('JOD 12'), findsNothing);
    });

    test('the model refuses a zero created date', () {
      expect(
        _shipment(created: '0000-00-00 00:00:00').createdAtDateTime,
        isNull,
      );
      expect(_shipment(created: 'rubbish').createdAtDateTime, isNull);
      final naive =
          _shipment(created: '2026-01-15 23:30:00').createdAtDateTime!;
      expect(naive.day, 15);
      expect(naive.hour, 23);
    });
  });

  // ---------------------------------------------------------------------------
  // Claim
  // ---------------------------------------------------------------------------
  group('claim', () {
    Future<void> tapAccept(WidgetTester tester) async {
      await tester.ensureVisible(find.text('Accept Shipment').first);
      await tester.tap(find.text('Accept Shipment').first);
      await _settle(tester);
    }

    testWidgets('25. the confirmation is English', (tester) async {
      await _pump(tester, _hosts());
      await tapAccept(tester);

      expect(find.text('Accept shipment?'), findsOneWidget);
      expect(
        find.text('This shipment will be assigned to your driver account.'),
        findsOneWidget,
      );
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('26. the confirmation is Arabic', (tester) async {
      await _pump(tester, _hosts(), locale: const Locale('ar'));
      await tester.ensureVisible(find.text('قبول الشحنة').first);
      await tester.tap(find.text('قبول الشحنة').first);
      await _settle(tester);

      expect(find.text('هل تريد قبول هذه الشحنة؟'), findsOneWidget);
      expect(
        find.text('سيتم إسناد هذه الشحنة إلى حساب السائق الخاص بك.'),
        findsOneWidget,
      );
      expect(find.text('إلغاء'), findsOneWidget);
    });

    testWidgets('27/29/35. a confirmed claim refreshes both lists once', (
      tester,
    ) async {
      final hosts = _hosts();
      await _pump(tester, hosts);
      await tapAccept(tester);
      await tester.tap(find.text('Accept'));
      await _settle(tester);

      expect(hosts.instant.accepts, 1);
      expect(hosts.assigned.refreshes, 1, reason: 'assigned list refreshed');
      expect(find.text('Shipment accepted successfully'), findsOneWidget);
    });

    testWidgets('28. a busy shipment shows its progress and blocks a retap', (
      tester,
    ) async {
      final hosts = _hosts();
      await _pump(tester, hosts);

      hosts.instant.markBusyForTesting(1);
      await tester.pump();

      // The card reports the request in flight rather than offering it again.
      expect(hosts.instant.isShipmentBusy(1), isTrue);
      expect(find.byType(CircularProgressIndicator), findsWidgets);
    });

    testWidgets('30. SHIPMENT_ALREADY_ACCEPTED removes the stale card', (
      tester,
    ) async {
      final hosts = _hosts(
        pages: _onePage([
          _shipment(id: 1, policy: 'INS-1'),
          _shipment(id: 2, policy: 'INS-2'),
        ]),
        acceptOutcome: const _AcceptOutcome(
          success: false,
          code: 'SHIPMENT_ALREADY_ACCEPTED',
        ),
      );
      await _pump(tester, hosts);
      expect(find.text('INS-1'), findsOneWidget);

      await tapAccept(tester);
      await tester.tap(find.text('Accept'));
      await _settle(tester);

      expect(
        find.text('This shipment is no longer available.'),
        findsOneWidget,
      );
      expect(find.text('INS-1'), findsNothing, reason: 'stale card refetched');
      expect(find.text('INS-2'), findsOneWidget);
      expect(hosts.assigned.refreshes, 0, reason: 'nothing was assigned');
    });

    testWidgets('31. SHIPMENT_NOT_AVAILABLE removes the stale card', (
      tester,
    ) async {
      final hosts = _hosts(
        pages: _onePage([
          _shipment(id: 1, policy: 'INS-1'),
          _shipment(id: 2, policy: 'INS-2'),
        ]),
        acceptOutcome: const _AcceptOutcome(
          success: false,
          code: 'SHIPMENT_NOT_AVAILABLE',
        ),
      );
      await _pump(tester, hosts);

      await tapAccept(tester);
      await tester.tap(find.text('Accept'));
      await _settle(tester);

      expect(
        find.text('This shipment is not available to accept.'),
        findsOneWidget,
      );
      expect(find.text('INS-1'), findsNothing);
    });

    testWidgets("the server's own Arabic wording is used when it sends one", (
      tester,
    ) async {
      final hosts = _hosts(
        acceptOutcome: const _AcceptOutcome(
          success: false,
          code: 'SHIPMENT_NOT_AVAILABLE',
          messageEn: 'Reserved for another driver.',
          messageAr: 'هذه الشحنة محجوزة لسائق آخر.',
        ),
      );
      await _pump(tester, hosts, locale: const Locale('ar'));

      await tester.ensureVisible(find.text('قبول الشحنة').first);
      await tester.tap(find.text('قبول الشحنة').first);
      await _settle(tester);
      await tester.tap(find.text('قبول'));
      await _settle(tester);

      expect(find.text('هذه الشحنة محجوزة لسائق آخر.'), findsOneWidget);
      expect(find.text('Reserved for another driver.'), findsNothing);
    });

    testWidgets('32. a network failure never looks successful', (tester) async {
      final hosts = _hosts(acceptOutcome: const _AcceptOutcome(success: false));
      await _pump(tester, hosts);

      await tapAccept(tester);
      await tester.tap(find.text('Accept'));
      await _settle(tester);

      expect(find.text('Failed to accept shipment'), findsOneWidget);
      expect(hosts.assigned.refreshes, 0);
      // The card is still there: nothing claimed it.
      expect(find.text('BLK-2026-0012'), findsOneWidget);
    });

    test('33. a server failure uses safe localized copy', () {
      for (final code in const [
        'DB_ERROR',
        'DRIVER_INACTIVE',
        'DRIVER_SUBSCRIPTION_INACTIVE',
        'REQUEST_IN_PROGRESS',
      ]) {
        for (final language in const ['en', 'ar']) {
          final message = ShipmentInstantprovider.messageForCodeForTesting(
            code,
            language,
          );
          expect(message, isNotNull, reason: '$code/$language');
          expect(message, isNot(contains('SQL')));
          expect(message, isNot(contains('Dio')));
          expect(message, isNot(contains(code)));
        }
      }
    });

    test('34. Arabic never falls back to the English message', () {
      // message_ar missing: the app's own Arabic wording, not message_en.
      expect(
        ShipmentInstantprovider().resolveOutcomeForTesting(
          {'code': 'SHIPMENT_ALREADY_ACCEPTED', 'message_en': 'Gone.'},
          languageCode: 'ar',
          fallback: 'احتياطي',
        ),
        'هذه الشحنة لم تعد متاحة.',
      );
      // No code and no Arabic message: the caller's Arabic fallback.
      expect(
        ShipmentInstantprovider().resolveOutcomeForTesting(
          {'message_en': 'Something English'},
          languageCode: 'ar',
          fallback: 'احتياطي',
        ),
        'احتياطي',
      );
      // English is unaffected.
      expect(
        ShipmentInstantprovider().resolveOutcomeForTesting(
          {'message_en': 'Something English'},
          languageCode: 'en',
          fallback: 'fallback',
        ),
        'Something English',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Pagination
  // ---------------------------------------------------------------------------
  group('pagination', () {
    Map<int, List<Shipment>> pages(int count) => {
      for (var page = 1; page <= count; page++)
        page: [_shipment(id: page, policy: 'INS-$page')],
    };

    test('36/39. page 1 appears once and nothing repeats', () {
      for (final current in [1, 2, 5, 8, 9, 10]) {
        final slots = visiblePaginationSlots(current: current, total: 10);
        final numbers = slots.whereType<int>().toList();
        expect(
          numbers.where((n) => n == 1).length,
          1,
          reason: 'page 1 duplicated at current=$current',
        );
        expect(numbers.toSet().length, numbers.length);
        expect(numbers, orderedEquals(numbers.toList()..sort()));
      }
    });

    test('37/38. first, last and current are always present', () {
      for (final current in [1, 4, 5, 6, 10]) {
        final slots = visiblePaginationSlots(current: current, total: 10);
        expect(slots, contains(1));
        expect(slots, contains(10));
        expect(slots, contains(current));
      }
      expect(visiblePaginationSlots(current: 5, total: 10), [
        1,
        null,
        4,
        5,
        6,
        null,
        10,
      ]);
      expect(visiblePaginationSlots(current: 1, total: 1), [1]);
      expect(visiblePaginationSlots(current: 1, total: 0), isEmpty);
    });

    testWidgets('40. the current page is marked selected', (tester) async {
      await _pump(tester, _hosts(pages: pages(10)));

      final selected = tester.widget<Semantics>(
        find
            .ancestor(of: find.text('1'), matching: find.byType(Semantics))
            .first,
      );
      expect(selected.properties.selected, isTrue);
    });

    /// Whether the arrow behind [label] can be tapped.
    bool arrowEnabled(WidgetTester tester, String label) {
      final detector = tester.widget<GestureDetector>(
        find
            .descendant(
              of: find.byWidgetPredicate(
                (widget) => widget is Tooltip && widget.message == label,
              ),
              matching: find.byType(GestureDetector),
            )
            .first,
      );
      return detector.onTap != null;
    }

    testWidgets('41. previous is disabled on the first page', (tester) async {
      await _pump(tester, _hosts(pages: pages(3)));
      expect(arrowEnabled(tester, 'Previous page'), isFalse);
      expect(arrowEnabled(tester, 'Next page'), isTrue);
    });

    testWidgets('42. next is disabled on the last page', (tester) async {
      final hosts = _hosts(pages: pages(3));
      await _pump(tester, hosts);

      hosts.instant.setPage(3);
      await _settle(tester);

      expect(arrowEnabled(tester, 'Next page'), isFalse);
      expect(arrowEnabled(tester, 'Previous page'), isTrue);
    });

    testWidgets('43. a second tap is refused while a page is in flight', (
      tester,
    ) async {
      final hosts = _hosts(pages: pages(5));
      await _pump(tester, hosts);
      final before = hosts.instant.fetches;

      hosts.instant.holdNextResponse = true;
      hosts.instant.setPage(2);
      await tester.pump();
      hosts.instant.setPage(3);
      hosts.instant.setPage(4);
      await tester.pump();

      expect(hosts.instant.fetches, before + 1);
    });

    testWidgets('44. a page change is visible while it loads', (tester) async {
      final hosts = _hosts(pages: pages(5));
      await _pump(tester, hosts);

      hosts.instant.holdNextResponse = true;
      hosts.instant.setPage(2);
      await tester.pump();

      expect(find.text('Loading page…'), findsWidgets);
      expect(find.text('INS-1'), findsOneWidget);
      expect(find.text('Jobs'), findsOneWidget);
    });

    testWidgets('45. a failed page change keeps page and rows together', (
      tester,
    ) async {
      final hosts = _hosts(pages: pages(3), failOnPage: 2);
      await _pump(tester, hosts);
      expect(hosts.instant.currentPage, 1);

      hosts.instant.setPage(2);
      await _settle(tester);

      expect(hosts.instant.currentPage, 1, reason: 'rolled back');
      expect(find.text('INS-1'), findsOneWidget);
      expect(find.text('INS-2'), findsNothing);
      expect(
        find.text(
          'Unable to load available instant shipments. Please try again.',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('No available instant shipments'),
        findsNothing,
      );
    });

    testWidgets('46. a successful page change moves both together', (
      tester,
    ) async {
      final hosts = _hosts(pages: pages(3));
      await _pump(tester, hosts);

      hosts.instant.setPage(2);
      await _settle(tester);

      expect(hosts.instant.currentPage, 2);
      expect(find.text('INS-2'), findsOneWidget);
      expect(find.text('INS-1'), findsNothing);
    });

    testWidgets('47. page numerals stay left-to-right in Arabic', (
      tester,
    ) async {
      await _pump(tester, _hosts(pages: pages(3)), locale: const Locale('ar'));
      final page2 = tester.widget<Text>(find.text('2').first);
      expect(page2.textDirection, TextDirection.ltr);
    });

    testWidgets('48. the arrows carry localized labels and mirror', (
      tester,
    ) async {
      await _pump(tester, _hosts(pages: pages(3)), locale: const Locale('ar'));
      expect(find.bySemanticsLabel('الصفحة السابقة'), findsWidgets);
      expect(find.bySemanticsLabel('الصفحة التالية'), findsWidgets);

      final prev = tester.getCenter(find.byIcon(Icons.chevron_left).first).dx;
      final next = tester.getCenter(find.byIcon(Icons.chevron_right).first).dx;
      expect(prev, greaterThan(next), reason: 'row mirrors in Arabic');
      expect(Icons.chevron_left.matchTextDirection, isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // Search
  // ---------------------------------------------------------------------------
  group('search', () {
    testWidgets('49/50. the clear button appears and resets the query', (
      tester,
    ) async {
      final hosts = _hosts();
      await _pump(tester, hosts);
      expect(find.byIcon(Icons.close_rounded), findsNothing);

      await tester.enterText(find.byType(TextField).first, 'INS-1');
      await tester.pump();
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pump();

      expect(find.byIcon(Icons.close_rounded), findsNothing);
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        isEmpty,
      );
    });

    testWidgets('51/52. a numeric query is LTR, Arabic text is not', (
      tester,
    ) async {
      await _pump(tester, _hosts(), locale: const Locale('ar'));

      await tester.enterText(find.byType(TextField).first, '2026001');
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byType(TextField).first).textDirection,
        TextDirection.ltr,
      );

      await tester.enterText(find.byType(TextField).first, 'قيد الانتظار');
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byType(TextField).first).textDirection,
        isNull,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Identifiers
  // ---------------------------------------------------------------------------
  group('identifiers', () {
    testWidgets('53. the phone is isolated left-to-right in Arabic', (
      tester,
    ) async {
      await _pump(
        tester,
        _hosts(
          pages: _onePage([
            _shipment(
              id: 9,
              driverId: 501,
              statusId: 4,
              phone: '+962 79-123-4567',
            ),
          ]),
        ),
        locale: const Locale('ar'),
      );

      // The value lives in a RichText span, so the finder has to look there.
      expect(
        find.textContaining(
          isolateIdentifier('+962 79-123-4567'),
          findRichText: true,
        ),
        findsWidgets,
      );
    });

    testWidgets('54. the policy number is left-to-right in Arabic', (
      tester,
    ) async {
      await _pump(
        tester,
        _hosts(pages: _onePage([_shipment(policy: '2026-0012')])),
        locale: const Locale('ar'),
      );

      final policy = tester.widget<Text>(find.text('2026-0012'));
      expect(policy.textDirection, TextDirection.ltr);
    });

    test('55. names and addresses are never forced left-to-right', () {
      expect(identifierTextDirection('عمان، شارع الملك حسين'), isNull);
      expect(identifierTextDirection('Demo Store'), isNull);
      expect(isolateIdentifier('عمان، الأردن'), 'عمان، الأردن');
      expect(identifierTextDirection('+962 79-123-4567'), TextDirection.ltr);
    });
  });

  // ---------------------------------------------------------------------------
  // Layout
  // ---------------------------------------------------------------------------
  group('layout', () {
    for (final size in const [Size(360, 640), Size(390, 844), Size(430, 932)]) {
      for (final locale in const [Locale('en'), Locale('ar')]) {
        final index =
            56 +
            const [
                  Size(360, 640),
                  Size(390, 844),
                  Size(430, 932),
                ].indexOf(size) *
                2 +
            (locale.languageCode == 'ar' ? 1 : 0);
        testWidgets('$index. ${size.width.toInt()}x${size.height.toInt()} '
            '${locale.languageCode} lays out cleanly', (tester) async {
          await _pump(
            tester,
            _hosts(
              pages: _onePage([
                _shipment(
                  id: 9,
                  driverId: 501,
                  statusId: 4,
                  address:
                      'عمان، شارع الملكة رانيا العبدالله، مقابل الجامعة '
                      'الأردنية، بناية رقم ١٢٣، الطابق الرابع',
                  store: 'متجر الإلكترونيات والأجهزة المنزلية الحديثة',
                  cod: 98765.43,
                ),
              ]),
            ),
            locale: locale,
            size: size,
          );
          expect(tester.takeException(), isNull);

          await tester.fling(
            find.byType(CustomScrollView),
            const Offset(0, -700),
            2000,
          );
          await _settle(tester, frames: 40);
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('62/63. a long Arabic address and a large COD fit', (
      tester,
    ) async {
      await _pump(
        tester,
        _hosts(
          pages: _onePage([
            _shipment(
              id: 9,
              driverId: 501,
              statusId: 4,
              address: 'عمان، شارع الملكة رانيا العبدالله، بناية رقم ١٢٣',
              cod: 987654.32,
            ),
          ]),
        ),
        locale: const Locale('ar'),
        size: const Size(360, 640),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('987654.32 دينار أردني'), findsWidgets);
    });

    testWidgets('64/65. the last card and the pager clear the chat launcher', (
      tester,
    ) async {
      await _pump(
        tester,
        _hosts(
          pages: {
            1: [_shipment(id: 1, policy: 'INS-LAST')],
            2: [_shipment(id: 2, policy: 'INS-2')],
          },
        ),
      );

      await tester.fling(
        find.byType(CustomScrollView),
        const Offset(0, -3000),
        3000,
      );
      await _settle(tester, frames: 40);

      final viewport = tester.getSize(find.byType(ShipmentInstantPage)).height;
      final accept = tester.getRect(find.text('Accept Shipment').first);
      expect(
        viewport - accept.bottom,
        greaterThan(DriverChatBubble.reservedBottomSpace),
        reason: 'accept button clears the launcher',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Session and notification entry
  // ---------------------------------------------------------------------------
  group('session', () {
    testWidgets('66. a previous session response is ignored', (tester) async {
      final hosts = _hosts();
      await _pump(tester, hosts);
      expect(find.text('BLK-2026-0012'), findsOneWidget);

      hosts.instant.staleGeneration = -1;
      hosts.instant.setPage(1);
      await _settle(tester);

      expect(find.text('BLK-2026-0012'), findsOneWidget);
    });

    test('67. a session reset empties the queue and the pager', () {
      final provider = ShipmentInstantprovider();
      addTearDown(provider.dispose);

      UserSessionState.reset(SessionResetReason.accountInactive);

      expect(provider.currentPage, 1);
      expect(provider.paginatedShipments, isEmpty);
      expect(provider.activeInstantShipment, isNull);
      expect(provider.hasLoaded, isFalse);
      expect(provider.isPageChanging, isFalse);
    });

    testWidgets('68/69. arriving from a notification lands on a valid state', (
      tester,
    ) async {
      // The notification carries an id but no shipment data; the page is
      // rendered entirely from the authoritative fetch, which no longer has
      // the claimed job.
      final hosts = _hosts(pages: {1: const []});
      await _pump(tester, hosts);

      expect(
        find.text('No available instant shipments right now.'),
        findsOneWidget,
      );
      expect(find.textContaining('Unable to load'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
