// Tests for the Driver shipment details screen and the pickup workflow it
// drives.
//
// The page is exercised with real providers whose network calls are stubbed,
// so the state shapes are the real ones: a shipment that cannot be resolved
// really does leave the page with nothing, and a session reset really does
// bump the generation these tests assert against.

import 'package:blockatie/constants/fonts.dart';
import 'package:blockatie/models/shipment.dart';
import 'package:blockatie/provider/bottom_nav.dart';
import 'package:blockatie/provider/chat/driver_chat_conversations_provider.dart';
import 'package:blockatie/provider/home.dart';
import 'package:blockatie/provider/localization.dart';
import 'package:blockatie/provider/order_location.dart';
import 'package:blockatie/provider/orders.dart';
import 'package:blockatie/provider/shipment.dart';
import 'package:blockatie/provider/shipment_instsnt.dart';
import 'package:blockatie/services/auth_secure_store.dart';
import 'package:blockatie/services/auth_services.dart';
import 'package:blockatie/services/driver_chat_service.dart';
import 'package:blockatie/services/user_session_state.dart';
import 'package:blockatie/utils/localization.dart';
import 'package:blockatie/utils/nav.dart';
import 'package:blockatie/utils/text_direction.dart';
import 'package:blockatie/views/pages/orders/order_details.dart';
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

class _StubShipmentProvider extends ShipmentProvider {
  _StubShipmentProvider({List<Shipment>? rows}) : _rows = rows ?? const [];

  List<Shipment> _rows;
  int refreshes = 0;

  set rows(List<Shipment> value) {
    _rows = value;
    notifyListeners();
  }

  @override
  List<Shipment> get paginatedShipments => _rows;

  @override
  Future<void> getAllShipments({bool force = false, int? page}) async {
    refreshes++;
  }
}

class _StubInstantProvider extends ShipmentInstantprovider {
  _StubInstantProvider({this.pickupSucceeds = true});

  bool pickupSucceeds;
  int pickups = 0;
  final List<String> languages = [];

  List<Shipment> _rows = const [];

  set rows(List<Shipment> value) {
    _rows = value;
    notifyListeners();
  }

  @override
  List<Shipment> get paginatedShipments => const [];

  @override
  List<Shipment> get allShipments => _rows;

  @override
  Future<ShipmentActionResult> pickupShipmentFromStore(
    int? shipmentId, {
    String languageCode = 'en',
  }) async {
    pickups++;
    languages.add(languageCode);
    await Future<void>.delayed(Duration.zero);
    return ShipmentActionResult(
      success: pickupSucceeds,
      message:
          pickupSucceeds
              ? (languageCode == 'ar'
                  ? 'تم استلام الطلب من المتجر بنجاح'
                  : 'Shipment has been collected from the store successfully.')
              : (languageCode == 'ar'
                  ? 'تعذر استلام الشحنة من المتجر'
                  : 'Unable to pickup shipment from store'),
    );
  }

  @override
  Future<ShipmentActionResult> markArrivedAtStore(
    int? shipmentId, {
    String languageCode = 'en',
  }) async {
    await Future<void>.delayed(Duration.zero);
    return const ShipmentActionResult(success: true, message: 'Arrived');
  }
}

class _StubHomeProvider extends HomeProvider {
  @override
  Future<void> getOrderStatus({bool force = false}) async {}
}

class _StubOrderLocationProvider extends OrderLocationProvider {
  @override
  Future<void> getShipmentCords(int shipmentId) async {}
}

// -----------------------------------------------------------------------------
// Fixtures
// -----------------------------------------------------------------------------

