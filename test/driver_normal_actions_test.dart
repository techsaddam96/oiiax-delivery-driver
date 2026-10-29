import 'package:blockatie/services/driver_action_service.dart';
// The driver's normal shipment steps — arrival at the store, pickup and
// delivery — on every screen that shows a shipment.
//
// Regression for the owner's report: the only visible status actions were
// Failed Delivery / Cancelled / Returned. The forward steps were derived from
// the delivery type, so a scheduled shipment never offered arrival or pickup
// (and so could never reach In Transit, the one status Delivered is offered
// from), the tracking screen had no Delivered button at all, and the assigned
// list and the active instant card offered no step of their own.
//
// The pages are the real ones. Behind them a fake server holds each
// shipment's status and driver and accepts exactly what the backend accepts:
//   check_driver_arrival.php      1/2/3 -> 10   (assigned driver only)
//   mark_as_arrived_driver.php    2/10  -> 4
//   complete_shipment_driver.php  4     -> 11
// so a test can walk a shipment through the normal workflow instead of
// forcing statuses, and a screen that offered a step the server refuses
// would fail here.

import 'dart:async';

import 'package:blockatie/constants/fonts.dart';
import 'package:blockatie/models/driver_profile.dart';
import 'package:blockatie/models/order_status_modle.dart';
import 'package:blockatie/models/shipment.dart';
import 'package:blockatie/provider/bottom_nav.dart';
import 'package:blockatie/provider/chat/driver_chat_conversations_provider.dart';
import 'package:blockatie/provider/home.dart';
import 'package:blockatie/provider/localization.dart';
import 'package:blockatie/provider/notification.dart';
import 'package:blockatie/provider/order_location.dart';
import 'package:blockatie/provider/profile.dart';
import 'package:blockatie/provider/shipment.dart';
import 'package:blockatie/provider/shipment_flow_config.dart';
import 'package:blockatie/provider/shipment_instsnt.dart';
import 'package:blockatie/services/auth_secure_store.dart';
import 'package:blockatie/services/auth_services.dart';
import 'package:blockatie/services/driver_chat_service.dart';
import 'package:blockatie/utils/driver_shipment_actions.dart';
import 'package:blockatie/utils/localization.dart';
import 'package:blockatie/utils/nav.dart';
import 'package:blockatie/utils/size_config.dart';
import 'package:blockatie/views/pages/home/components/order_tile.dart';
import 'package:blockatie/views/pages/home/tabs/all-shipments/table_all_shipment.dart';
import 'package:blockatie/views/pages/home/tabs/shipment-instant/shipment_instant.dart';
import 'package:blockatie/views/pages/order-location/order_location.dart';
import 'package:blockatie/views/pages/orders/order_details.dart';
import 'package:blockatie/views/widgets/status_update_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _actionContract(int status, int owner) {
  final owned = owner == 601;
  final actions = <String, int>{
    'arrive_at_pickup': 10,
    'confirm_pickup': 4,
    'complete_delivery': 11,
    'failed_delivery': 9,
    'cancel_shipment': 7,
    'return_shipment': 8,
  };
  final legal = <String>{
    if (owned && {1, 2, 3}.contains(status)) 'arrive_at_pickup',
    if (owned && {2, 10}.contains(status)) 'confirm_pickup',
    if (owned && status == 4) 'complete_delivery',
    if (owned && !{6, 7, 8, 11}.contains(status)) ...[
      'cancel_shipment',
      'return_shipment',
    ],
    if (owned && !{6, 7, 8, 9, 11}.contains(status)) 'failed_delivery',
  };
  return {
    'driver_action_contract_version': 1,
    'driver_lifecycle': [
      for (var id = 1; id <= 11; id++)
        {'id': id, 'status_name_en': '', 'status_name_ar': ''},
    ],
    'driver_actions': [
      for (final e in actions.entries)
        {
          'id': e.key,
          'target_status_id': e.value,
          'enabled': legal.contains(e.key),
          'group': {7, 8, 9}.contains(e.value) ? 'exception' : 'progression',
          'label_en': '',
          'label_ar': '',
        },
    ],
  };
}

Shipment _authorizedFixture(int status, int owner) => Shipment.fromJson({
  'id': 1,
  'driver_id': owner,
  'shipment_status_id': status,
  ..._actionContract(status, owner),
});

const int _me = 601;
const int _otherDriver = 602;

// -----------------------------------------------------------------------------
// Fake server
// -----------------------------------------------------------------------------

class _Row {
  _Row({required this.status, required this.driver, required this.type});

  int status;
  int driver;
  final int type;
}

class _Server {
  final Map<int, _Row> rows = {};
  final List<String> calls = [];

  void add(int id, {required int status, int driver = _me, int type = 2}) {
    rows[id] = _Row(status: status, driver: driver, type: type);
  }

  Shipment shipment(int id) {
    final row = rows[id]!;
    return Shipment.fromJson({
      ..._actionContract(row.status, row.driver),
      'id': id,
      'shipment_date': '2026-10-26 09:00:00',
      'created_at': '2026-10-26 09:00:00',
      'policy_num': 'QA-$id',
      'recipient_name': 'Ahmad Saleh',
      'recipient_phone': '0791234567',
      'delivery_address': 'Amman, Jordan',
      'delivery_latitude': '31.9600',
      'delivery_longitude': '35.9200',
      'latitude': '31.9500',
      'longitude': '35.9100',
      'shipment_cost': 12.5,
      'delivery_cost': 2,
      'shipment_status_id': row.status,
      'shipment_status': row.status,
      'status_name_en': '',
      'status_name_ar': '',
      'nstore': 'Demo Store',
      'lclient': 'Store Street 1',
      'phclient': '0788888888',
      'driver_id': row.driver,
      'delivery_type_id': row.type,
    });
  }

