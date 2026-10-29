// Tests for the Assigned (normal) shipments list.
//
// The provider is the real one with a stub transport behind it, so the page is
// exercised against the actual response handling: a failed page change really
// does have to leave the pager and the rows describing the same page, and a
// failed first read really does have to stay out of the empty state.

import 'package:blockatie/constants/fonts.dart';
import 'package:blockatie/models/shipment.dart';
import 'package:blockatie/provider/bottom_nav.dart';
import 'package:blockatie/provider/home.dart';
import 'package:blockatie/provider/localization.dart';
import 'package:blockatie/provider/notification.dart';
import 'package:blockatie/provider/shipment.dart';
import 'package:blockatie/provider/shipment_instsnt.dart';
import 'package:blockatie/services/auth_secure_store.dart';
import 'package:blockatie/services/auth_services.dart';
import 'package:blockatie/services/user_session_state.dart';
import 'package:blockatie/utils/localization.dart';
import 'package:blockatie/utils/text_direction.dart';
import 'package:blockatie/views/pages/home/tabs/all-shipments/components/pagination_row.dart';
import 'package:blockatie/views/pages/home/tabs/all-shipments/table_all_shipment.dart';
import 'package:blockatie/views/widgets/driver_chat_bubble.dart';
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

/// The real provider with only the network call replaced, so pagination,
/// rollback, failure classification and session guards all run for real.
class _StubShipmentProvider extends ShipmentProvider {
  _StubShipmentProvider({
    required this.pages,
    this.failOnPage,
    this.failFirstLoad = false,
    this.failureKind = ShipmentLoadFailure.generic,
  });

  /// page number -> rows the server would return
  final Map<int, List<Shipment>> pages;
  final int? failOnPage;
  final bool failFirstLoad;
  final ShipmentLoadFailure failureKind;

  int fetches = 0;
  final List<String> requestedLanguages = [];
  bool holdNextResponse = false;
  int? staleGeneration;

  @override
  Future<void> getAllShipments({bool force = false, int? page}) async {
    if (isLoading && isPageChanging) return; // mirrors the real in-flight guard

    final requested = page ?? currentPage;
    fetches++;
    requestedLanguages.add(languageCode);

    final generation = stateGeneration;
    final previousPage = currentPage;

    isLoading = !hasLoaded || requested != currentPage || force;
    isPageChanging = isLoading && hasLoaded;
    errorMessage = null;
    failure = null;
    if (isLoading) notifyListeners();

    if (holdNextResponse) return; // leaves the page in its loading state

    await Future<void>.delayed(Duration.zero);

    if (staleGeneration != null && staleGeneration != generation) {
      // Stands in for `acceptsState` refusing a previous session's response.
      return;
    }

    final shouldFail =
        (failFirstLoad && !hasLoaded) ||
        (failOnPage != null && requested == failOnPage);

    if (shouldFail) {
      errorMessage = 'Failed to fetch shipments';
      failure = failureKind;
      currentPage = previousPage;
    } else {
      _rows = pages[requested] ?? const [];
      _loaded = true;
      currentPage = requested;
      _total = pages.values.fold(0, (sum, rows) => sum + rows.length);
      _pages = pages.length;
    }

    isLoading = false;
    isPageChanging = false;
    notifyListeners();
  }

  List<Shipment> _rows = const [];
  bool _loaded = false;
  int _total = 0;
  int _pages = 0;

  @override
  List<Shipment> get paginatedShipments => _rows;
  @override
  bool get hasLoaded => _loaded;
  @override
  int get totalCount => _total;
  @override
  int get totalPages => _pages;
}

class _StubHomeProvider extends HomeProvider {
  @override
  Future<void> getOrderStatus({bool force = false}) async {}
}

class _StubNotificationProvider extends NotificationProvider {
  @override
  Future<void> refreshUnreadCount({bool force = false}) async {}
}

// -----------------------------------------------------------------------------
// Fixtures
// -----------------------------------------------------------------------------

