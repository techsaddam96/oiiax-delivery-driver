// Tests for the shipment tracking screen.
//
// What these start from: the page dialled and opened maps with a bare
// `launchUrl`, so a device without a dialer produced a tap that did nothing and
// an exception nobody saw; it started a 30-second GPS + network loop that
// nothing ever stopped once the driver left; and it kept rendering the previous
// driver's recipient, phone and address across a session boundary.

import 'dart:io';

import 'package:blockatie/models/order_status_modle.dart';
import 'package:blockatie/models/shipment.dart';
import 'package:blockatie/provider/home.dart';
import 'package:blockatie/provider/order_location.dart';
import 'package:blockatie/provider/shipment.dart';
import 'package:blockatie/provider/shipment_instsnt.dart';
import 'package:blockatie/services/driver_action_service.dart';
import 'package:blockatie/services/auth_secure_store.dart';
import 'package:blockatie/services/auth_services.dart';
import 'package:blockatie/services/user_session_state.dart';
import 'package:blockatie/utils/localization.dart';
import 'package:blockatie/utils/nav.dart';
import 'package:blockatie/views/pages/order-location/order_location.dart';
import 'package:blockatie/views/widgets/driver_chat_bubble.dart';
import 'package:blockatie/views/widgets/status_update_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
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

/// The real provider with every platform call replaced, so the page drives the
/// shipped lifecycle and the test can count timer starts and stops.
class _StubOrderLocationProvider extends OrderLocationProvider {
  _StubOrderLocationProvider({this.startFails = false});

  bool startFails;
  int startCalls = 0;
  int stopCalls = 0;
  bool timerRunning = false;

  @override
  Future<void> getShipmentCords(int shipmentId) async {
    isLoading = false;
    notifyListeners();
  }

  @override
  Future<void> loadDriverLocationFallback(int shipmentId) async {}

  @override
  Future<void> startRouteTracking({
    LatLng? destination,
    String? destinationAddressValue,
    String? destinationTitleValue,
  }) async {
    destinationLocation = destination;
    destinationAddress = destinationAddressValue ?? '';
    destinationTitle = destinationTitleValue ?? '';
    isLoading = false;
    notifyListeners();
  }

  @override
  Future<void> startDriverLocationUpdates({
    BuildContext? context,
    bool allowLegacyFallback = false,
  }) async {
    // Mirrors the real guard: a second start while running is a no-op.
    if (timerRunning) return;
    startCalls++;
    if (startFails) {
      trackingStatus = DriverLocationTrackingStatus.permissionRequired;
      notifyListeners();
      return;
    }
    timerRunning = true;
    trackingStatus = DriverLocationTrackingStatus.active;
    hasFreshDeviceLocation = true;
    driverLocation = const LatLng(31.95, 35.91);
    distanceInKm = 2.4;
    driverAddress = 'Amman';
    notifyListeners();
  }

  @override
  void stopDriverLocationUpdates({bool notify = true}) {
    stopCalls++;
    timerRunning = false;
    trackingStatus = DriverLocationTrackingStatus.idle;
    if (notify) notifyListeners();
  }
}

class _StubInstantProvider extends ShipmentInstantprovider {
  _StubInstantProvider({this.succeeds = true});

  bool succeeds;

  /// The server's own sentence. Left empty on purpose: that is the case that
  /// used to produce a blank green SnackBar.
  String message = '';
  int arrivedCalls = 0;
  int pickupCalls = 0;
  String? lastEndpointHint;

  @override
  Future<ShipmentActionResult> markArrivedAtStore(
    int? shipmentId, {
    String languageCode = 'en',
  }) async {
    arrivedCalls++;
    lastEndpointHint = 'check_driver_arrival';
    return ShipmentActionResult(success: succeeds, message: message);
  }

  @override
  Future<ShipmentActionResult> pickupShipmentFromStore(
    int? shipmentId, {
    String languageCode = 'en',
  }) async {
    pickupCalls++;
    lastEndpointHint = 'mark_as_arrived_driver';
    return ShipmentActionResult(success: succeeds, message: message);
  }

  @override
  Future<void> getShipmentsInstant({bool force = false, int? page}) async {}
}

class _StubHomeProvider extends HomeProvider {
  _StubHomeProvider({this.statuses = const <int>[7, 8, 9]});