  /// What api_shipments_driver.php returns: this driver's shipments.
  List<Shipment> mine() => [
    for (final entry in rows.entries)
      if (entry.value.driver == _me) shipment(entry.key),
  ];

  ShipmentActionResult arrive(int id) {
    calls.add('arrive:$id');
    final row = rows[id]!;
    if (row.driver != _me) {
      return const ShipmentActionResult(
        success: false,
        code: 'SHIPMENT_ASSIGNED_TO_ANOTHER_DRIVER',
        httpStatus: 403,
        message: 'Shipment is assigned to another driver',
      );
    }
    if (row.status == 10) {
      return const ShipmentActionResult(
        success: true,
        code: 'ARRIVAL_ALREADY_PROCESSED',
        message: 'This arrival request was already processed successfully',
      );
    }
    if (!const {1, 2, 3}.contains(row.status)) {
      return const ShipmentActionResult(
        success: false,
        code: 'TRANSITION_NOT_ALLOWED',
        message: 'Arrival at the store can no longer be confirmed',
      );
    }
    row.status = 10;
    return const ShipmentActionResult(
      success: true,
      code: 'ARRIVAL_CONFIRMED',
      message: 'Arrival at the store was confirmed',
    );
  }

  ShipmentActionResult pickUp(int id) {
    calls.add('pickup:$id');
    final row = rows[id]!;
    if (row.driver != _me) {
      return const ShipmentActionResult(
        success: false,
        code: 'NOT_ASSIGNED',
        message: 'You are not assigned to this shipment.',
      );
    }
    if (!const {2, 10}.contains(row.status)) {
      return const ShipmentActionResult(
        success: false,
        code: 'INVALID_STATUS',
        message: 'This shipment cannot be marked as collected.',
      );
    }
    row.status = 4;
    return const ShipmentActionResult(
      success: true,
      code: 'SHIPMENT_COLLECTED',
      message: 'Shipment has been collected from the store successfully.',
    );
  }

  ShipmentActionResult deliver(int id) {
    calls.add('deliver:$id');
    final row = rows[id]!;
    if (row.driver != _me) {
      return const ShipmentActionResult(
        success: false,
        code: 'NOT_ASSIGNED',
        httpStatus: 403,
        message: 'You are not assigned to this shipment.',
      );
    }
    if (row.status != 4) {
      return const ShipmentActionResult(
        success: false,
        code: 'INVALID_STATUS',
        httpStatus: 409,
        message: 'Shipment must be in transit before it can be completed.',
      );
    }
    row.status = 11;
    return const ShipmentActionResult(
      success: true,
      code: 'SHIPMENT_COMPLETED',
      httpStatus: 200,
      message: 'Shipment has been marked as delivered successfully.',
    );
  }
}

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

/// Each step goes to the fake server, under the same one-request-per-shipment
/// rule the real provider keeps.
class _StubInstant extends ShipmentInstantprovider {
  _StubInstant(this.server);

  final _Server server;
  final Set<int> _busy = {};
  Completer<void>? gate;
  int refreshes = 0;

  @override
  bool isShipmentBusy(int? shipmentId) => _busy.contains(shipmentId);

  Future<ShipmentActionResult> _run(
    int? id,
    ShipmentActionResult Function(int id) step,
  ) async {
    if (id == null || _busy.contains(id)) {
      return const ShipmentActionResult(
        success: false,
        code: 'REQUEST_IN_PROGRESS',
        message: 'Shipment request is already in progress',
      );
    }
    _busy.add(id);
    notifyListeners();
    if (gate != null) await gate!.future;
    await Future<void>.delayed(Duration.zero);
    final result = step(id);
    _busy.remove(id);
    notifyListeners();
    return result;
  }

  @override
  Future<ShipmentActionResult> markArrivedAtStore(
    int? shipmentId, {
    String languageCode = 'en',
  }) => _run(shipmentId, server.arrive);

  @override
  Future<ShipmentActionResult> pickupShipmentFromStore(
    int? shipmentId, {
    String languageCode = 'en',
  }) => _run(shipmentId, server.pickUp);

  @override
  Future<ShipmentActionResult> deliverShipment(
    int? shipmentId, {
    String languageCode = 'en',
  }) => _run(shipmentId, server.deliver);

  @override
  Future<void> getShipmentsInstant({bool force = false, int? page}) async {
    refreshes++;
    notifyListeners();
  }

  /// The driver's own open instant job, as `active_instant`.
  @override
  Shipment? get activeInstantShipment {
    for (final entry in server.rows.entries) {
      final row = entry.value;
      if (row.driver == _me &&
          row.type == 1 &&
          !isFinalShipmentStatus(row.status)) {
        return server.shipment(entry.key);
      }
    }
    return null;
  }

  /// The available list: unclaimed offers and the driver's own non-instant
  /// accepted jobs (an accepted instant job is pinned instead).
  @override
  List<Shipment> get paginatedShipments => [
    for (final entry in server.rows.entries)
      if (!isFinalShipmentStatus(entry.value.status) &&
          entry.value.type != 2 &&
          (entry.value.driver == 0 ||
              (entry.value.driver == _me && entry.value.type != 1)))
        server.shipment(entry.key),
  ];

  /// As in production: the active instant job plus the available page —
  /// never the driver's scheduled shipments.
  @override
  List<Shipment> get allShipments => [
    if (activeInstantShipment != null) activeInstantShipment!,
    ...paginatedShipments,
  ];

  @override
  bool get hasLoaded => true;

  @override
  int get totalCount => paginatedShipments.length;