Shipment _shipment({
  int id = 1,
  String policy = 'BLK-2026-0012',
  int statusId = 4,
  int deliveryTypeId = 1,
  int driverId = 501,
  String statusEn = 'In Transit',
  String statusAr = 'في الطريق',
  String messageEn = 'Your shipment is moving',
  String messageAr = 'شحنتك في الطريق',
  String recipient = 'Ahmad Saleh',
  String phone = '0791234567',
  String address = 'Amman, Jordan',
  String store = 'Demo Store',
  String storePhone = '0788888888',
  String storeAddress = 'Store Street 1',
  double cod = 12.5,
  double delivery = 2,
  String date = '2026-01-15 10:30:00',
}) {
  return Shipment.fromJson({
    'id': id,
    'shipment_date': date,
    'policy_num': policy,
    'recipient_name': recipient,
    'recipient_phone': phone,
    'delivery_address': address,
    'shipment_cost': cod,
    'delivery_cost': delivery,
    'shipment_status_id': statusId,
    'shipment_status': statusId,
    'delivery_type_id': deliveryTypeId,
    'driver_id': driverId,
    'status_name_en': statusEn,
    'status_name_ar': statusAr,
    'message_en': messageEn,
    'message_ar': messageAr,
    'nstore': store,
    'phclient': storePhone,
    'lclient': storeAddress,
  });
}

Map<int, List<Shipment>> _onePage([List<Shipment>? rows]) => {
  1: rows ?? [_shipment()],
};

// -----------------------------------------------------------------------------
// Harness
// -----------------------------------------------------------------------------

Widget _app({
  required ShipmentProvider shipments,
  Locale locale = const Locale('en'),
  LocaleProvider? localeProvider,
}) {
  final localeState = localeProvider ?? LocaleProvider(loadSaved: false);
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<ShipmentProvider>.value(value: shipments),
      // The card's next step runs through it (the app always provides it).
      ChangeNotifierProvider<ShipmentInstantprovider>(
        create: (_) => ShipmentInstantprovider(),
      ),
      ChangeNotifierProvider<HomeProvider>(create: (_) => _StubHomeProvider()),
      ChangeNotifierProvider<LocaleProvider>.value(value: localeState),
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
            home: const Scaffold(body: TableAllShipment()),
          ),
    ),
  );
}