Shipment _shipment({
  int id = 7001,
  String policy = 'BLK-7001',
  int statusId = 4,
  String statusEn = 'In Transit',
  String statusAr = 'في الطريق',
  int driverId = 501,
  int deliveryTypeId = 1,
  String recipient = 'Ahmad Saleh',
  String phone = '0791234567',
  String storePhone = '0788888888',
  String address = 'Amman, Jordan',
  double cod = 12.5,
  double delivery = 2,
  String created = '2026-01-15 10:30:00',
  String reasonCreated = '',
}) {
  return Shipment.fromJson({
    'id': id,
    'shipment_date': created,
    'created_at': created,
    'policy_num': policy,
    'recipient_name': recipient,
    'recipient_phone': phone,
    'delivery_address': address,
    'shipment_cost': cod,
    'delivery_cost': delivery,
    'shipment_status_id': statusId,
    'shipment_status': statusId,
    'status_name_en': statusEn,
    'status_name_ar': statusAr,
    'message_en': 'Your shipment is moving',
    'message_ar': 'شحنتك في الطريق',
    'nstore': 'Demo Store',
    'lclient': 'Store Street 1',
    'phclient': storePhone,
    'driver_id': driverId,
    'delivery_type_id': deliveryTypeId,
    if (reasonCreated.isNotEmpty) 'action_reason_created_at': reasonCreated,
    if (reasonCreated.isNotEmpty) 'action_reason_note': 'Left with neighbour',
  });
}

// -----------------------------------------------------------------------------
// Harness
// -----------------------------------------------------------------------------

class _Hosts {
  _Hosts({required this.assigned, required this.instant, required this.locale});

  final _StubShipmentProvider assigned;
  final _StubInstantProvider instant;
  final LocaleProvider locale;
}

_Hosts _hosts({List<Shipment>? rows, bool pickupSucceeds = true}) => _Hosts(
  assigned: _StubShipmentProvider(rows: rows),
  instant: _StubInstantProvider(pickupSucceeds: pickupSucceeds),
  locale: LocaleProvider(loadSaved: false),
);

Widget _app(
  _Hosts hosts, {
  required Widget page,
  Locale locale = const Locale('en'),
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<ShipmentProvider>.value(value: hosts.assigned),
      ChangeNotifierProvider<ShipmentInstantprovider>.value(
        value: hosts.instant,
      ),
      ChangeNotifierProvider<LocaleProvider>.value(value: hosts.locale),
      ChangeNotifierProvider<HomeProvider>(create: (_) => _StubHomeProvider()),
      ChangeNotifierProvider<OrderLocationProvider>(
        create: (_) => _StubOrderLocationProvider(),
      ),
      ChangeNotifierProvider(create: (_) => BottomNavProvider()),
      // The chat action on this page reads the app-wide conversations
      // provider, exactly as main.dart registers it.
      ChangeNotifierProvider<DriverChatConversationsProvider>(
        create:
            (_) => DriverChatConversationsProvider(
              repository: DriverChatService(),
            ),
      ),
    ],
    child: Consumer<LocaleProvider>(
      builder:
          (context, value, _) => MaterialApp(
            navigatorKey: Nav.key,
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
            home: page,
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

/// Taps an external-app action and lets the real plugin call resolve.
///
/// url_launcher has no platform implementation under flutter_test, so the
/// call genuinely fails — which is exactly the path these localized strings
/// exist for. `runAsync` is needed because that failure arrives off the fake
/// clock.
Future<void> _tapExternal(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label).first);
  await tester.tap(find.text(label).first);
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 50)),
  );
  await _settle(tester);
}

/// The action button carrying [label], if the card is offering it.
///
/// `byType` matches the exact runtime type, and `ElevatedButton.icon` builds a
/// private subclass, so the predicate form is the one that finds these.
Finder _actionButton(String label) => find.ancestor(
  of: find.text(label),
  matching: find.byWidgetPredicate((widget) => widget is ElevatedButton),
);