  @override
  int get totalPages => 1;

  @override
  int get currentPage => 1;
}

class _StubAssigned extends ShipmentProvider {
  _StubAssigned(this.server);

  final _Server server;
  int refreshes = 0;

  /// Shipments on a page of the assigned list that is not loaded.
  final Set<int> offPage = {};

  @override
  List<Shipment> get paginatedShipments => [
    for (final shipment in server.mine())
      if (!offPage.contains(shipment.id)) shipment,
  ];

  @override
  bool get hasLoaded => true;

  @override
  Future<void> getAllShipments({bool force = false, int? page}) async {
    refreshes++;
    notifyListeners();
  }
}

class _StubHome extends HomeProvider {
  int statisticsRefreshes = 0;

  /// Asynchronous like the real request: the filter card calls it from
  /// initState, where a synchronous notify would land mid-build.
  @override
  Future<void> getOrderStatus({bool force = false}) async {
    await Future<void>.delayed(Duration.zero);
    orderStatusData = OrderStatusData.fromJson({
      'success': true,
      'count': 11,
      'status': [
        for (var id = 1; id <= 11; id++)
          <String, dynamic>{
            'id': '$id',
            'status_name_en': '',
            'status_name_ar': '',
          },
      ],
    });
    notifyListeners();
  }

  @override
  Future<void> getDriverStatistics(
    BuildContext context, {
    bool force = false,
  }) async {
    statisticsRefreshes++;
  }
}

class _StubLocation extends OrderLocationProvider {
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
    isLoading = false;
    notifyListeners();
  }

  // allowLegacyFallback: present on newer providers; an extra optional
  // parameter keeps this override valid on either signature.
  @override
  Future<void> startDriverLocationUpdates({
    BuildContext? context,
    bool allowLegacyFallback = false,
  }) async {}

  @override
  void stopDriverLocationUpdates({bool notify = true}) {}
}

class _StubProfile extends ProfileProvider {
  @override
  Future<DriverInfo?> fetchDriverProfile() async => profileInfo;
}

class _StubNotifications extends NotificationProvider {
  @override
  Future<void> refreshUnreadCount({bool force = false}) async {}
}

class _StubFlowConfig extends ShipmentFlowConfigProvider {
  @override
  Future<void> fetch({bool force = false}) async {}
}

// -----------------------------------------------------------------------------
// Harness
// -----------------------------------------------------------------------------

class _Hosts {
  _Hosts(this.server)
    : instant = _StubInstant(server),
      assigned = _StubAssigned(server),
      home = _StubHome(),
      location = _StubLocation();

  final _Server server;
  final _StubInstant instant;
  final _StubAssigned assigned;
  final _StubHome home;
  final _StubLocation location;
}

Future<void> _settle(WidgetTester tester, {int frames = 16}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<void> _pumpPage(
  WidgetTester tester,
  _Hosts hosts,
  Widget page, {
  Locale locale = const Locale('en'),
  double width = 390,
}) async {
  tester.view.physicalSize = Size(width * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<DriverActionService>(
          create:
              (_) => DriverActionService(
                loader:
                    (id) async =>
                        hosts.assigned.server.rows.containsKey(id) &&
                                hosts.assigned.server.rows[id]!.driver == _me
                            ? hosts.assigned.server.shipment(id)
                            : null,
              ),
        ),
        ChangeNotifierProvider<ShipmentProvider>.value(value: hosts.assigned),
        ChangeNotifierProvider<ShipmentInstantprovider>.value(
          value: hosts.instant,
        ),
        ChangeNotifierProvider<HomeProvider>.value(value: hosts.home),
        ChangeNotifierProvider<OrderLocationProvider>.value(
          value: hosts.location,
        ),
        ChangeNotifierProvider<LocaleProvider>(
          create: (_) => LocaleProvider(loadSaved: false),
        ),
        ChangeNotifierProvider<ProfileProvider>(
          create:
              (_) =>
                  _StubProfile()
                    ..profileInfo = DriverInfo(
                      id: _me,
                      dname: 'QA Driver',
                      dpercent: 0,
                      dphone: '0790000101',
                      img: '',
                      numcd: '',
                      latitude: '',
                      longitude: '',
                      subscription: 1,
                      status: 0,
                      createdAt: '2026-01-01',
                    ),
        ),
        ChangeNotifierProvider<ShipmentFlowConfigProvider>(
          create: (_) => _StubFlowConfig(),
        ),
        ChangeNotifierProvider<NotificationProvider>(
          create: (_) => _StubNotifications(),
        ),
        ChangeNotifierProvider(create: (_) => BottomNavProvider()),
        ChangeNotifierProvider<DriverChatConversationsProvider>(
          create:
              (_) => DriverChatConversationsProvider(
                repository: DriverChatService(),
              ),
        ),
      ],
      child: MaterialApp(
        navigatorKey: Nav.key,
        theme: ThemeData(fontFamily: AppFonts.currentFontFamily),
        locale: locale,
        supportedLocales: const [Locale('en'), Locale('ar')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        // A fresh State for every pump, so a loop over statuses never reads
        // the previous shipment.
        home: Scaffold(body: KeyedSubtree(key: UniqueKey(), child: page)),
      ),
    ),
  );
  await _settle(tester);
}

/// Lets the details screen's real status read (OrderStatusProvider) answer:
/// it goes through real I/O, which only completes outside the fake clock.
Future<void> _drain(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 60)),
  );
  await _settle(tester);
}

/// The tracking screen and the lists build lazily; bring [finder] on screen.
Future<void> _reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    220,
    scrollable: find.byType(Scrollable).first,
    maxScrolls: 60,
  );
  await _settle(tester);
}