  List<int> statuses;

  @override
  Future<void> getOrderStatus({bool force = false}) async {
    orderStatusData = OrderStatusData.fromJson({
      'success': true,
      'count': statuses.length,
      'status': [
        for (final id in statuses)
          <String, dynamic>{
            'id': '$id',
            'status_name_en': 'Status $id',
            'status_name_ar': 'حالة $id',
          },
      ],
    });
    notifyListeners();
  }
}

class _StubShipmentProvider extends ShipmentProvider {
  @override
  Future<void> getAllShipments({bool force = false, int? page}) async {}
}

/// Answers the url_launcher channel so the shipped failure paths run.
class _LauncherChannel {
  bool canLaunch = true;
  bool launchSucceeds = true;
  bool throwPlatformException = false;
  final List<String> launched = [];

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/url_launcher'),
          (call) async {
            if (throwPlatformException) {
              throw PlatformException(code: 'ACTIVITY_NOT_FOUND');
            }
            switch (call.method) {
              case 'canLaunch':
                return canLaunch;
              case 'launch':
                launched.add('${call.arguments['url']}');
                return launchSucceeds;
            }
            return null;
          },
        );
  }

  void remove() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/url_launcher'),
          null,
        );
  }
}

// -----------------------------------------------------------------------------
// Fixtures
// -----------------------------------------------------------------------------

Map<String, dynamic> _actionContract(int statusId, int driverId) {
  final enabled = <String>{
    if (driverId > 0 && {1, 2, 3}.contains(statusId)) 'arrive_at_pickup',
    if (driverId > 0 && {2, 10}.contains(statusId)) 'confirm_pickup',
    if (driverId > 0 && statusId == 4) 'complete_delivery',
    if (driverId > 0 && !{6, 7, 8, 11}.contains(statusId)) 'cancel_shipment',
    if (driverId > 0 && !{6, 7, 8, 11}.contains(statusId)) 'return_shipment',
    if (driverId > 0 && !{6, 7, 8, 9, 11}.contains(statusId)) 'failed_delivery',
  };
  const targets = <String, int>{
    'arrive_at_pickup': 10,
    'confirm_pickup': 4,
    'complete_delivery': 11,
    'cancel_shipment': 7,
    'return_shipment': 8,
    'failed_delivery': 9,
  };
  return {
    'driver_action_contract_version': 1,
    'driver_actions': [
      for (final action in targets.entries)
        {
          'id': action.key,
          'target_status_id': action.value,
          'group':
              {7, 8, 9}.contains(action.value) ? 'exception' : 'progression',
          'enabled': enabled.contains(action.key),
        },
    ],
  };
}

Shipment _shipment({
  int id = 7001,
  int statusId = 4,
  int driverId = 501,
  int deliveryTypeId = 1,
  String statusEn = 'In Transit',
  String statusAr = 'في الطريق',
  String lat = '31.9600',
  String lng = '35.9200',
}) {
  return Shipment.fromJson({
    ..._actionContract(statusId, driverId),
    'id': id,
    'shipment_date': '2026-01-15 10:30:00',
    'created_at': '2026-01-15 10:30:00',
    'policy_num': 'BLK-7001',
    'recipient_name': 'Ahmad Saleh',
    'recipient_phone': '0791234567',
    'delivery_address': 'Amman, Jordan',
    'delivery_latitude': lat,
    'delivery_longitude': lng,
    'latitude': '31.9500',
    'longitude': '35.9100',
    'shipment_cost': 12.5,
    'delivery_cost': 2,
    'shipment_status_id': statusId,
    'shipment_status': statusId,
    'status_name_en': statusEn,
    'status_name_ar': statusAr,
    'nstore': 'Demo Store',
    'lclient': 'Store Street 1',
    'phclient': '0788888888',
    'driver_id': driverId,
    'delivery_type_id': deliveryTypeId,
  });
}

// -----------------------------------------------------------------------------
// Harness
// -----------------------------------------------------------------------------

class _Hosts {
  _Hosts({
    _StubOrderLocationProvider? location,
    _StubInstantProvider? instant,
    _StubHomeProvider? home,
  }) : location = location ?? _StubOrderLocationProvider(),
       instant = instant ?? _StubInstantProvider(),
       home = home ?? _StubHomeProvider();