/// Bounded pumping: the page's own animations plus a stubbed future settle
/// well inside this, and nothing here depends on a quiet tree.
Future<void> _settle(WidgetTester tester, {int frames = 16}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<void> _pump(
  WidgetTester tester,
  _Hosts hosts, {
  Shipment? shipment,
  int shipmentId = 7001,
  Locale locale = const Locale('en'),
  Size size = const Size(390, 844),
}) async {
  await _setSize(tester, size.width, size.height);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(
    _app(
      hosts,
      locale: locale,
      page: OrderDetailPage(
        shipmentId: shipmentId,
        shipment: shipment,
        phoneCustomer: shipment?.recipientPhone ?? '',
        orderDate: shipment?.createdAt,
      ),
    ),
  );
  await _settle(tester);
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
  // Pickup workflow
  // ---------------------------------------------------------------------------
  group('pickup workflow', () {
    testWidgets('1. status 10 exposes the pickup action', (tester) async {
      await _pump(
        tester,
        _hosts(),
        shipment: _shipment(statusId: 10, statusEn: '', statusAr: ''),
      );

      expect(_actionButton('Picked Up Shipment'), findsOneWidget);
      expect(_actionButton('Arrived at Store'), findsNothing);
    });

    testWidgets('2/7. a driver-owned pickup runs through the fixed path', (
      tester,
    ) async {
      final hosts = _hosts();
      await _pump(tester, hosts, shipment: _shipment(statusId: 10));

      await tester.ensureVisible(_actionButton('Picked Up Shipment'));
      await tester.tap(_actionButton('Picked Up Shipment'));
      await _settle(tester);

      expect(hosts.instant.pickups, 1);
      expect(
        find.text('Shipment has been collected from the store successfully.'),
        findsOneWidget,
      );
      // The authoritative list is refreshed rather than trusted locally.
      expect(hosts.assigned.refreshes, greaterThan(0));
    });

    testWidgets('4. a terminal shipment offers no pickup', (tester) async {
      for (final statusId in const [6, 7, 8, 9, 11]) {
        await _pump(tester, _hosts(), shipment: _shipment(statusId: statusId));
        expect(
          _actionButton('Picked Up Shipment'),
          findsNothing,
          reason: 'status $statusId',
        );
        expect(_actionButton('Update Status'), findsNothing);
      }
    });

    testWidgets('5. a pre-arrival status offers arrival; pickup only where '
        'the server takes it (2)', (tester) async {
      // check_driver_arrival.php takes 1/2/3; mark_as_arrived_driver.php takes
      // 2 or 10, so 1 and 3 must go through arrival first.
      for (final statusId in const [1, 3]) {
        await _pump(tester, _hosts(), shipment: _shipment(statusId: statusId));
        expect(_actionButton('Arrived at Store'), findsOneWidget);
        expect(_actionButton('Picked Up Shipment'), findsNothing);
      }
      await _pump(tester, _hosts(), shipment: _shipment(statusId: 2));
      expect(_actionButton('Arrived at Store'), findsOneWidget);
      expect(_actionButton('Picked Up Shipment'), findsOneWidget);
    });

    testWidgets('6/49. a duplicate tap cannot start a second pickup', (
      tester,
    ) async {
      final hosts = _hosts();
      await _pump(tester, hosts, shipment: _shipment(statusId: 10));

      await tester.ensureVisible(_actionButton('Picked Up Shipment'));
      await tester.tap(_actionButton('Picked Up Shipment'));
      await tester.pump();
      // Busy: the button is disabled while the first request is in flight.
      final button = tester.widget<ElevatedButton>(
        _actionButton('Picked Up Shipment'),
      );
      expect(button.onPressed, isNull);
      await _settle(tester);

      expect(hosts.instant.pickups, 1);
    });

    testWidgets('8. the instant flow calls the same provider method', (
      tester,
    ) async {
      // One method, one endpoint: both screens go through it, so neither can
      // drift back to the generic status endpoint.
      final hosts = _hosts();
      await _pump(tester, hosts, shipment: _shipment(statusId: 10));
      await tester.ensureVisible(_actionButton('Picked Up Shipment'));
      await tester.tap(_actionButton('Picked Up Shipment'));
      await _settle(tester);

      expect(hosts.instant.pickups, 1);
      expect(hosts.instant.languages.single, 'en');
    });

    testWidgets('50. a failed pickup never looks successful', (tester) async {
      final hosts = _hosts(pickupSucceeds: false);
      await _pump(tester, hosts, shipment: _shipment(statusId: 10));

      await tester.ensureVisible(_actionButton('Picked Up Shipment'));
      await tester.tap(_actionButton('Picked Up Shipment'));
      await _settle(tester);

      expect(find.text('Unable to pickup shipment from store'), findsOneWidget);
      // Still offering the action, and nothing claims the new status.
      expect(_actionButton('Picked Up Shipment'), findsOneWidget);
    });

    testWidgets('52. a successful action reconciles with the server', (
      tester,
    ) async {
      final hosts = _hosts();
      await _pump(tester, hosts, shipment: _shipment(statusId: 10));

      await tester.ensureVisible(_actionButton('Picked Up Shipment'));
      await tester.tap(_actionButton('Picked Up Shipment'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await _settle(tester, frames: 30);

      // The lists were re-read but do not hold this shipment. The server
      // confirmed the pickup, so 4 stands: rolling back to 10 used to offer
      // the pickup again and hide Delivered.
      expect(hosts.assigned.refreshes, greaterThan(0));
      expect(_actionButton('Picked Up Shipment'), findsNothing);
      expect(find.byKey(const ValueKey('deliver_action')), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // Status
  // ---------------------------------------------------------------------------
  group('status', () {
    const cases = <int, List<String>>{
      1: ['Pending', 'قيد الانتظار'],
      2: ['Processing', 'قيد التجهيز'],
      4: ['In Transit', 'في الطريق'],
      9: ['Failed Delivery', 'فشل في التسليم'],
      8: ['Returned', 'تم الإرجاع'],
      11: ['Completed', 'مكتمل'],
    };

    var index = 9;
    cases.forEach((statusId, labels) {
      final number = index++;
      testWidgets('$number. status $statusId reads ${labels.first}', (
        tester,
      ) async {
        await _pump(
          tester,
          _hosts(),
          shipment: _shipment(statusId: statusId, statusEn: '', statusAr: ''),
        );
        expect(find.text(labels.first), findsWidgets);

        await _pump(
          tester,
          _hosts(),
          shipment: _shipment(statusId: statusId, statusEn: '', statusAr: ''),
          locale: const Locale('ar'),
        );
        expect(find.text(labels.last), findsWidgets);
      });
    });

    testWidgets('15. a known status never shows an id', (tester) async {
      for (final statusId in const [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]) {
        await _pump(
          tester,
          _hosts(),
          shipment: _shipment(statusId: statusId, statusEn: '', statusAr: ''),
        );
        expect(
          find.textContaining('Status #'),
          findsNothing,
          reason: 'status $statusId',
        );
        expect(find.textContaining('الحالة #'), findsNothing);
      }
    });

    testWidgets('16. the raw provider status is never displayed', (
      tester,
    ) async {
      // OrderStatusProvider defaults to the English literal "Order Placed".
      expect(OrderStatusProvider().currentStatus, 'Order Placed');

      await _pump(
        tester,
        _hosts(),
        shipment: _shipment(statusId: 4, statusEn: '', statusAr: ''),
        locale: const Locale('ar'),
      );

      expect(find.text('Order Placed'), findsNothing);
      expect(find.text('في الطريق'), findsWidgets);
      // The shipment's message is not a status either.
      expect(find.text('شحنتك في الطريق'), findsNothing);
    });

    testWidgets('17. the details wording matches the shared resolver', (
      tester,
    ) async {
      await _pump(
        tester,
        _hosts(),
        shipment: _shipment(statusId: 8, statusEn: '', statusAr: ''),
        locale: const Locale('ar'),
      );

      final context = tester.element(find.byType(OrderDetailPage));
      expect(getStatusLabel(context, 8), 'تم الإرجاع');
      // The status now reads what the lists and the sheet read. "مرتجع" is
      // still correct for the separate return-flag chip, which is why the two
      // must not share a resolver — the old table made the status borrow it.
      expect(find.text('تم الإرجاع'), findsWidgets);
      expect(find.text('حالة المرتجع'), findsOneWidget);
    });

    testWidgets('18. status colours come from the id', (tester) async {
      await _pump(tester, _hosts(), shipment: _shipment(statusId: 9));
      // Failed is never the success green, whatever the English text says.
      expect(getStatusColor(9), isNot(const Color(0xff16A06D)));
      expect(getStatusColor(11), const Color(0xff16A06D));
      expect(getStatusColor(9), getStatusColor(9));
    });
  });

  group('pickup-stage privacy', () {
    testWidgets(
      'a direct Admin assignment remains store-focused until pickup',
      (tester) async {
        await _pump(
          tester,
          _hosts(),
          shipment: _shipment(
            deliveryTypeId: 2,
            statusId: 2,
            recipient: 'Protected Recipient',
            phone: '0791234567',
            address: 'Private Customer Address',
          ),
        );

        expect(find.text('Go to Store'), findsWidgets);
        expect(find.text('Demo Store'), findsOneWidget);
        expect(find.text('Protected Recipient'), findsNothing);
        expect(find.text('0791234567'), findsNothing);
        expect(find.text('Private Customer Address'), findsNothing);
      },
    );

    testWidgets('a picked-up direct Admin assignment shows customer delivery', (
      tester,
    ) async {
      await _pump(
        tester,
        _hosts(),
        shipment: _shipment(
          deliveryTypeId: 2,
          statusId: 4,
          recipient: 'Delivery Recipient',
          phone: '0791234567',
          address: 'Customer Delivery Address',
        ),
      );

      expect(find.text('Customer Delivery'), findsWidgets);
      expect(find.text('Delivery Recipient'), findsOneWidget);
      expect(find.text('0791234567'), findsWidgets);
      expect(find.text('Customer Delivery Address'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // Dates and money
  // ---------------------------------------------------------------------------
  group('dates and money', () {
    testWidgets('19/20. a valid date is formatted and the raw one is absent', (
      tester,
    ) async {
      await _pump(
        tester,
        _hosts(),
        shipment: _shipment(created: '2026-01-15 10:30:00'),
      );

      expect(find.textContaining('15/01/2026'), findsWidgets);
      expect(find.textContaining('2026-01-15'), findsNothing);
      expect(find.textContaining('10:30:00'), findsNothing);
    });

    testWidgets('21/22. a zero or malformed date never reaches the screen', (
      tester,
    ) async {
      await _pump(
        tester,
        _hosts(),
        shipment: _shipment(created: '0000-00-00 00:00:00'),
      );
      expect(find.textContaining('0000'), findsNothing);

      await _pump(tester, _hosts(), shipment: _shipment(created: 'not-a-date'));
      expect(find.textContaining('not-a-date'), findsNothing);
    });

    test('23. the shared parser refuses what it cannot trust', () {
      expect(Shipment.safeDateTime('0000-00-00 00:00:00'), isNull);
      expect(Shipment.safeDateTime('not-a-date'), isNull);
      expect(Shipment.safeDateTime(''), isNull);
      expect(Shipment.safeDateTime(null), isNull);
      // A naive timestamp is not shifted into another day.
      final naive = Shipment.safeDateTime('2026-01-15 23:30:00')!;
      expect(naive.day, 15);
      expect(naive.hour, 23);
    });

    testWidgets('24/25/26. COD wording and precision match the lists', (
      tester,
    ) async {
      await _pump(
        tester,
        _hosts(),
        shipment: _shipment(cod: 12.5, delivery: 3),
      );
      expect(find.text('COD amount'), findsOneWidget);
      expect(find.text('JOD 12.50'), findsOneWidget);
      expect(find.text('JOD 3.00'), findsOneWidget);
      expect(find.text('JOD 3'), findsNothing);

      await _pump(
        tester,
        _hosts(),
        shipment: _shipment(cod: 12.5),
        locale: const Locale('ar'),
      );
      expect(find.text('مبلغ التحصيل'), findsOneWidget);
      expect(find.text('12.50 دينار أردني'), findsOneWidget);
      expect(find.textContaining('JOD'), findsNothing);
    });
  });

  // ---------------------------------------------------------------------------
  // RTL
  // ---------------------------------------------------------------------------
  group('rtl', () {
    testWidgets('27/28. the back chevron mirrors exactly once', (tester) async {
      await _pump(tester, _hosts(), shipment: _shipment());
      expect(find.byIcon(Icons.chevron_left_rounded), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);

      await _pump(
        tester,
        _hosts(),
        shipment: _shipment(),
        locale: const Locale('ar'),
      );
      // Same icon in both languages: Flutter mirrors the glyph itself, so
      // choosing the other one would flip it twice.
      expect(find.byIcon(Icons.chevron_left_rounded), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
      expect(Icons.chevron_left_rounded.matchTextDirection, isTrue);
    });

    testWidgets('29/30. the title uses directional alignment', (tester) async {
      await _pump(tester, _hosts(), shipment: _shipment());
      var title = tester.widget<Text>(find.text('Shipment Details'));
      expect(title.textAlign, TextAlign.start);

      await _pump(
        tester,
        _hosts(),
        shipment: _shipment(),
        locale: const Locale('ar'),
      );
      title = tester.widget<Text>(find.text('تفاصيل الشحنة'));
      expect(title.textAlign, TextAlign.start);
      expect(
        Directionality.of(tester.element(find.text('تفاصيل الشحنة'))),
        TextDirection.rtl,
      );
    });

    testWidgets('31/32/33. identifiers stay left-to-right in Arabic', (
      tester,
    ) async {
      await _pump(
        tester,
        _hosts(),
        shipment: _shipment(
          statusId: 4,
          deliveryTypeId: 2, // scheduled: store and customer cards both show
          phone: '+962 79-123-4567',
          storePhone: '0788888888',
          policy: '2026-0012',
        ),
        locale: const Locale('ar'),
      );

      final policy = tester.widget<Text>(find.text('2026-0012'));
      expect(policy.textDirection, TextDirection.ltr);

      for (final value in const ['+962 79-123-4567', '0788888888']) {
        final matches = tester.widgetList<Text>(find.text(value));
        expect(matches, isNotEmpty, reason: value);
        for (final text in matches) {
          expect(text.textDirection, TextDirection.ltr, reason: value);
        }
      }

      // A name is a name: it keeps the page direction.
      final recipient = tester.widgetList<Text>(find.text('Ahmad Saleh'));
      for (final text in recipient) {
        expect(text.textDirection, isNull);
      }
    });
  });

  // ---------------------------------------------------------------------------
  // Loading, error, retry
  // ---------------------------------------------------------------------------
  group('load states', () {
    testWidgets('34/35. authoritative data renders straight away', (
      tester,
    ) async {
      await _pump(tester, _hosts(), shipment: _shipment());
      expect(find.text('Shipment Details'), findsOneWidget);
      expect(find.textContaining('Unable to load'), findsNothing);
    });

    testWidgets('36/37. a shipment that cannot be resolved shows an error', (
      tester,
    ) async {
      // Opened by id, nothing in the providers: that is a failed read, not a
      // shipment whose every field happens to be empty.
      await _pump(tester, _hosts(), shipmentId: 9999);

      expect(
        find.text('Unable to load shipment details. Please try again.'),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Not available'), findsNothing);
      expect(find.text('Status unavailable'), findsNothing);
    });

    testWidgets('the error state is localized', (tester) async {
      await _pump(
        tester,
        _hosts(),
        shipmentId: 9999,
        locale: const Locale('ar'),
      );
      expect(
        find.text('تعذر تحميل تفاصيل الشحنة. يرجى المحاولة مرة أخرى.'),
        findsOneWidget,
      );
      expect(find.text('حاول مرة أخرى'), findsOneWidget);
      expect(find.textContaining('Dio'), findsNothing);
    });

    testWidgets('38. retry loads the shipment once it is available', (
      tester,
    ) async {
      final hosts = _hosts();
      await _pump(tester, hosts, shipmentId: 7001);
      expect(find.text('Retry'), findsOneWidget);

      hosts.instant.rows = [_shipment(id: 7001, policy: 'BLK-7001')];
      await tester.tap(find.text('Retry'));
      await _settle(tester);

      expect(find.text('BLK-7001'), findsWidgets);
      expect(find.textContaining('Unable to load'), findsNothing);
    });
  });

  // ---------------------------------------------------------------------------
  // Session
  // ---------------------------------------------------------------------------
  group('session', () {
    testWidgets('39/40. a session reset clears the shipment from the screen', (
      tester,
    ) async {
      await _pump(
        tester,
        _hosts(),
        shipment: _shipment(recipient: 'Ahmad Saleh', phone: '0791234567'),
      );
      expect(find.text('Ahmad Saleh'), findsWidgets);

      UserSessionState.reset(SessionResetReason.accountChanged);
      await _settle(tester);

      // Driver A's customer must not still be on screen for Driver B.
      expect(find.text('Ahmad Saleh'), findsNothing);
      expect(find.text('0791234567'), findsNothing);
    });

    testWidgets('41. a stale response is discarded', (tester) async {
      final hosts = _hosts();
      await _pump(tester, hosts, shipmentId: 7001);

      // The reply lands after the session has moved on.
      UserSessionState.reset(SessionResetReason.accountChanged);
      hosts.instant.rows = [_shipment(id: 7001, recipient: 'Previous Driver')];
      await _settle(tester);

      expect(find.text('Previous Driver'), findsNothing);
    });

    test('42. the inactive-account reason still resets state', () {
      final provider = ShipmentProvider();
      addTearDown(provider.dispose);

      UserSessionState.reset(SessionResetReason.accountInactive);

      expect(provider.paginatedShipments, isEmpty);
      expect(provider.currentPage, 1);
    });
  });

  // ---------------------------------------------------------------------------
  // External actions and chat
  // ---------------------------------------------------------------------------
  group('external actions', () {
    testWidgets('43/44/45/46/47/48. failures are localized, never raw', (
      tester,
    ) async {
      // url_launcher has no platform implementation under flutter_test, so a
      // real tap exercises exactly the failure path these strings exist for.
      await _pump(tester, _hosts(), shipment: _shipment(statusId: 4));

      await _tapExternal(tester, 'Call');
      expect(find.text('Unable to start call.'), findsOneWidget);
      expect(find.textContaining('PlatformException'), findsNothing);
      expect(find.textContaining('MissingPluginException'), findsNothing);

      await _tapExternal(tester, 'Open Map');
      expect(find.text('Unable to open maps.'), findsOneWidget);

      await _pump(
        tester,
        _hosts(),
        shipment: _shipment(statusId: 4),
        locale: const Locale('ar'),
      );
      await _tapExternal(tester, 'اتصال');
      expect(find.text('تعذر بدء الاتصال.'), findsOneWidget);

      await _tapExternal(tester, 'فتح الخريطة');
      expect(find.text('تعذر فتح الخرائط.'), findsOneWidget);
    });

    testWidgets('53/54/55. the chat action is localized and guarded', (
      tester,
    ) async {
      await _pump(tester, _hosts(), shipment: _shipment(statusId: 4));
      expect(find.textContaining('Chat'), findsWidgets);

      await _pump(
        tester,
        _hosts(),
        shipment: _shipment(statusId: 4),
        locale: const Locale('ar'),
      );
      // The chat action renders from the shared chat copy, not this page.
      expect(find.byIcon(Icons.chat_bubble_outline_rounded), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // Language
  // ---------------------------------------------------------------------------
  group('language', () {
    testWidgets('66/67/68. a switch updates the page in the same frame', (
      tester,
    ) async {
      final hosts = _hosts();
      await _setSize(tester, 390, 844);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        _app(
          hosts,
          locale: const Locale('follow'),
          page: OrderDetailPage(
            shipmentId: 7001,
            shipment: _shipment(statusId: 4, statusEn: '', statusAr: ''),
            phoneCustomer: '0791234567',
          ),
        ),
      );
      await _settle(tester);
      expect(find.text('Shipment Details'), findsOneWidget);
      expect(find.text('In Transit'), findsWidgets);

      await hosts.locale.setLanguage(LocaleProvider.arabic, _NullContext());
      await _settle(tester);

      expect(find.text('تفاصيل الشحنة'), findsOneWidget);
      expect(find.text('في الطريق'), findsWidgets);
      expect(find.text('Shipment Details'), findsNothing);

      await hosts.locale.setLanguage(LocaleProvider.english, _NullContext());
      await _settle(tester);
      expect(find.text('Shipment Details'), findsOneWidget);
    });

    testWidgets('69. every former shadow-table string renders in Arabic', (
      tester,
    ) async {
      await _pump(
        tester,
        _hosts(),
        shipment: _shipment(statusId: 4),
        locale: const Locale('ar'),
      );

      // A sample across the cards the table used to feed. None may fall back
      // to their English key.
      for (final english in const [
        'Shipment Details',
        'Store',
        'Recipient',
        'Phone',
        'Address',
        'Call',
        'Actions',
        'Notes',
        'Costs',
      ]) {
        expect(find.text(english), findsNothing, reason: english);
      }
      for (final arabic in const [
        'تفاصيل الشحنة',
        'المستلم',
        'الهاتف',
        'العنوان',
        'اتصال',
        'الإجراءات',
      ]) {
        expect(find.text(arabic), findsWidgets, reason: arabic);
      }
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
            _hosts(),
            shipment: _shipment(
              statusId: 4,
              recipient: 'عبد الرحمن محمد الشريف الحسيني الهاشمي',
              address:
                  'عمان، شارع الملكة رانيا العبدالله، مقابل الجامعة '
                  'الأردنية، بناية رقم ١٢٣، الطابق الرابع',
              cod: 987654.32,
            ),
            locale: locale,
            size: size,
          );
          expect(tester.takeException(), isNull);

          await tester.fling(
            find.byType(SingleChildScrollView).first,
            const Offset(0, -900),
            2000,
          );
          await _settle(tester, frames: 40);
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('62/63. long Arabic values and a large COD fit', (
      tester,
    ) async {
      await _pump(
        tester,
        _hosts(),
        shipment: _shipment(statusId: 4, cod: 987654.32),
        locale: const Locale('ar'),
        size: const Size(360, 640),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('987654.32 دينار أردني'), findsOneWidget);
    });

    testWidgets('64/65. the actions clear the floating chat launcher', (
      tester,
    ) async {
      await _pump(tester, _hosts(), shipment: _shipment(statusId: 10));

      await tester.fling(
        find.byType(SingleChildScrollView).first,
        const Offset(0, -3000),
        3000,
      );
      await _settle(tester, frames: 40);

      final viewport = tester.getSize(find.byType(OrderDetailPage)).height;
      final action = tester.getRect(_actionButton('Picked Up Shipment'));
      expect(
        viewport - action.bottom,
        greaterThan(DriverChatBubble.reservedBottomSpace),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Shared helpers
  // ---------------------------------------------------------------------------
  test('identifier rules are unchanged', () {
    expect(identifierTextDirection('+962 79-123-4567'), TextDirection.ltr);
    expect(identifierTextDirection('2026-0012'), TextDirection.ltr);
    expect(identifierTextDirection('عمان، الأردن'), isNull);
    expect(identifierTextDirection('Ahmad Saleh'), isNull);
    expect(isolateIdentifier('عمان، الأردن'), 'عمان، الأردن');
  });
}

/// `setLanguage` only touches the context when it is mounted; these tests
/// drive the provider directly and assert on the rebuilt tree.
class _NullContext extends StatelessElement {
  _NullContext() : super(const _NullWidget());
}

class _NullWidget extends StatelessWidget {
  const _NullWidget();

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