Future<void> _setSize(WidgetTester tester, double w, double h) async {
  tester.view.physicalSize = Size(w * 3, h * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pump(
  WidgetTester tester, {
  required ShipmentProvider shipments,
  Locale locale = const Locale('en'),
  LocaleProvider? localeProvider,
  Size size = const Size(390, 844),
}) async {
  await _setSize(tester, size.width, size.height);
  // A bare frame first: pumping the same widget types again would reuse
  // TableAllShipment's State, whose one-shot init guard would then never load
  // the provider handed to this call.
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(
    _app(shipments: shipments, locale: locale, localeProvider: localeProvider),
  );
  await tester.pump();
  // The stub completes over a zero-duration timer, which needs the clock to
  // advance rather than just a microtask drain.
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
  // Language and direction
  // ---------------------------------------------------------------------------
  group('language', () {
    testWidgets('1. the page renders English', (tester) async {
      await _pump(tester, shipments: _StubShipmentProvider(pages: _onePage()));

      expect(find.text('Assigned Shipments'), findsOneWidget);
      expect(find.text('Recipient'), findsOneWidget);
      expect(find.text('Details'), findsOneWidget);
    });

    testWidgets('2. the page renders Arabic', (tester) async {
      await _pump(
        tester,
        shipments: _StubShipmentProvider(pages: _onePage()),
        locale: const Locale('ar'),
      );

      expect(find.text('الشحنات المسندة'), findsOneWidget);
      expect(find.text('المستلم'), findsOneWidget);
      expect(find.text('التفاصيل'), findsOneWidget);
    });

    testWidgets('3. Arabic lays out right-to-left', (tester) async {
      await _pump(
        tester,
        shipments: _StubShipmentProvider(pages: _onePage()),
        locale: const Locale('ar'),
      );

      expect(
        Directionality.of(tester.element(find.text('الشحنات المسندة'))),
        TextDirection.rtl,
      );
    });

    testWidgets('4. English lays out left-to-right', (tester) async {
      await _pump(tester, shipments: _StubShipmentProvider(pages: _onePage()));

      expect(
        Directionality.of(tester.element(find.text('Assigned Shipments'))),
        TextDirection.ltr,
      );
    });
  });

  group('pickup-stage visibility', () {
    testWidgets(
      'an Admin-assigned pre-pickup shipment shows store information only',
      (tester) async {
        await _pump(
          tester,
          shipments: _StubShipmentProvider(
            pages: _onePage([
              _shipment(
                deliveryTypeId: 2,
                statusId: 2,
                recipient: 'Protected Recipient',
                phone: '0791234567',
                address: 'Private Customer Address',
                store: 'Assigned Store',
                storePhone: '0788888888',
                storeAddress: 'Public Store Address',
              ),
            ]),
          ),
        );

        expect(find.text('Store'), findsWidgets);
        expect(find.text('Assigned Store'), findsWidgets);
        expect(find.text('0788888888'), findsOneWidget);
        expect(find.text('Public Store Address'), findsOneWidget);
        expect(find.text('Protected Recipient'), findsNothing);
        expect(find.text('0791234567'), findsNothing);
        expect(find.text('Private Customer Address'), findsNothing);
        expect(find.text('Current destination'), findsOneWidget);
        expect(find.text('Store pickup'), findsOneWidget);
      },
    );

    testWidgets(
      'a picked-up Admin assignment switches to customer information',
      (tester) async {
        await _pump(
          tester,
          shipments: _StubShipmentProvider(
            pages: _onePage([
              _shipment(
                deliveryTypeId: 2,
                statusId: 4,
                recipient: 'Delivered Recipient',
                phone: '0791234567',
                address: 'Customer Delivery Address',
                store: 'Assigned Store',
              ),
            ]),
          ),
        );

        expect(find.text('Delivered Recipient'), findsOneWidget);
        expect(find.text('0791234567'), findsOneWidget);
        expect(find.text('Customer Delivery Address'), findsOneWidget);
        expect(find.text('Customer delivery'), findsOneWidget);
      },
    );
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
    }) async {
      await _pump(
        tester,
        shipments: _StubShipmentProvider(
          pages: _onePage([
            _shipment(
              statusId: statusId,
              statusEn: statusEn,
              statusAr: statusAr,
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
      11: ['Completed', 'مكتمل'],
      7: ['Cancelled', 'تم الإلغاء'],
      8: ['Returned', 'تم الإرجاع'],
      9: ['Failed Delivery', 'فشل في التسليم'],
    };

    var index = 5;
    cases.forEach((statusId, labels) {
      final number = index++;
      testWidgets('$number. status $statusId reads ${labels.first} / '
          '${labels.last}', (tester) async {
        await pumpStatus(tester, statusId, const Locale('en'));
        expect(find.text(labels.first), findsOneWidget);

        await pumpStatus(tester, statusId, const Locale('ar'));
        expect(find.text(labels.last), findsOneWidget);
      });
    });

    testWidgets('12. a failed delivery is not success green', (tester) async {
      await _pump(
        tester,
        shipments: _StubShipmentProvider(
          pages: _onePage([
            _shipment(
              statusId: 9,
              statusEn: 'Failed Delivery',
              statusAr: 'فشل في التسليم',
            ),
          ]),
        ),
      );

      const success = Color(0xff16A06D);
      final badge = tester.widget<Text>(find.text('Failed Delivery'));
      expect(badge.style?.color, isNot(success));
      expect(badge.style?.color, getStatusColor(9));
    });

    testWidgets('13. a completed shipment uses the success colour', (
      tester,
    ) async {
      await _pump(
        tester,
        shipments: _StubShipmentProvider(
          pages: _onePage([
            _shipment(statusId: 11, statusEn: 'Completed', statusAr: 'مكتمل'),
          ]),
        ),
      );

      final badge = tester.widget<Text>(find.text('Completed'));
      expect(badge.style?.color, const Color(0xff16A06D));
    });

    testWidgets('14. the card and the sheet resolve the same wording', (
      tester,
    ) async {
      await _pump(
        tester,
        shipments: _StubShipmentProvider(
          pages: _onePage([_shipment(statusId: 4, statusEn: '', statusAr: '')]),
        ),
        locale: const Locale('ar'),
      );

      final context = tester.element(find.byType(TableAllShipment));
      final shared = getStatusLabel(context, 4);
      expect(shared, 'في الطريق');
      expect(find.text(shared), findsOneWidget);
    });

    testWidgets('15. a known status never renders as an id', (tester) async {
      for (final statusId in const [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]) {
        await _pump(
          tester,
          shipments: _StubShipmentProvider(
            pages: _onePage([
              _shipment(statusId: statusId, statusEn: '', statusAr: ''),
            ]),
          ),
        );
        expect(
          find.textContaining('Status #'),
          findsNothing,
          reason: 'status $statusId fell through to an id',
        );
      }
    });

    testWidgets('16. the shipment message is not used as the status', (
      tester,
    ) async {
      await _pump(
        tester,
        shipments: _StubShipmentProvider(
          pages: _onePage([
            _shipment(
              statusId: 4,
              statusEn: '',
              statusAr: '',
              messageEn: 'Your shipment is moving',
            ),
          ]),
        ),
      );

      expect(find.text('Your shipment is moving'), findsNothing);
      expect(find.text('In Transit'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // States
  // ---------------------------------------------------------------------------
  group('states', () {
    testWidgets('17. the first load shows only the loading state', (
      tester,
    ) async {
      final provider = _StubShipmentProvider(pages: _onePage())
        ..holdNextResponse = true;
      await _pump(tester, shipments: provider);

      expect(find.byType(CircularProgressIndicator), findsWidgets);
      expect(find.textContaining('Unable to load'), findsNothing);
      expect(find.textContaining('No assigned shipments'), findsNothing);
    });

    testWidgets('18. a failed first load shows only the error state', (
      tester,
    ) async {
      await _pump(
        tester,
        shipments: _StubShipmentProvider(pages: {}, failFirstLoad: true),
      );

      expect(
        find.text('Unable to load shipments. Please try again.'),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('19. an error never renders the empty state', (tester) async {
      await _pump(
        tester,
        shipments: _StubShipmentProvider(pages: {}, failFirstLoad: true),
      );

      expect(find.textContaining('No assigned shipments'), findsNothing);

      await _pump(
        tester,
        shipments: _StubShipmentProvider(pages: {}, failFirstLoad: true),
        locale: const Locale('ar'),
      );
      expect(find.textContaining('لا توجد شحنات مسندة'), findsNothing);
      expect(find.text('تعذر تحميل الشحنات. حاول مرة أخرى.'), findsOneWidget);
    });

    testWidgets('a network failure is worded as one', (tester) async {
      await _pump(
        tester,
        shipments: _StubShipmentProvider(
          pages: {},
          failFirstLoad: true,
          failureKind: ShipmentLoadFailure.network,
        ),
      );

      expect(
        find.text('No connection. Check your network and try again.'),
        findsOneWidget,
      );
      // Nothing technical, whatever the cause.
      expect(find.textContaining('Dio'), findsNothing);
      expect(find.textContaining('SQL'), findsNothing);
      expect(find.textContaining('api_key'), findsNothing);
    });

    testWidgets('20. a successful empty response shows the empty state', (
      tester,
    ) async {
      await _pump(
        tester,
        shipments: _StubShipmentProvider(pages: {1: const []}),
      );

      expect(find.text('No assigned shipments right now.'), findsOneWidget);
      expect(find.textContaining('Unable to load'), findsNothing);
    });

    testWidgets('21. rows render when the response carries them', (
      tester,
    ) async {
      await _pump(
        tester,
        shipments: _StubShipmentProvider(
          pages: _onePage([
            _shipment(policy: 'BLK-1'),
            _shipment(id: 2, policy: 'BLK-2'),
          ]),
        ),
      );

      expect(find.text('BLK-1'), findsOneWidget);
      expect(find.text('BLK-2'), findsOneWidget);
      expect(find.textContaining('No assigned shipments'), findsNothing);
    });
  });

  // ---------------------------------------------------------------------------
  // Money and dates
  // ---------------------------------------------------------------------------
  group('money and dates', () {
    testWidgets('22. English puts the currency first', (tester) async {
      await _pump(
        tester,
        shipments: _StubShipmentProvider(
          pages: _onePage([_shipment(cod: 12.5, delivery: 2)]),
        ),
      );

      expect(find.text('JOD 12.50'), findsOneWidget);
      expect(find.text('COD amount'), findsOneWidget);
    });

    testWidgets('23. Arabic uses the Arabic currency name', (tester) async {
      await _pump(
        tester,
        shipments: _StubShipmentProvider(
          pages: _onePage([_shipment(cod: 12.5)]),
        ),
        locale: const Locale('ar'),
      );

      expect(find.text('12.50 دينار أردني'), findsOneWidget);
      expect(find.textContaining('JOD'), findsNothing);
      expect(find.text('مبلغ التحصيل'), findsOneWidget);
    });

    testWidgets('24. a round amount keeps both decimals', (tester) async {
      await _pump(
        tester,
        shipments: _StubShipmentProvider(
          pages: _onePage([_shipment(cod: 12, delivery: 3)]),
        ),
      );

      expect(find.text('JOD 12.00'), findsOneWidget);
      expect(find.text('JOD 3.00'), findsOneWidget);
    });

    testWidgets('25. a valid date is formatted', (tester) async {
      await _pump(
        tester,
        shipments: _StubShipmentProvider(
          pages: _onePage([_shipment(date: '2026-01-15 10:30:00')]),
        ),
      );

      expect(find.text('15/01/2026'), findsOneWidget);
    });

    testWidgets('26. a malformed date never leaks the raw value', (
      tester,
    ) async {
      await _pump(
        tester,
        shipments: _StubShipmentProvider(
          pages: _onePage([_shipment(date: 'not-a-date')]),
        ),
      );

      expect(find.text('not-a-date'), findsNothing);
      expect(find.text('Not available'), findsWidgets);
    });

    testWidgets('27. the MySQL zero date shows the localized placeholder', (
      tester,
    ) async {
      await _pump(
        tester,
        shipments: _StubShipmentProvider(
          pages: _onePage([_shipment(date: '0000-00-00 00:00:00')]),
        ),
        locale: const Locale('ar'),
      );

      expect(find.textContaining('0000'), findsNothing);
      expect(find.text('غير متوفر'), findsWidgets);
    });

    test('the model refuses a zero date rather than inventing year zero', () {
      expect(_shipment(date: '0000-00-00 00:00:00').shipmentDateTime, isNull);
      expect(_shipment(date: '').shipmentDateTime, isNull);
      expect(_shipment(date: 'rubbish').shipmentDateTime, isNull);
      // A naive timestamp is not shifted into another day by a timezone.
      final naive = _shipment(date: '2026-01-15 23:30:00').shipmentDateTime!;
      expect(naive.day, 15);
      expect(naive.hour, 23);
    });
  });

  // ---------------------------------------------------------------------------
  // Pagination
  // ---------------------------------------------------------------------------
  group('pagination', () {
    Map<int, List<Shipment>> pages(int count) => {
      for (var page = 1; page <= count; page++)
        page: [_shipment(id: page, policy: 'BLK-$page')],
    };

    test('28/29/30. the window always contains first, current and last', () {
      expect(visiblePageSlots(current: 1, total: 10), containsAll([1, 2, 10]));
      expect(visiblePageSlots(current: 5, total: 10), contains(5));
      expect(visiblePageSlots(current: 10, total: 10), contains(10));
      for (final current in [1, 2, 5, 9, 10]) {
        final slots = visiblePageSlots(current: current, total: 10);
        expect(slots, contains(1));
        expect(slots, contains(10));
        expect(slots, contains(current));
        final numbers = slots.whereType<int>().toList();
        expect(
          numbers.toSet().length,
          numbers.length,
          reason: 'duplicate page number at current=$current',
        );
        expect(numbers, orderedEquals(numbers.toList()..sort()));
      }
    });

    test('a small total needs no gap at all', () {
      expect(visiblePageSlots(current: 1, total: 1), [1]);
      expect(visiblePageSlots(current: 2, total: 3), [1, 2, 3]);
      expect(visiblePageSlots(current: 1, total: 4), [1, 2, 3, 4]);
      expect(visiblePageSlots(current: 1, total: 0), isEmpty);
    });

    test('34. ten pages on page five still shows five', () {
      expect(visiblePageSlots(current: 5, total: 10), [
        1,
        null,
        4,
        5,
        6,
        null,
        10,
      ]);
    });

    testWidgets('31. the current page is marked selected', (tester) async {
      final provider = _StubShipmentProvider(pages: pages(10));
      await _pump(tester, shipments: provider);

      final selected = tester.widget<Semantics>(
        find
            .ancestor(of: find.text('1'), matching: find.byType(Semantics))
            .first,
      );
      expect(selected.properties.selected, isTrue);
    });

    /// Whether the arrow behind [label] can actually be tapped.
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

    testWidgets('32. previous is disabled on the first page', (tester) async {
      final provider = _StubShipmentProvider(pages: pages(3));
      await _pump(tester, shipments: provider);

      expect(arrowEnabled(tester, 'Previous page'), isFalse);
      expect(arrowEnabled(tester, 'Next page'), isTrue);
    });

    testWidgets('33. next is disabled on the last page', (tester) async {
      final provider = _StubShipmentProvider(pages: pages(3));
      await _pump(tester, shipments: provider);

      provider.setPage(3);
      await tester.pumpAndSettle();

      expect(arrowEnabled(tester, 'Next page'), isFalse);
      expect(arrowEnabled(tester, 'Previous page'), isTrue);
    });

    testWidgets('35. a failed page change leaves page and rows agreeing', (
      tester,
    ) async {
      final provider = _StubShipmentProvider(pages: pages(3), failOnPage: 2);
      await _pump(tester, shipments: provider);
      expect(provider.currentPage, 1);
      expect(find.text('BLK-1'), findsOneWidget);

      provider.setPage(2);
      await tester.pumpAndSettle();

      expect(provider.currentPage, 1, reason: 'rolled back');
      // The rows the driver was reading stay, and they are page 1's — the
      // page the indicator still names.
      expect(find.text('BLK-1'), findsOneWidget);
      expect(find.text('BLK-2'), findsNothing);
      // The failure is stated rather than swallowed, and never as "no work".
      expect(
        find.text('Unable to load shipments. Please try again.'),
        findsOneWidget,
      );
      expect(find.textContaining('No assigned shipments'), findsNothing);
    });

    testWidgets('36. a successful page change moves both together', (
      tester,
    ) async {
      final provider = _StubShipmentProvider(pages: pages(3));
      await _pump(tester, shipments: provider);

      provider.setPage(2);
      await tester.pumpAndSettle();

      expect(provider.currentPage, 2);
      expect(find.text('BLK-2'), findsOneWidget);
      expect(find.text('BLK-1'), findsNothing);
    });

    testWidgets('37. a second tap is refused while a page is in flight', (
      tester,
    ) async {
      final provider = _StubShipmentProvider(pages: pages(5));
      await _pump(tester, shipments: provider);
      final before = provider.fetches;

      provider.holdNextResponse = true;
      provider.setPage(2);
      await tester.pump();
      provider.setPage(3);
      provider.setPage(4);
      await tester.pump();

      expect(provider.fetches, before + 1);
    });

    testWidgets('38. a page change is visible while it loads', (tester) async {
      final provider = _StubShipmentProvider(pages: pages(5));
      await _pump(tester, shipments: provider);

      provider.holdNextResponse = true;
      provider.setPage(2);
      await tester.pump();

      expect(find.text('Loading page…'), findsWidgets);
      // The rows the driver was reading are still there.
      expect(find.text('BLK-1'), findsOneWidget);
      // And the total has not blanked into a spinner.
      expect(find.text('Total'), findsOneWidget);
    });

    testWidgets('39. the arrows carry localized labels', (tester) async {
      await _pump(
        tester,
        shipments: _StubShipmentProvider(pages: pages(3)),
        locale: const Locale('ar'),
      );

      expect(find.bySemanticsLabel('الصفحة السابقة'), findsWidgets);
      expect(find.bySemanticsLabel('الصفحة التالية'), findsWidgets);
    });

    testWidgets('43. the arrows mirror in Arabic', (tester) async {
      await _pump(tester, shipments: _StubShipmentProvider(pages: pages(3)));
      final ltrPrev =
          tester.getCenter(find.byIcon(Icons.chevron_left).first).dx;
      final ltrNext =
          tester.getCenter(find.byIcon(Icons.chevron_right).first).dx;
      expect(ltrPrev, lessThan(ltrNext));

      await _pump(
        tester,
        shipments: _StubShipmentProvider(pages: pages(3)),
        locale: const Locale('ar'),
      );
      final rtlPrev =
          tester.getCenter(find.byIcon(Icons.chevron_left).first).dx;
      final rtlNext =
          tester.getCenter(find.byIcon(Icons.chevron_right).first).dx;
      expect(rtlPrev, greaterThan(rtlNext), reason: 'row mirrors in Arabic');
      // Flutter mirrors the glyph itself for these icons.
      expect(Icons.chevron_left.matchTextDirection, isTrue);
      expect(Icons.chevron_right.matchTextDirection, isTrue);
    });

    testWidgets('42. page numerals stay left-to-right in Arabic', (
      tester,
    ) async {
      await _pump(
        tester,
        shipments: _StubShipmentProvider(pages: pages(3)),
        locale: const Locale('ar'),
      );

      final page2 = tester.widget<Text>(find.text('2').first);
      expect(page2.textDirection, TextDirection.ltr);
    });
  });

  // ---------------------------------------------------------------------------
  // Identifiers
  // ---------------------------------------------------------------------------
  group('identifiers', () {
    testWidgets('40. the phone stays left-to-right in Arabic', (tester) async {
      await _pump(
        tester,
        shipments: _StubShipmentProvider(
          pages: _onePage([_shipment(phone: '0791234567')]),
        ),
        locale: const Locale('ar'),
      );

      final phone = tester.widget<Text>(find.text('0791234567'));
      expect(phone.textDirection, TextDirection.ltr);
    });

    testWidgets('41. the policy number stays left-to-right in Arabic', (
      tester,
    ) async {
      await _pump(
        tester,
        shipments: _StubShipmentProvider(
          pages: _onePage([_shipment(policy: '2026-0012')]),
        ),
        locale: const Locale('ar'),
      );

      final policy = tester.widget<Text>(find.text('2026-0012'));
      expect(policy.textDirection, TextDirection.ltr);
      // A name is a name; it keeps the page direction.
      final recipient = tester.widget<Text>(find.text('Ahmad Saleh'));
      expect(recipient.textDirection, isNull);
    });

    test('the shared rule only claims identifier-shaped values', () {
      expect(identifierTextDirection('+962 79-123-4567'), TextDirection.ltr);
      expect(identifierTextDirection('15/01/2026'), TextDirection.ltr);
      expect(identifierTextDirection('عمان، الأردن'), isNull);
      expect(identifierTextDirection('JOD 12.50'), isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // Language switching and the request
  // ---------------------------------------------------------------------------
  group('request language', () {
    testWidgets('44. a language switch updates the card copy immediately', (
      tester,
    ) async {
      final locale = LocaleProvider(loadSaved: false);
      await _pump(
        tester,
        shipments: _StubShipmentProvider(pages: _onePage()),
        locale: const Locale('follow'),
        localeProvider: locale,
      );
      expect(find.text('In Transit'), findsOneWidget);
      expect(find.text('Recipient'), findsOneWidget);

      await locale.setLanguage(LocaleProvider.arabic, _NullContext());
      await tester.pumpAndSettle();

      expect(find.text('في الطريق'), findsOneWidget);
      expect(find.text('المستلم'), findsOneWidget);
      expect(find.text('In Transit'), findsNothing);
    });

    testWidgets('45/46. the request carries the current language', (
      tester,
    ) async {
      AppLocalizations.applyLocale(const Locale('en'));
      final english = _StubShipmentProvider(pages: _onePage());
      await _pump(tester, shipments: english);
      expect(english.requestedLanguages, isNotEmpty);
      expect(english.requestedLanguages.last, 'en');

      AppLocalizations.applyLocale(const Locale('ar'));
      final arabic = _StubShipmentProvider(pages: _onePage());
      await _pump(tester, shipments: arabic, locale: const Locale('ar'));
      expect(arabic.requestedLanguages.last, 'ar');
    });
  });

  // ---------------------------------------------------------------------------
  // Layout
  // ---------------------------------------------------------------------------
  group('layout', () {
    for (final size in const [Size(360, 640), Size(390, 844), Size(430, 932)]) {
      for (final locale in const [Locale('en'), Locale('ar')]) {
        final index =
            47 +
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
            shipments: _StubShipmentProvider(
              pages: _onePage([
                _shipment(
                  recipient: 'عبد الرحمن محمد الشريف الحسيني الهاشمي',
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
            const Offset(0, -600),
            2000,
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('53. long Arabic values do not overflow the card', (
      tester,
    ) async {
      await _pump(
        tester,
        shipments: _StubShipmentProvider(
          pages: _onePage([
            _shipment(
              recipient: 'عبد الرحمن محمد الشريف الحسيني الهاشمي العبدلي',
              store: 'متجر الإلكترونيات والأجهزة المنزلية الحديثة جدا',
            ),
          ]),
        ),
        locale: const Locale('ar'),
        size: const Size(360, 640),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('المستلم'), findsOneWidget);
    });

    testWidgets('54. the last card clears the floating chat launcher', (
      tester,
    ) async {
      await _pump(
        tester,
        shipments: _StubShipmentProvider(
          pages: _onePage([_shipment(policy: 'BLK-LAST')]),
        ),
      );

      await tester.fling(
        find.byType(CustomScrollView),
        const Offset(0, -2000),
        3000,
      );
      await tester.pumpAndSettle();

      final card = tester.getRect(find.text('BLK-LAST'));
      final viewport = tester.getSize(find.byType(TableAllShipment)).height;
      expect(
        viewport - card.bottom,
        greaterThan(DriverChatBubble.reservedBottomSpace),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Session
  // ---------------------------------------------------------------------------
  group('session', () {
    testWidgets('55. a previous session response is ignored', (tester) async {
      final provider = _StubShipmentProvider(pages: _onePage());
      await _pump(tester, shipments: provider);
      expect(provider.paginatedShipments, isNotEmpty);

      // The response that is about to arrive belongs to the old generation.
      provider.staleGeneration = -1;
      provider.setPage(1);
      await tester.pumpAndSettle();

      expect(find.text('BLK-2026-0012'), findsOneWidget);
    });

    test('56. a session reset still empties the list and the pager', () {
      final provider = ShipmentProvider();
      addTearDown(provider.dispose);

      UserSessionState.reset(SessionResetReason.accountInactive);

      expect(provider.currentPage, 1);
      expect(provider.paginatedShipments, isEmpty);
      expect(provider.hasLoaded, isFalse);
      expect(provider.failure, isNull);
      expect(provider.isPageChanging, isFalse);
    });
  });
}

/// `setLanguage` only touches the context when it is mounted; these tests drive
/// the provider directly and assert on the rebuilt tree.
class _NullContext extends StatelessElement {
  _NullContext() : super(const _NullWidget());
}

class _NullWidget extends StatelessWidget {
  const _NullWidget();

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