Widget _details(_Server server, int id) => OrderDetailPage(
  shipmentId: id,
  shipment: server.shipment(id),
  phoneCustomer: '0791234567',
  allowChatEntry: false,
);

/// The tracking screen opened plainly, the way a scheduled shipment reaches
/// it: no instant flags and no store location handed in.
Widget _tracking(_Server server, int id) => LocationOrderPage(
  shipmentId: id,
  phoneCustomer: '0791234567',
  shipment: server.shipment(id),
  storeName: 'Demo Store',
  customerName: 'Ahmad Saleh',
  customerAddress: 'Amman, Jordan',
);

const _arrive = ValueKey('arrive_action');
const _pickup = ValueKey('pickup_action');
const _deliver = ValueKey('deliver_action');
const _updateStatus = ValueKey('update_status_action');
const _hint = ValueKey('next_step_hint');

/// [drain] is off on the tracking screen: it needs no real I/O, and its map
/// platform view cannot be created outside the fake clock.
Future<void> _tap(
  WidgetTester tester,
  Finder finder, {
  bool drain = true,
}) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await _settle(tester);
  if (drain) await _drain(tester);
}

Future<void> _confirm(
  WidgetTester tester,
  String label, {
  bool drain = true,
}) async {
  await tester.tap(find.widgetWithText(ElevatedButton, label).last);
  await _settle(tester);
  if (drain) await _drain(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store =
        _FakeSecureStore()
          ..values['driver_api_key'] = 'qa-key'
          ..values['driver_session_id'] = '$_me';
    AuthService.configureForTesting(secureStore: store);
    AppLocalizations.applyLocale(const Locale('en'));
  });

  tearDown(AuthService.resetForTesting);

  // ---------------------------------------------------------------------------
  group('resolver mirrors the server contract', () {
    const arrivalFrom = {1, 2, 3};
    const pickupFrom = {2, 10};
    const deliverFrom = {4};

    test('R1. each open status offers exactly the steps the server takes', () {
      final expected = <int, List<DriverShipmentStep?>>{
        1: [DriverShipmentStep.arriveAtStore, null],
        2: [DriverShipmentStep.arriveAtStore, DriverShipmentStep.pickUp],
        3: [DriverShipmentStep.arriveAtStore, null],
        4: [DriverShipmentStep.deliver, null],
        5: [null, null],
        10: [DriverShipmentStep.pickUp, null],
      };
      for (final entry in expected.entries) {
        final actions = driverShipmentActionsFor(
          statusId: entry.key,
          driverId: _me,
          shipment: _authorizedFixture(entry.key, _me),
        );
        expect(actions.primary, entry.value[0], reason: 'status ${entry.key}');
        expect(
          actions.secondary,
          entry.value[1],
          reason: 'status ${entry.key}',
        );
        expect(actions.canReportException, isTrue);
      }
      expect(
        driverShipmentActionsFor(
          statusId: 5,
          driverId: _me,
          shipment: _authorizedFixture(5, _me),
        ).block,
        DriverStepBlock.dispatchControlled,
      );
    });

    test('R2. the delivery type plays no part', () {
      // Only status and driver are inputs, so a scheduled shipment gets the
      // same steps as an instant one.
      for (final type in [1, 2, 3, 6]) {
        final server = _Server()..add(1, status: 2, type: type);
        final actions = driverShipmentActionsForShipment(server.shipment(1));
        expect(actions.primary, DriverShipmentStep.arriveAtStore);
        expect(actions.secondary, DriverShipmentStep.pickUp);
      }
    });

    test('R3. closed and unclaimed shipments offer nothing', () {
      for (final status in [6, 7, 8, 11]) {
        final actions = driverShipmentActionsFor(
          statusId: status,
          driverId: _me,
          shipment: _authorizedFixture(status, _me),
        );
        expect(actions.primary, isNull);
        expect(actions.canReportException, isFalse);
        expect(actions.block, DriverStepBlock.closed);
      }
      final offer = driverShipmentActionsFor(
        statusId: 1,
        driverId: 0,
        shipment: _authorizedFixture(1, 0),
      );
      expect(offer.primary, isNull);
      expect(offer.canReportException, isFalse);
      expect(offer.block, DriverStepBlock.notAccepted);
    });

    test('R4. no status ever offers a step the server refuses', () {
      for (var status = 0; status <= 12; status++) {
        final actions = driverShipmentActionsFor(
          statusId: status,
          driverId: _me,
          shipment: _authorizedFixture(status, _me),
        );
        for (final step in [actions.primary, actions.secondary]) {
          if (step == null) continue;
          final accepted = switch (step) {
            DriverShipmentStep.arriveAtStore => arrivalFrom,
            DriverShipmentStep.pickUp => pickupFrom,
            DriverShipmentStep.deliver => deliverFrom,
          };
          expect(accepted.contains(status), isTrue, reason: '$step @ $status');
        }
      }
    });
  });

  // ---------------------------------------------------------------------------
  group('details screen', () {
    testWidgets(
      'D1. a scheduled shipment shows its step for every open status',
      (tester) async {
        final cases = <int, List<ValueKey<String>>>{
          1: [_arrive],
          2: [_arrive, _pickup],
          3: [_arrive],
          10: [_pickup],
          4: [_deliver],
          5: [],
        };
        for (final entry in cases.entries) {
          final server = _Server()..add(7001, status: entry.key);
          await _pumpPage(tester, _Hosts(server), _details(server, 7001));
          for (final key in [_arrive, _pickup, _deliver]) {
            expect(
              find.byKey(key),
              entry.value.contains(key) ? findsOneWidget : findsNothing,
              reason: 'status ${entry.key}, $key',
            );
          }
          // The off-ramps stay available, and the next step is explained.
          expect(find.byKey(_updateStatus), findsOneWidget);
          expect(find.byKey(_hint), findsOneWidget);
        }
      },
    );

    testWidgets('D2. status 5 explains why nothing moves it forward', (
      tester,
    ) async {
      final server = _Server()..add(7001, status: 5);
      await _pumpPage(tester, _Hosts(server), _details(server, 7001));
      expect(find.textContaining('dispatch controls this status'), findsOne);
    });

    testWidgets(
      'D3. scheduled normal flow: arrive -> pick up -> deliver, one request each',
      (tester) async {
        final server = _Server()..add(7001, status: 2);
        final hosts = _Hosts(server);
        await _pumpPage(tester, hosts, _details(server, 7001));

        await _tap(tester, find.byKey(_arrive));
        expect(server.rows[7001]!.status, 10);
        expect(find.text('Arrival at the store was confirmed'), findsOneWidget);
        expect(find.byKey(_arrive), findsNothing);
        expect(find.byKey(_pickup), findsOneWidget);

        // From 10 the pickup is the normal next step: no extra question.
        await _tap(tester, find.byKey(_pickup));
        expect(server.rows[7001]!.status, 4);
        expect(find.byKey(_deliver), findsOneWidget);

        await _tap(tester, find.byKey(_deliver));
        expect(find.text('Mark as Delivered?'), findsOneWidget);
        await _confirm(tester, 'Mark as Delivered');
        expect(server.rows[7001]!.status, 11);
        expect(find.byKey(_deliver), findsNothing);
        expect(find.byKey(_updateStatus), findsNothing);
        expect(hosts.home.statisticsRefreshes, 1);

        expect(server.calls, ['arrive:7001', 'pickup:7001', 'deliver:7001']);
      },
    );

    testWidgets('D4. instant normal flow from an accepted shipment', (
      tester,
    ) async {
      final server = _Server()..add(7002, status: 2, type: 1);
      await _pumpPage(tester, _Hosts(server), _details(server, 7002));

      await _tap(tester, find.byKey(_arrive));
      await _tap(tester, find.byKey(_pickup));
      await _tap(tester, find.byKey(_deliver));
      await _confirm(tester, 'Mark as Delivered');

      expect(server.rows[7002]!.status, 11);
      expect(server.calls, ['arrive:7002', 'pickup:7002', 'deliver:7002']);
    });

    testWidgets('D5. a direct pickup from 2 asks first; cancel sends nothing', (
      tester,
    ) async {
      final server = _Server()..add(7001, status: 2);
      await _pumpPage(tester, _Hosts(server), _details(server, 7001));

      await _tap(tester, find.byKey(_pickup));
      expect(find.text('Confirm pickup?'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await _settle(tester);
      expect(server.calls, isEmpty);

      await _tap(tester, find.byKey(_pickup));
      await _confirm(tester, 'Confirm pickup');
      expect(server.calls, ['pickup:7001']);
      expect(server.rows[7001]!.status, 4);
      expect(find.byKey(_deliver), findsOneWidget);
    });

    testWidgets(
      'D6. a refused arrival re-reads the shipment and shows the server state',
      (tester) async {
        final server = _Server()..add(7001, status: 2);
        final hosts = _Hosts(server);
        await _pumpPage(tester, hosts, _details(server, 7001));
        // Dispatch cancelled it while the screen was open.
        server.rows[7001]!.status = 7;

        await _tap(tester, find.byKey(_arrive));
        expect(server.calls, ['arrive:7001']);
        expect(
          find.text('Arrival at the store can no longer be confirmed'),
          findsOneWidget,
        );
        expect(hosts.instant.refreshes, greaterThanOrEqualTo(1));
        expect(find.byKey(_arrive), findsNothing);
        expect(find.byKey(_updateStatus), findsNothing);
      },
    );

    testWidgets(
      "D7. another driver's shipment: the server refuses, nothing advances",
      (tester) async {
        final server = _Server()..add(7001, status: 4);
        final hosts = _Hosts(server);
        await _pumpPage(tester, hosts, _details(server, 7001));
        server.rows[7001]!.driver = _otherDriver;

        await _tap(tester, find.byKey(_deliver));
        await _confirm(tester, 'Mark as Delivered');
        expect(server.calls, ['deliver:7001']);
        expect(server.rows[7001]!.status, 4);
        expect(
          find.text('You are not assigned to this shipment.'),
          findsOneWidget,
        );
        expect(hosts.instant.refreshes, greaterThanOrEqualTo(1));
      },
    );

    testWidgets('D8. a double tap sends one arrival; the button waits', (
      tester,
    ) async {
      final server = _Server()..add(7001, status: 1);
      final hosts = _Hosts(server)..instant.gate = Completer<void>();
      await _pumpPage(tester, hosts, _details(server, 7001));

      await tester.ensureVisible(find.byKey(_arrive));
      await tester.tap(find.byKey(_arrive));
      await _settle(tester, frames: 4);
      final button = tester.widget<ElevatedButton>(
        find.descendant(
          of: find.byKey(_arrive),
          matching: find.byWidgetPredicate((w) => w is ElevatedButton),
        ),
      );
      expect(button.onPressed, isNull);
      await tester.tap(find.byKey(_arrive), warnIfMissed: false);
      await _settle(tester, frames: 4);

      hosts.instant.gate!.complete();
      await _settle(tester);
      expect(server.calls, ['arrive:7001']);
    });

    testWidgets('D9. Arabic labels, hint and right-to-left layout', (
      tester,
    ) async {
      AppLocalizations.applyLocale(const Locale('ar'));
      final server = _Server()..add(7001, status: 2);
      await _pumpPage(
        tester,
        _Hosts(server),
        _details(server, 7001),
        locale: const Locale('ar'),
      );
      expect(
        find.descendant(
          of: find.byKey(_arrive),
          matching: find.text('وصلت إلى المتجر'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(_pickup),
          matching: find.text('استلام الشحنة'),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('الخطوة التالية'), findsOneWidget);
      expect(
        Directionality.of(tester.element(find.byKey(_arrive))),
        TextDirection.rtl,
      );
    });

    testWidgets(
      'D14. the pre-pickup details sheet retains exceptions but not delivery',
      (tester) async {
        final server = _Server()..add(7015, status: 10);
        await _pumpPage(tester, _Hosts(server), _details(server, 7015));

        await _tap(tester, find.byKey(_updateStatus));

        expect(find.byType(ShipmentStatusUpdateSheet), findsOneWidget);
        expect(
          find.byKey(const ValueKey('lifecycle_status_7')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('lifecycle_status_11')), findsNothing);
      },
    );
  });

  // ---------------------------------------------------------------------------
  group('details screen — review follow-ups', () {
    testWidgets(
      'D10. a shipment on no loaded list page keeps each confirmed step',
      (tester) async {
        // A later page of the assigned list, or a screen opened from a
        // notification: the lists do not hold the shipment.
        final server = _Server()..add(7010, status: 1);
        final hosts = _Hosts(server)..assigned.offPage.add(7010);
        await _pumpPage(tester, hosts, _details(server, 7010));

        await _tap(tester, find.byKey(_arrive));
        expect(server.rows[7010]!.status, 10);
        expect(find.byKey(_arrive), findsNothing);
        expect(find.byKey(_pickup), findsOneWidget);

        await _tap(tester, find.byKey(_pickup));
        expect(server.rows[7010]!.status, 4);
        expect(find.byKey(_deliver), findsOneWidget);

        await _tap(tester, find.byKey(_deliver));
        await _confirm(tester, 'Mark as Delivered');
        expect(server.rows[7010]!.status, 11);
        expect(find.byKey(_deliver), findsNothing);
        expect(server.calls, ['arrive:7010', 'pickup:7010', 'deliver:7010']);
      },
    );

    testWidgets('D11. a shipment taken from the driver withdraws every step', (
      tester,
    ) async {
      final server = _Server()..add(7011, status: 4);
      await _pumpPage(tester, _Hosts(server), _details(server, 7011));
      server.rows[7011]!.driver = _otherDriver;

      await _tap(tester, find.byKey(_deliver));
      await _confirm(tester, 'Mark as Delivered');
      expect(server.calls, ['deliver:7011']);
      expect(
        find.text('This shipment is no longer assigned to you.'),
        findsOneWidget,
      );
      expect(find.byKey(_deliver), findsNothing);
      expect(find.byKey(_updateStatus), findsNothing);
    });

    testWidgets('D12. returning from tracking shows what was done there', (
      tester,
    ) async {
      final server = _Server()..add(7012, status: 4, type: 1);
      await _pumpPage(tester, _Hosts(server), _details(server, 7012));
      expect(find.byKey(_deliver), findsOneWidget);

      // No drain while the tracking screen (and its map) is up.
      final track = find.ancestor(
        of: find.text('Track Shipment'),
        matching: find.byWidgetPredicate((w) => w is ElevatedButton),
      );
      await _tap(tester, track, drain: false);
      // Let the route transition finish, so the search runs on tracking.
      await _settle(tester, frames: 40);
      expect(find.byType(LocationOrderPage), findsOneWidget);
      await _reveal(tester, find.byKey(_deliver));
      await _tap(tester, find.byKey(_deliver), drain: false);
      await _confirm(tester, 'Mark as Delivered', drain: false);
      expect(server.rows[7012]!.status, 11);

      Nav.key.currentState!.pop();
      await _settle(tester);
      expect(find.byKey(_deliver), findsNothing);
      expect(find.byKey(_updateStatus), findsNothing);
    });

    testWidgets(
      'D13. a scheduled shipment at 10 is a pickup stage, not delivered',
      (tester) async {
        final server = _Server()..add(7013, status: 10);
        await _pumpPage(tester, _Hosts(server), _details(server, 7013));
        expect(find.text('Pick up from store'), findsOneWidget);
        expect(find.text('Delivery stage'), findsNothing);
      },
    );
  });

  // ---------------------------------------------------------------------------
  group('tracking screen', () {
    testWidgets('T1. in transit (4) offers Delivered and completes it', (
      tester,
    ) async {
      final server = _Server()..add(7003, status: 4, type: 1);
      final hosts = _Hosts(server);
      await _pumpPage(tester, hosts, _tracking(server, 7003));

      await _reveal(tester, find.byKey(_deliver));
      expect(find.byKey(_deliver), findsOneWidget);
      await _tap(tester, find.byKey(_deliver), drain: false);
      expect(find.text('Mark as Delivered?'), findsOneWidget);
      await _confirm(tester, 'Mark as Delivered', drain: false);

      expect(server.calls, ['deliver:7003']);
      expect(server.rows[7003]!.status, 11);
      expect(find.byKey(_deliver), findsNothing);
      expect(hosts.assigned.refreshes, greaterThanOrEqualTo(1));
      expect(hosts.home.statisticsRefreshes, 1);
    });

    testWidgets('T2. a scheduled shipment gets arrival and pickup here too', (
      tester,
    ) async {
      final server =
          _Server()
            ..add(7004, status: 2)
            ..add(7005, status: 3);
      await _pumpPage(tester, _Hosts(server), _tracking(server, 7004));
      await _reveal(tester, find.byKey(_pickup));
      expect(find.byKey(_arrive), findsOneWidget);
      expect(find.byKey(_pickup), findsOneWidget);

      await _pumpPage(tester, _Hosts(server), _tracking(server, 7005));
      await _reveal(tester, find.text('Open Maps'));
      expect(find.byKey(_arrive), findsOneWidget);
      expect(find.byKey(_pickup), findsNothing);
    });

    testWidgets('T3. a refused delivery adopts the server status', (
      tester,
    ) async {
      final server = _Server()..add(7003, status: 4, type: 1);
      final hosts = _Hosts(server);
      await _pumpPage(tester, hosts, _tracking(server, 7003));
      server.rows[7003]!.status = 8;

      await _reveal(tester, find.byKey(_deliver));
      await _tap(tester, find.byKey(_deliver), drain: false);
      await _confirm(tester, 'Mark as Delivered', drain: false);
      expect(
        find.text('Shipment must be in transit before it can be completed.'),
        findsOneWidget,
      );
      expect(find.byKey(_deliver), findsNothing);
    });
  });

  group('tracking screen — review follow-ups', () {
    testWidgets(
      "T4. an arrival refused as another driver's (403) withdraws the steps",
      (tester) async {
        final server = _Server()..add(7014, status: 2);
        await _pumpPage(tester, _Hosts(server), _tracking(server, 7014));
        server.rows[7014]!.driver = _otherDriver;

        await _reveal(tester, find.byKey(_arrive));
        await _tap(tester, find.byKey(_arrive), drain: false);
        expect(server.calls, ['arrive:7014']);
        expect(
          find.text('This shipment is no longer assigned to you.'),
          findsOneWidget,
        );
        expect(find.byKey(_arrive), findsNothing);
        expect(find.byKey(_pickup), findsNothing);
        expect(find.text('Update Status'), findsNothing);
      },
    );
  });

  // ---------------------------------------------------------------------------
  group('assigned list', () {
    testWidgets('L1. every card offers its own next step', (tester) async {
      final cases = <int, ValueKey<String>?>{
        1: _arrive,
        2: _arrive,
        3: _arrive,
        10: _pickup,
        4: _deliver,
        5: null,
        11: null,
      };
      for (final entry in cases.entries) {
        final server = _Server()..add(8000 + entry.key, status: entry.key);
        await _pumpPage(tester, _Hosts(server), const TableAllShipment());
        final launcherIsVisible = const <int>{10, 4, 5}.contains(entry.key);
        expect(
          find.byTooltip('Update status'),
          launcherIsVisible ? findsOneWidget : findsNothing,
          reason: 'status ${entry.key}',
        );
        if (launcherIsVisible) {
          await _reveal(tester, find.byTooltip('Update status'));
        }
        for (final key in [_arrive, _pickup, _deliver]) {
          expect(
            find.byKey(key),
            key == entry.value ? findsOneWidget : findsNothing,
            reason: 'status ${entry.key}, $key',
          );
        }
      }
    });

    testWidgets('L2. Delivered from the card asks, sends once, re-reads', (
      tester,
    ) async {
      final server = _Server()..add(8003, status: 4);
      final hosts = _Hosts(server);
      await _pumpPage(tester, hosts, const TableAllShipment());

      await _tap(tester, find.byKey(_deliver));
      expect(find.text('Mark as Delivered?'), findsOneWidget);
      await _confirm(tester, 'Mark as Delivered');

      expect(server.calls, ['deliver:8003']);
      expect(hosts.assigned.refreshes, greaterThanOrEqualTo(1));
      expect(hosts.home.statisticsRefreshes, 1);
      // The re-read list holds the server's state: closed, nothing to offer.
      expect(find.byKey(_deliver), findsNothing);
    });

    testWidgets('L3. a refused step still re-reads the list', (tester) async {
      final server = _Server()..add(8002, status: 10);
      final hosts = _Hosts(server);
      await _pumpPage(tester, hosts, const TableAllShipment());
      server.rows[8002]!.status = 7;

      await _tap(tester, find.byKey(_pickup));
      expect(server.calls, ['pickup:8002']);
      expect(hosts.assigned.refreshes, greaterThanOrEqualTo(1));
      expect(find.byKey(_pickup), findsNothing);
    });

    testWidgets(
      'L4. the pre-pickup list sheet retains exceptions but withholds delivery',
      (tester) async {
        final server = _Server()..add(8010, status: 10);
        await _pumpPage(tester, _Hosts(server), const TableAllShipment());

        await _reveal(tester, find.byTooltip('Update status'));
        await _tap(tester, find.byTooltip('Update status'));

        expect(find.byType(ShipmentStatusUpdateSheet), findsOneWidget);
        expect(
          find.byKey(const ValueKey('lifecycle_status_7')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('lifecycle_status_11')), findsNothing);
      },
    );

    testWidgets('L5. the post-pickup list sheet enables delivery', (
      tester,
    ) async {
      final server = _Server()..add(8011, status: 4);
      await _pumpPage(tester, _Hosts(server), const TableAllShipment());

      await _reveal(tester, find.byTooltip('Update status'));
      await _tap(tester, find.byTooltip('Update status'));

      expect(find.byType(ShipmentStatusUpdateSheet), findsOneWidget);
      expect(find.byKey(const ValueKey('lifecycle_status_11')), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  group('available tab', () {
    testWidgets('A1. the active instant card carries the next step', (
      tester,
    ) async {
      final server = _Server()..add(9001, status: 2, type: 1);
      final hosts = _Hosts(server);
      await _pumpPage(tester, hosts, const ShipmentInstantPage());

      expect(find.byKey(_arrive), findsOneWidget);
      expect(find.text('Update Status'), findsNothing);
      await _tap(tester, find.byKey(_arrive));
      expect(server.rows[9001]!.status, 10);
      expect(find.byKey(_pickup), findsOneWidget);
      expect(find.text('Update Status'), findsOneWidget);

      await _tap(tester, find.byKey(_pickup));
      expect(server.rows[9001]!.status, 4);
      expect(find.byKey(_deliver), findsOneWidget);
      expect(find.text('Track Shipment'), findsOneWidget);

      await _tap(tester, find.byKey(_deliver));
      await _confirm(tester, 'Mark as Delivered');
      expect(server.rows[9001]!.status, 11);
      expect(server.calls, ['arrive:9001', 'pickup:9001', 'deliver:9001']);
    });

    testWidgets('A2. an accepted non-instant job in transit offers Delivered', (
      tester,
    ) async {
      final server = _Server()..add(9002, status: 4, type: 6);
      await _pumpPage(tester, _Hosts(server), const ShipmentInstantPage());
      expect(find.byKey(_deliver), findsOneWidget);
      expect(find.text('View Details'), findsOneWidget);
      expect(find.text('Track Shipment'), findsOneWidget);
    });

    testWidgets(
      'A4. the active card offers the direct pickup from 2, asked first',
      (tester) async {
        final server = _Server()..add(9004, status: 2, type: 1);
        await _pumpPage(tester, _Hosts(server), const ShipmentInstantPage());
        expect(find.byKey(_arrive), findsOneWidget);
        expect(find.byKey(_pickup), findsOneWidget);

        await _tap(tester, find.byKey(_pickup));
        expect(find.text('Confirm pickup?'), findsOneWidget);
        await _confirm(tester, 'Confirm pickup');
        expect(server.calls, ['pickup:9004']);
        expect(server.rows[9004]!.status, 4);
        expect(find.byKey(_deliver), findsOneWidget);
      },
    );

    testWidgets(
      'A5. a post-pickup dispatch state keeps only its exception actions',
      (tester) async {
        final server = _Server()..add(9005, status: 5, type: 1);
        await _pumpPage(tester, _Hosts(server), const ShipmentInstantPage());
        expect(
          find.textContaining('open tracking to report a problem'),
          findsOneWidget,
        );

        // Active instant work uses the pinned card's full-width button; the
        // square tooltip belongs to ordinary list cards.
        await _tap(tester, find.text('Update Status'));
        expect(
          find.byKey(const ValueKey('lifecycle_status_7')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('lifecycle_status_11')), findsNothing);
      },
    );

    testWidgets('A7. an instant offer exposes Accept, not a status sheet', (
      tester,
    ) async {
      final server = _Server()..add(9007, status: 1, driver: 0, type: 1);
      await _pumpPage(tester, _Hosts(server), const ShipmentInstantPage());

      expect(find.text('Accept Shipment'), findsOneWidget);
      expect(find.byTooltip('Update status'), findsNothing);
      expect(find.byKey(_deliver), findsNothing);
    });

    testWidgets(
      'A6. Delivered on the card is full width and readable at 360dp',
      (tester) async {
        final server = _Server()..add(9006, status: 4, type: 6);
        await _pumpPage(
          tester,
          _Hosts(server),
          const ShipmentInstantPage(),
          width: 360,
        );
        await _reveal(tester, find.byKey(_deliver));
        // Its own row: the card's full inner width (292 at 360dp). Beside the
        // three square actions it had about 136. Glyph widths are not checked:
        // the test font draws every character a full em wide.
        expect(tester.getSize(find.byKey(_deliver)).width, greaterThan(280));
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'A3. Update status retains the shared sheet and loads lifecycle actions',
      (tester) async {
        final server = _Server()..add(9002, status: 4, type: 6);
        await _pumpPage(tester, _Hosts(server), const ShipmentInstantPage());

        await _tap(tester, find.byTooltip('Update status'));
        expect(find.byType(ShipmentStatusUpdateSheet), findsOneWidget);
        final sheet = tester.widget<ShipmentStatusUpdateSheet>(
          find.byType(ShipmentStatusUpdateSheet),
        );
        expect(sheet.statuses.map((s) => s.id).toSet(), {'7', '8', '9'});
      },
    );
  });

  // ---------------------------------------------------------------------------
  group('filter results card', () {
    testWidgets('F1. its status button retains the shared lifecycle sheet', (
      tester,
    ) async {
      // Wide surface: the card's header row (unchanged here) overflows at
      // phone width under the test font, which draws every glyph a full em.
      SizeConfig().init(
        const BoxConstraints(maxWidth: 800, maxHeight: 844),
        Orientation.portrait,
      );
      final server = _Server()..add(9101, status: 4);
      await _pumpPage(
        tester,
        _Hosts(server),
        const SingleChildScrollView(
          child: OrderTile(
            orderId: 'QA-9101',
            orderIdInt: 9101,
            currentStatusId: 4,
            statusNameEn: 'In Transit',
            statusNameAr: 'في الطريق',
            username: 'Ahmad Saleh',
            dphno: '0791234567',
            locationStore: LatLng(31.95, 35.91),
          ),
        ),
        width: 800,
      );

      // tr() without the asset loader answers with the key itself.
      final button = find.text('update_order_status');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await _settle(tester);

      expect(find.byType(ShipmentStatusUpdateSheet), findsOneWidget);
      final sheet = tester.widget<ShipmentStatusUpdateSheet>(
        find.byType(ShipmentStatusUpdateSheet),
      );
      expect(sheet.statuses.map((s) => s.id).toSet(), {'7', '8', '9'});
      expect(sheet.currentStatusId, 4);
    });
  });
}