  final _StubOrderLocationProvider location;
  final _StubInstantProvider instant;
  final _StubHomeProvider home;
}

Future<void> _pump(
  WidgetTester tester,
  _Hosts hosts, {
  Locale locale = const Locale('en'),
  Shipment? shipment,
  Size size = const Size(390, 844),
  bool showPage = true,
  bool isInstantFlow = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<DriverActionService>(
          create:
              (_) => DriverActionService(
                loader: (_) async => shipment ?? _shipment(),
              ),
        ),
        ChangeNotifierProvider<OrderLocationProvider>.value(
          value: hosts.location,
        ),
        ChangeNotifierProvider<ShipmentInstantprovider>.value(
          value: hosts.instant,
        ),
        ChangeNotifierProvider<HomeProvider>.value(value: hosts.home),
        ChangeNotifierProvider<ShipmentProvider>(
          create: (_) => _StubShipmentProvider(),
        ),
      ],
      child: MaterialApp(
        navigatorKey: Nav.key,
        locale: locale,
        supportedLocales: const [Locale('en'), Locale('ar')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home:
            showPage
                ? LocationOrderPage(
                  shipmentId: 7001,
                  phoneCustomer: '0791234567',
                  shipment: shipment ?? _shipment(),
                  isInstantFlow: isInstantFlow,
                  storeLocation: const LatLng(31.95, 35.91),
                  storeName: 'Demo Store',
                  storePhone: '0788888888',
                  storeAddress: 'Store Street 1',
                  customerName: 'Ahmad Saleh',
                  customerAddress: 'Amman, Jordan',
                )
                : const Scaffold(body: Text('elsewhere')),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

/// Scrolls the tracking list until [finder] is mounted and on screen.
///
/// The page is a CustomScrollView, so its cards only exist in the element tree
/// once they enter the viewport — `find.text` cannot see them before that.
Future<void> _reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    220,
    scrollable: find.byType(Scrollable).first,
    maxScrolls: 60,
  );
  await tester.pumpAndSettle();
}

/// Pumps a bounded number of frames.
///
/// Used wherever the screen may be showing its loading spinner: a
/// CircularProgressIndicator animates forever, so pumpAndSettle would time out
/// rather than settle.
Future<void> _settleBounded(WidgetTester tester, {int frames = 8}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 40));
  }
}

String _source(String path) => File(path).readAsStringSync();

String _code(String path) => _source(path)
    .split('\n')
    .where(
      (line) =>
          !line.trimLeft().startsWith('//') && !line.trimLeft().startsWith('*'),
    )
    .join('\n');

const _page = 'lib/views/pages/order-location/order_location.dart';
const _provider = 'lib/provider/order_location.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    AuthService.configureForTesting(secureStore: _FakeSecureStore());
    AppLocalizations.applyLocale(const Locale('en'));
  });

  tearDown(AuthService.resetForTesting);

  // ---------------------------------------------------------------------------
  group('session', () {
    testWidgets('1. Driver A data renders initially', (tester) async {
      final hosts = _Hosts();
      addTearDown(hosts.location.dispose);
      await _pump(tester, hosts);

      expect(find.text('Shipment Tracking'), findsOneWidget);
      await _reveal(tester, find.text('BLK-7001'));
      expect(find.text('BLK-7001'), findsOneWidget);
      await _reveal(tester, find.text('Call Recipient'));
      expect(find.text('Call Recipient'), findsOneWidget);
    });

    testWidgets('2/3. a session change hides the previous driver', (
      tester,
    ) async {
      final hosts = _Hosts();
      addTearDown(hosts.location.dispose);
      await _pump(tester, hosts);
      await _reveal(tester, find.text('Call Recipient'));
      expect(find.text('Call Recipient'), findsOneWidget);

      UserSessionState.reset(SessionResetReason.accountChanged);
      await _settleBounded(tester);

      // Nothing of Driver A's job is readable or actionable any more.
      expect(find.text('Call Recipient'), findsNothing);
      expect(find.text('BLK-7001'), findsNothing);
    });

    test('4/5. actions are gated on the captured generation', () {
      final source = _code(_page);
      expect(source.contains('bool get _sessionIsCurrent'), isTrue);
      // Call, maps, both stage actions and the status sheet all consult it.
      expect(
        '_sessionIsCurrent'.allMatches(source).length,
        greaterThanOrEqualTo(7),
      );
      expect(source.contains('UserSessionState.changes.addListener'), isTrue);
      expect(
        source.contains('UserSessionState.changes.removeListener'),
        isTrue,
      );
    });

    test('6. a late action result is refused', () {
      final source = _code(_page);
      // Every step (arrival, pickup, delivery) and the re-read after a
      // refusal re-check after the await, not only `mounted`.
      expect(
        'if (!mounted || !_sessionIsCurrent) return;'.allMatches(source).length,
        4,
      );
    });
  });

  // ---------------------------------------------------------------------------
  group('timer lifecycle', () {
    testWidgets('7. the page starts tracking once', (tester) async {
      final hosts = _Hosts();
      addTearDown(hosts.location.dispose);
      await _pump(tester, hosts);

      expect(hosts.location.startCalls, 1);
      expect(hosts.location.timerRunning, isTrue);
    });

    testWidgets('8. leaving the page stops the timer', (tester) async {
      final hosts = _Hosts();
      addTearDown(hosts.location.dispose);
      await _pump(tester, hosts);
      expect(hosts.location.timerRunning, isTrue);

      await _pump(tester, hosts, showPage: false);
      await tester.pumpAndSettle();

      expect(hosts.location.timerRunning, isFalse);
      expect(hosts.location.stopCalls, greaterThanOrEqualTo(1));
    });

    testWidgets('9. pull to refresh does not stack a second timer', (
      tester,
    ) async {
      final hosts = _Hosts();
      addTearDown(hosts.location.dispose);
      await _pump(tester, hosts);

      await tester.fling(
        find.byType(CustomScrollView),
        const Offset(0, 320),
        1000,
      );
      await tester.pumpAndSettle();

      expect(hosts.location.startCalls, 1);
    });

    testWidgets('10. an account reset stops the timer', (tester) async {
      final hosts = _Hosts();
      addTearDown(hosts.location.dispose);
      await _pump(tester, hosts);

      UserSessionState.reset(SessionResetReason.accountChanged);
      await _settleBounded(tester);

      expect(hosts.location.timerRunning, isFalse);
    });

    testWidgets('11. re-entering starts a fresh one', (tester) async {
      final hosts = _Hosts();
      addTearDown(hosts.location.dispose);
      await _pump(tester, hosts);
      await _pump(tester, hosts, showPage: false);
      await tester.pumpAndSettle();
      expect(hosts.location.timerRunning, isFalse);

      await _pump(tester, hosts);
      expect(hosts.location.timerRunning, isTrue);
      expect(hosts.location.startCalls, 2);
    });
  });

  // ---------------------------------------------------------------------------
  group('external actions', () {
    late _LauncherChannel channel;

    setUp(() {
      channel = _LauncherChannel()..install();
    });
    tearDown(() => channel.remove());

    testWidgets('12. a call hands off to the dialler', (tester) async {
      final hosts = _Hosts();
      addTearDown(hosts.location.dispose);
      await _pump(tester, hosts);

      await _reveal(tester, find.text('Call Recipient'));
      await tester.tap(find.text('Call Recipient'));
      await tester.pumpAndSettle();

      expect(channel.launched.single, startsWith('tel:'));
      expect(find.text('Unable to open this contact option.'), findsNothing);
    });

    testWidgets('13. nothing can dial — English', (tester) async {
      channel.canLaunch = false;
      final hosts = _Hosts();
      addTearDown(hosts.location.dispose);
      await _pump(tester, hosts);

      await _reveal(tester, find.text('Call Recipient'));
      await tester.tap(find.text('Call Recipient'));
      await tester.pumpAndSettle();

      expect(find.text('Unable to open this contact option.'), findsOneWidget);
    });

    testWidgets('14. nothing can dial — Arabic', (tester) async {
      channel.canLaunch = false;
      final hosts = _Hosts();
      addTearDown(hosts.location.dispose);
      await _pump(tester, hosts, locale: const Locale('ar'));

      await _reveal(tester, find.text('اتصال بالمستلم'));
      await tester.tap(find.text('اتصال بالمستلم'));
      await tester.pumpAndSettle();

      expect(find.text('تعذر فتح وسيلة التواصل.'), findsOneWidget);
    });

    testWidgets('15. a PlatformException from the dialler is absorbed', (
      tester,
    ) async {
      channel.throwPlatformException = true;
      final hosts = _Hosts();
      addTearDown(hosts.location.dispose);
      await _pump(tester, hosts);

      await _reveal(tester, find.text('Call Recipient'));
      await tester.tap(find.text('Call Recipient'));
      await tester.pumpAndSettle();

      expect(find.text('Unable to open this contact option.'), findsOneWidget);
      expect(find.textContaining('PlatformException'), findsNothing);
      expect(find.textContaining('ACTIVITY_NOT_FOUND'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('16. maps hands off', (tester) async {
      final hosts = _Hosts();
      addTearDown(hosts.location.dispose);
      await _pump(tester, hosts);

      await _reveal(tester, find.text('Open Maps'));
      await tester.tap(find.text('Open Maps'));
      await tester.pumpAndSettle();

      expect(channel.launched.single, contains('google.com/maps'));
    });

    testWidgets('17. no maps app — English', (tester) async {
      channel.canLaunch = false;
      final hosts = _Hosts();
      addTearDown(hosts.location.dispose);
      await _pump(tester, hosts);

      await _reveal(tester, find.text('Open Maps'));
      await tester.tap(find.text('Open Maps'));
      await tester.pumpAndSettle();

      expect(find.text('Unable to open maps.'), findsOneWidget);
    });

    testWidgets('18. no maps app — Arabic', (tester) async {
      channel.canLaunch = false;
      final hosts = _Hosts();
      addTearDown(hosts.location.dispose);
      await _pump(tester, hosts, locale: const Locale('ar'));

      await _reveal(tester, find.text('فتح الخرائط'));
      await tester.tap(find.text('فتح الخرائط'));
      await tester.pumpAndSettle();

      expect(find.text('تعذر فتح الخرائط.'), findsOneWidget);
    });

    testWidgets('19. a PlatformException from maps is absorbed', (
      tester,
    ) async {
      channel.throwPlatformException = true;
      final hosts = _Hosts();
      addTearDown(hosts.location.dispose);
      await _pump(tester, hosts);

      await _reveal(tester, find.text('Open Maps'));
      await tester.tap(find.text('Open Maps'));
      await tester.pumpAndSettle();

      expect(find.text('Unable to open maps.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    test('the shared helper is the only launcher here', () {
      final source = _code(_page);
      expect(source.contains('openExternalUri('), isTrue);
      expect(source.contains('await launchUrl('), isFalse);
      expect(source.contains("import 'package:url_launcher"), isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  group('locale', () {
    testWidgets('20. English copy', (tester) async {
      final hosts = _Hosts();
      addTearDown(hosts.location.dispose);
      await _pump(tester, hosts);

      expect(find.text('Shipment Tracking'), findsOneWidget);
      await _reveal(tester, find.text('Driver Location'));
      expect(find.text('Driver Location'), findsOneWidget);
      expect(
        Directionality.of(tester.element(find.text('Shipment Tracking'))),
        TextDirection.ltr,
      );
    });

    testWidgets('21. Arabic copy', (tester) async {
      final hosts = _Hosts();
      addTearDown(hosts.location.dispose);
      await _pump(tester, hosts, locale: const Locale('ar'));

      expect(find.text('تتبع الشحنة'), findsOneWidget);
      await _reveal(tester, find.text('موقع السائق'));
      expect(find.text('موقع السائق'), findsOneWidget);
      expect(
        Directionality.of(tester.element(find.text('تتبع الشحنة'))),
        TextDirection.rtl,
      );
    });

    testWidgets('22/23. a language switch takes effect immediately', (
      tester,
    ) async {
      final hosts = _Hosts();
      addTearDown(hosts.location.dispose);
      await _pump(tester, hosts);
      expect(find.text('Shipment Tracking'), findsOneWidget);

      await _pump(tester, hosts, locale: const Locale('ar'));
      expect(find.text('تتبع الشحنة'), findsOneWidget);
      expect(find.text('Shipment Tracking'), findsNothing);

      await _pump(tester, hosts);
      expect(find.text('Shipment Tracking'), findsOneWidget);
      expect(find.text('تتبع الشحنة'), findsNothing);
    });

    test('24. no visible EasyLocalization dependency remains', () {
      final source = _source(_page);
      expect(source.contains('context.locale'), isFalse);
      expect(source.contains("import 'package:easy_localization"), isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  group('status', () {
    test('25/26. the shared label table is the only one', () {
      final source = _code(_page);
      expect(source.contains('getStatusLabel('), isTrue);
      // The private eleven-row copy is gone.
      expect(
        source.contains("'Awaiting Pickup', 'في انتظار الاستلام'"),
        isFalse,
      );
      expect(source.contains("'Failed Delivery', 'فشل التسليم'"), isFalse);

      // Arabic 9 now comes from the shared table.
      final shared = _source('lib/views/widgets/status_update_sheet.dart');
      expect(shared.contains("9: 'فشل في التسليم'"), isTrue);
    });

    testWidgets('27. a confirmed arrival advances the visible stage', (
      tester,
    ) async {
      final hosts = _Hosts(instant: _StubInstantProvider(succeeds: true));
      addTearDown(hosts.location.dispose);
      await _pump(tester, hosts, shipment: _shipment(statusId: 2));

      // Revealed with the plain finder — scrollUntilVisible cannot take a
      // `.first` finder while the match set is still empty.
      await _reveal(tester, find.text('Arrived at Store'));
      expect(find.text('Arrived at Store'), findsWidgets);
      await tester.tap(find.text('Arrived at Store').last);
      await tester.pumpAndSettle();

      expect(hosts.instant.arrivedCalls, 1);
      expect(find.text('Arrival confirmed.'), findsOneWidget);
      // Stage moved on: the next action is now pickup.
      expect(find.text('Picked Up Shipment'), findsOneWidget);
    });

    testWidgets('28/31. pickup uses the corrected path and advances', (
      tester,
    ) async {
      final hosts = _Hosts(instant: _StubInstantProvider(succeeds: true));
      addTearDown(hosts.location.dispose);
      await _pump(tester, hosts, shipment: _shipment(statusId: 10));

      await _reveal(tester, find.text('Picked Up Shipment'));
      await tester.tap(find.text('Picked Up Shipment'));
      await tester.pumpAndSettle();

      expect(hosts.instant.pickupCalls, 1);
      // 10 -> 4 goes through mark_as_arrived_driver.php, never the generic
      // status endpoint, which refuses 4.
      expect(hosts.instant.lastEndpointHint, 'mark_as_arrived_driver');
      expect(find.text('Shipment picked up successfully.'), findsOneWidget);
    });

    testWidgets('29. a failed action leaves the stage alone', (tester) async {
      final hosts = _Hosts(instant: _StubInstantProvider(succeeds: false));
      addTearDown(hosts.location.dispose);
      await _pump(tester, hosts, shipment: _shipment(statusId: 10));

      await _reveal(tester, find.text('Picked Up Shipment'));
      await tester.tap(find.text('Picked Up Shipment'));
      await tester.pumpAndSettle();

      expect(
        find.text('Unable to pickup shipment from store.'),
        findsOneWidget,
      );
      // Still the same action, so the stage did not advance.
      expect(find.text('Picked Up Shipment'), findsOneWidget);
    });

    testWidgets('30. a sheet with no selectable status is not opened', (
      tester,
    ) async {
      // The server offers only 6 and 11, which the shared sheet never lists.
      final hosts = _Hosts(home: _StubHomeProvider(statuses: const [6, 11]));
      addTearDown(hosts.location.dispose);
      await _pump(tester, hosts, shipment: _shipment(statusId: 4));

      await _reveal(tester, find.text('Update Status'));
      await tester.tap(find.text('Update Status'));
      await tester.pumpAndSettle();

      expect(find.byType(ShipmentStatusUpdateSheet), findsNothing);
      expect(
        find.text('No status updates are available for this shipment.'),
        findsOneWidget,
      );
    });

    testWidgets('a selectable status does open the shared sheet', (
      tester,
    ) async {
      final hosts = _Hosts(home: _StubHomeProvider(statuses: const [7, 8, 9]));
      addTearDown(hosts.location.dispose);
      await _pump(tester, hosts, shipment: _shipment(statusId: 4));

      await _reveal(tester, find.text('Update Status'));
      await tester.tap(find.text('Update Status'));
      await tester.pumpAndSettle();

      expect(find.byType(ShipmentStatusUpdateSheet), findsOneWidget);
    });

    test('the page filters through the shared selectable set', () {
      final source = _code(_page);
      expect(source.contains('driverSelectableStatusIds.contains'), isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  group('Admin assignment destination', () {
    testWidgets('pre-pickup routes a direct assignment to the store', (
      tester,
    ) async {
      final hosts = _Hosts();
      addTearDown(hosts.location.dispose);
      await _pump(
        tester,
        hosts,
        isInstantFlow: false,
        shipment: _shipment(statusId: 2, deliveryTypeId: 2),
      );

      await _reveal(tester, find.text('Call Store'));
      expect(find.text('Call Store'), findsOneWidget);
      expect(find.text('Call Recipient'), findsNothing);
      expect(hosts.location.destinationTitle, 'Store Location');
      expect(hosts.location.destinationAddress, 'Store Street 1');
    });

    testWidgets('after pickup routes a direct assignment to the customer', (
      tester,
    ) async {
      final hosts = _Hosts();
      addTearDown(hosts.location.dispose);
      await _pump(
        tester,
        hosts,
        isInstantFlow: false,
        shipment: _shipment(statusId: 4, deliveryTypeId: 2),
      );

      await _reveal(tester, find.text('Call Recipient'));
      expect(find.text('Call Recipient'), findsOneWidget);
      expect(find.text('Call Store'), findsNothing);
      expect(hosts.location.destinationTitle, 'Customer Location');
      expect(hosts.location.destinationAddress, 'Amman, Jordan');
    });
  });

  // ---------------------------------------------------------------------------
  group('coordinates', () {
    Shipment withCoords(String lat, String lng) =>
        _shipment(lat: lat, lng: lng);

    testWidgets('32. a normal pair is accepted', (tester) async {
      final hosts = _Hosts();
      addTearDown(hosts.location.dispose);
      await _pump(tester, hosts, shipment: withCoords('31.96', '35.92'));
      expect(tester.takeException(), isNull);
      expect(find.text('Shipment Tracking'), findsOneWidget);
    });

    for (final bad in const [
      ['33. null', '', ''],
      ['34. zero pair', '0', '0'],
      ['36. NaN', 'NaN', 'NaN'],
      ['37. Infinity', 'Infinity', '-Infinity'],
    ]) {
      testWidgets('${bad[0]} is rejected without crashing', (tester) async {
        final hosts = _Hosts();
        addTearDown(hosts.location.dispose);
        await _pump(tester, hosts, shipment: withCoords(bad[1], bad[2]));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }

    test('35/36/37. validation checks finiteness before range', () {
      for (final path in const [_page, _provider]) {
        final source = _code(path);
        expect(
          source.contains('!lat.isFinite || !lng.isFinite'),
          isTrue,
          reason: path,
        );
        expect(source.contains('lat == 0 && lng == 0'), isTrue, reason: path);
      }
      // Swapped Jordan pairs are still corrected.
      expect(_code(_page).contains('_looksLikeSwappedJordanPair'), isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  group('location failure', () {
    testWidgets('38/39. a permission problem offers Open Settings', (
      tester,
    ) async {
      final hosts = _Hosts(
        location: _StubOrderLocationProvider(startFails: true),
      );
      addTearDown(hosts.location.dispose);
      await _pump(tester, hosts);
      await tester.pumpAndSettle();

      expect(find.text('Open Settings'), findsOneWidget);
      expect(
        find.text(
          'Location permission is permanently denied. Enable it in app settings.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('40/41. an unavailable reading offers Retry', (tester) async {
      final hosts = _Hosts(
        location: _StubOrderLocationProvider(startFails: true),
      );
      hosts.location.trackingStatus = DriverLocationTrackingStatus.unavailable;
      addTearDown(hosts.location.dispose);
      await _pump(tester, hosts);
      hosts.location.trackingStatus = DriverLocationTrackingStatus.unavailable;
      hosts.location.notifyListeners();
      await tester.pumpAndSettle();

      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Unable to get your location.'), findsOneWidget);
    });

    test('42. the remedy is chosen by failure type, not by prose', () {
      final source = _code(_page);
      expect(source.contains('locationFailureOffersSettings('), isTrue);
      expect(source.contains('locationFailureMessage('), isTrue);
      expect(source.contains(r'$e'), isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  group('rtl and identifiers', () {
    test('43. the back icon is not mirrored twice', () {
      final source = _code(_page);
      // One direction-aware icon; Flutter does the mirroring.
      expect(
        source.contains('isRtl\n                            ? Icons.chevron'),
        isFalse,
      );
      expect(source.contains('Icons.chevron_right_rounded'), isFalse);
      expect(source.contains('icon: Icons.chevron_left_rounded'), isTrue);
    });

    test('44/45. identifiers and figures are isolated', () {
      final source = _code(_page);
      expect(source.contains('identifierTextDirection(policyNumber)'), isTrue);
      expect(source.contains('isolateIdentifier('), isTrue);
      expect(source.contains("DateFormat('HH:mm', 'en')"), isTrue);
    });

    test('46. page-local physical direction is gone', () {
      final source = _code(_page);
      expect(source.contains('Alignment.centerLeft'), isFalse);
      expect(source.contains('Alignment.centerRight'), isFalse);
      expect(source.contains('TextAlign.left'), isFalse);
      expect(source.contains('TextAlign.right'), isFalse);
    });

    testWidgets('the back control carries a language-correct tooltip', (
      tester,
    ) async {
      final hosts = _Hosts();
      addTearDown(hosts.location.dispose);
      await _pump(tester, hosts, locale: const Locale('ar'));

      final arabic = tester.widget<Tooltip>(
        find
            .ancestor(
              of: find.byIcon(Icons.chevron_left_rounded),
              matching: find.byType(Tooltip),
            )
            .first,
      );
      expect(arabic.message, 'رجوع');

      await _pump(tester, hosts);
      final english = tester.widget<Tooltip>(
        find
            .ancestor(
              of: find.byIcon(Icons.chevron_left_rounded),
              matching: find.byType(Tooltip),
            )
            .first,
      );
      expect(english.message, 'Back');
    });
  });

  // ---------------------------------------------------------------------------
  group('chat bubble', () {
    test('47. clearance is read from the launcher', () {
      final source = _code(_page);
      expect(
        source.contains('DriverChatBubble.reservedBottomSpace + 16'),
        isTrue,
      );
      expect(source.contains('16, 16, 16, 150'), isFalse);
    });

    testWidgets('the list reserves at least the launcher height', (
      tester,
    ) async {
      final hosts = _Hosts();
      addTearDown(hosts.location.dispose);
      await _pump(tester, hosts, size: const Size(360, 640));

      final sliver = tester.widget<SliverPadding>(
        find.byType(SliverPadding).first,
      );
      expect(
        (sliver.padding as EdgeInsets).bottom,
        greaterThanOrEqualTo(DriverChatBubble.reservedBottomSpace),
      );
    });

    test('48. the shared observer still owns modal hiding', () {
      final observer = _code('lib/utils/driver_chat_launcher_observer.dart');
      expect(observer.contains('setModalRouteOpen(top is PopupRoute)'), isTrue);
      // This page does not hide the bubble itself.
      expect(_code(_page).contains('setModalRouteOpen'), isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  group('layout', () {
    for (final size in const [Size(360, 640), Size(390, 844), Size(430, 932)]) {
      for (final locale in const [Locale('en'), Locale('ar')]) {
        testWidgets('49-54. ${size.width.toInt()}x${size.height.toInt()} '
            '${locale.languageCode}', (tester) async {
          final hosts = _Hosts();
          addTearDown(hosts.location.dispose);
          await _pump(tester, hosts, locale: locale, size: size);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('55/56. long Arabic names and addresses do not overflow', (
      tester,
    ) async {
      final hosts = _Hosts();
      addTearDown(hosts.location.dispose);
      hosts.location.destinationAddress =
          'شارع الملك عبدالله الثاني، مجمع الأعمال التجاري، الطابق الخامس، عمان';
      await _pump(tester, hosts, locale: const Locale('ar'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}
