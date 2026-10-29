// B2 (release blocker RG-11): the "Delivered" (تم التسليم) button on the
// Driver shipment details screen.
//
// Real page, real widgets; the provider's network call is replaced by a stub
// that answers like complete_shipment_driver.php (see
// b2_delivered_contract_test.dart for the request itself), and the list
// providers are stubs whose rows play the role of the server after a refresh.

import 'dart:async';

import 'package:blockatie/constants/fonts.dart';
import 'package:blockatie/models/shipment.dart';
import 'package:blockatie/provider/bottom_nav.dart';
import 'package:blockatie/provider/chat/driver_chat_conversations_provider.dart';
import 'package:blockatie/provider/home.dart';
import 'package:blockatie/provider/localization.dart';
import 'package:blockatie/provider/order_location.dart';
import 'package:blockatie/provider/shipment.dart';
import 'package:blockatie/provider/shipment_instsnt.dart';
import 'package:blockatie/services/auth_secure_store.dart';
import 'package:blockatie/services/auth_services.dart';
import 'package:blockatie/services/driver_chat_service.dart';
import 'package:blockatie/utils/localization.dart';
import 'package:blockatie/utils/nav.dart';
import 'package:blockatie/views/pages/orders/order_details.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  int refreshes = 0;

  @override
  Future<void> getAllShipments({bool force = false, int? page}) async {
    refreshes++;
  }
}

/// Answers deliverShipment with [reply]; `rowsAfterRefresh` is what the
/// server's list holds once the page re-reads it.
class _StubInstantProvider extends ShipmentInstantprovider {
  _StubInstantProvider(this._rows);

  List<Shipment> _rows;
  List<Shipment>? rowsAfterRefresh;
  ShipmentActionResult reply = const ShipmentActionResult(
    success: true,
    code: 'SHIPMENT_COMPLETED',
    httpStatus: 200,
    message: 'Shipment has been marked as delivered successfully.',
  );
  Completer<void>? gate;
  int deliveries = 0;
  int refreshes = 0;
  final List<String> languages = [];

  @override
  List<Shipment> get allShipments => _rows;

  @override
  List<Shipment> get paginatedShipments => const [];

  @override
  Future<void> getShipmentsInstant({bool force = false, int? page}) async {
    refreshes++;
    if (rowsAfterRefresh != null) _rows = rowsAfterRefresh!;
  }

  @override
  Future<ShipmentActionResult> deliverShipment(
    int? shipmentId, {
    String languageCode = 'en',
  }) async {
    deliveries++;
    languages.add(languageCode);
    if (gate != null) await gate!.future;
    await Future<void>.delayed(Duration.zero);
    return reply;
  }
}

class _StubHomeProvider extends HomeProvider {
  int statisticsRefreshes = 0;

  @override
  Future<void> getOrderStatus({bool force = false}) async {}

  @override
  Future<void> getDriverStatistics(
    BuildContext context, {
    bool force = false,
  }) async {
    statisticsRefreshes++;
  }
}

class _StubOrderLocationProvider extends OrderLocationProvider {
  @override
  Future<void> getShipmentCords(int shipmentId) async {}
}

Shipment _shipment({
  int statusId = 4,
  int driverId = 601,
  int deliveryTypeId = 1,
  double cod = 12.5,
}) {
  return Shipment.fromJson({
    'id': 7001,
    'shipment_date': '2026-01-15 10:30:00',
    'created_at': '2026-01-15 10:30:00',
    'policy_num': 'BLK-7001',
    'recipient_name': 'Ahmad Saleh',
    'recipient_phone': '0791234567',
    'delivery_address': 'Amman, Jordan',
    'shipment_cost': cod,
    'delivery_cost': 2,
    'shipment_status_id': statusId,
    'shipment_status': statusId,
    'status_name_en': '',
    'status_name_ar': '',
    'nstore': 'Demo Store',
    'lclient': 'Store Street 1',
    'phclient': '0788888888',
    'driver_id': driverId,
    'delivery_type_id': deliveryTypeId,
  });
}

class _Hosts {
  _Hosts(Shipment shipment)
    : instant = _StubInstantProvider([shipment]),
      assigned = _StubShipmentProvider(),
      home = _StubHomeProvider();

  final _StubInstantProvider instant;
  final _StubShipmentProvider assigned;
  final _StubHomeProvider home;
}

Future<void> _settle(WidgetTester tester, {int frames = 16}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<void> _pump(
  WidgetTester tester,
  _Hosts hosts,
  Shipment shipment, {
  Locale locale = const Locale('en'),
}) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ShipmentProvider>.value(value: hosts.assigned),
        ChangeNotifierProvider<ShipmentInstantprovider>.value(
          value: hosts.instant,
        ),
        ChangeNotifierProvider<HomeProvider>.value(value: hosts.home),
        ChangeNotifierProvider<LocaleProvider>(
          create: (_) => LocaleProvider(loadSaved: false),
        ),
        ChangeNotifierProvider<OrderLocationProvider>(
          create: (_) => _StubOrderLocationProvider(),
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
        home: OrderDetailPage(
          shipmentId: 7001,
          shipment: shipment,
          phoneCustomer: shipment.recipientPhone,
          orderDate: shipment.createdAt,
        ),
      ),
    ),
  );
  await _settle(tester);
}

final Finder _deliverButton = find.byKey(const ValueKey('deliver_action'));

/// The page always lists every status name (the "All Shipment Statuses" card),
/// so a status is asserted by how often its label appears against a baseline.
int _count(String text) => find.text(text).evaluate().length;

ElevatedButton _button(WidgetTester tester) => tester.widget<ElevatedButton>(
  find.descendant(
    of: _deliverButton,
    matching: find.byWidgetPredicate((w) => w is ElevatedButton),
  ),
);

Future<void> _tapDeliverAndConfirm(
  WidgetTester tester, {
  String confirm = 'Mark as Delivered',
}) async {
  await tester.ensureVisible(_deliverButton);
  await tester.tap(_deliverButton);
  await _settle(tester, frames: 8);
  await tester.tap(find.widgetWithText(ElevatedButton, confirm).last);
  await _settle(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store =
        _FakeSecureStore()
          ..values['driver_api_key'] = 'b2-test-key'
          ..values['driver_session_id'] = '601';
    AuthService.configureForTesting(secureStore: store);
    AppLocalizations.applyLocale(const Locale('en'));
  });

  tearDown(AuthService.resetForTesting);

  group('visibility (server rule: 4 -> 11)', () {
    testWidgets('V1. an instant shipment in transit (4) offers Delivered', (
      tester,
    ) async {
      await _pump(tester, _Hosts(_shipment()), _shipment());
      expect(_deliverButton, findsOneWidget);
      expect(find.text('Mark as Delivered'), findsOneWidget);
    });

    testWidgets('V2. a scheduled shipment in transit (4) offers Delivered', (
      tester,
    ) async {
      final s = _shipment(deliveryTypeId: 2);
      await _pump(tester, _Hosts(s), s);
      expect(_deliverButton, findsOneWidget);
    });

    for (final statusId in [1, 2, 3, 5, 6, 7, 8, 9, 10, 11]) {
      testWidgets('V3. status $statusId never offers Delivered', (
        tester,
      ) async {
        final s = _shipment(statusId: statusId, deliveryTypeId: 2);
        await _pump(tester, _Hosts(s), s);
        expect(_deliverButton, findsNothing);
      });
    }

    testWidgets('V4. an unaccepted instant offer never offers Delivered', (
      tester,
    ) async {
      final s = _shipment(driverId: 0);
      await _pump(tester, _Hosts(s), s);
      expect(_deliverButton, findsNothing);
    });

    testWidgets('V5. Arabic label and right-to-left layout', (tester) async {
      AppLocalizations.applyLocale(const Locale('ar'));
      await _pump(
        tester,
        _Hosts(_shipment()),
        _shipment(),
        locale: const Locale('ar'),
      );
      expect(
        find.descendant(of: _deliverButton, matching: find.text('تم التسليم')),
        findsOneWidget,
      );
      expect(
        Directionality.of(tester.element(_deliverButton)),
        TextDirection.rtl,
      );
    });
  });

  group('confirmation', () {
    testWidgets('C1. a tap asks first and shows the amount to collect', (
      tester,
    ) async {
      final hosts = _Hosts(_shipment());
      await _pump(tester, hosts, _shipment());
      await tester.ensureVisible(_deliverButton);
      await tester.tap(_deliverButton);
      await _settle(tester, frames: 8);
      expect(find.text('Mark as Delivered?'), findsOneWidget);
      expect(find.textContaining('BLK-7001'), findsWidgets);
      expect(find.textContaining('Amount to collect'), findsOneWidget);
      expect(hosts.instant.deliveries, 0);
    });

    testWidgets('C2. cancelling sends nothing', (tester) async {
      final hosts = _Hosts(_shipment());
      await _pump(tester, hosts, _shipment());
      await tester.ensureVisible(_deliverButton);
      await tester.tap(_deliverButton);
      await _settle(tester, frames: 8);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await _settle(tester);
      expect(hosts.instant.deliveries, 0);
      expect(_deliverButton, findsOneWidget);
    });
  });

  group('outcomes', () {
    testWidgets(
      'O1. success: server-confirmed Completed, button gone, lists and counters refreshed',
      (tester) async {
        final hosts = _Hosts(_shipment());
        await _pump(tester, hosts, _shipment());
        final completedBefore = _count('Completed');
        await _tapDeliverAndConfirm(tester);

        expect(hosts.instant.deliveries, 1);
        expect(hosts.instant.languages.single, 'en');
        expect(
          find.text('Shipment has been marked as delivered successfully.'),
          findsOneWidget,
        );
        expect(_deliverButton, findsNothing);
        expect(_count('Completed'), greaterThan(completedBefore));
        expect(hosts.assigned.refreshes, greaterThanOrEqualTo(1));
        expect(hosts.home.statisticsRefreshes, 1);
      },
    );

    testWidgets(
      'O2. a double tap starts one request; the button is disabled while it runs',
      (tester) async {
        final hosts = _Hosts(_shipment());
        hosts.instant.gate = Completer<void>();
        await _pump(tester, hosts, _shipment());
        await _tapDeliverAndConfirm(tester);

        expect(hosts.instant.deliveries, 1);
        expect(_button(tester).onPressed, isNull);
        await tester.tap(_deliverButton, warnIfMissed: false);
        await _settle(tester, frames: 4);
        expect(find.text('Mark as Delivered?'), findsNothing);
        expect(hosts.instant.deliveries, 1);

        hosts.instant.gate!.complete();
        await _settle(tester);
        expect(hosts.instant.deliveries, 1);
      },
    );

    testWidgets(
      'O3. 409: explains, re-reads, adopts the server state; never Completed',
      (tester) async {
        final hosts = _Hosts(_shipment());
        hosts.instant.reply = const ShipmentActionResult(
          success: false,
          code: 'INVALID_STATUS',
          httpStatus: 409,
          message:
              'This shipment\'s status changed, so it was not marked as delivered. It has been refreshed.',
        );
        hosts.instant.rowsAfterRefresh = [_shipment(statusId: 7)];
        await _pump(tester, hosts, _shipment());
        final cancelledBefore = _count('Cancelled');
        await _tapDeliverAndConfirm(tester);

        expect(find.textContaining('status changed'), findsOneWidget);
        expect(hosts.instant.refreshes, 1);
        expect(_deliverButton, findsNothing);
        // The server's state (cancelled) is shown, not a delivery.
        expect(_count('Cancelled'), greaterThan(cancelledBefore));
      },
    );

    testWidgets(
      'O4. a timeout is not resent and never shows Completed on its own',
      (tester) async {
        final hosts = _Hosts(_shipment());
        hosts.instant.reply = const ShipmentActionResult(
          success: false,
          unconfirmed: true,
          message:
              'No reply from the server. The delivery may not be saved; checking the shipment.',
        );
        await _pump(tester, hosts, _shipment());
        final completedBefore = _count('Completed');
        await _tapDeliverAndConfirm(tester);

        expect(hosts.instant.deliveries, 1);
        expect(hosts.instant.refreshes, 1);
        expect(find.textContaining('No reply from the server'), findsOneWidget);
        expect(_count('Completed'), completedBefore);
        // Still in transit on the server: the driver may try again (same request id).
        expect(_deliverButton, findsOneWidget);
      },
    );

    testWidgets(
      'O5. a timeout whose delivery was recorded shows the server\'s state',
      (tester) async {
        final hosts = _Hosts(_shipment());
        hosts.instant.reply = const ShipmentActionResult(
          success: false,
          unconfirmed: true,
          message: 'No reply from the server.',
        );
        hosts.instant.rowsAfterRefresh = [_shipment(statusId: 11)];
        await _pump(tester, hosts, _shipment());
        await _tapDeliverAndConfirm(tester);

        expect(
          find.text('The shipment is now closed on the server.'),
          findsOneWidget,
        );
        expect(_deliverButton, findsNothing);
      },
    );

    testWidgets('O6. 403 NOT_ASSIGNED: message and re-read', (tester) async {
      final hosts = _Hosts(_shipment());
      hosts.instant.reply = const ShipmentActionResult(
        success: false,
        code: 'NOT_ASSIGNED',
        httpStatus: 403,
        message: 'This shipment is no longer assigned to you.',
      );
      await _pump(tester, hosts, _shipment());
      final completedBefore = _count('Completed');
      await _tapDeliverAndConfirm(tester);
      expect(
        find.text('This shipment is no longer assigned to you.'),
        findsOneWidget,
      );
      expect(hosts.instant.refreshes, 1);
      expect(_count('Completed'), completedBefore);
    });

    testWidgets('O7. leaving the screen during the request is safe', (
      tester,
    ) async {
      final hosts = _Hosts(_shipment());
      hosts.instant.gate = Completer<void>();
      await _pump(tester, hosts, _shipment());
      await _tapDeliverAndConfirm(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      hosts.instant.gate!.complete();
      await _settle(tester);
      expect(tester.takeException(), isNull);
      expect(hosts.instant.deliveries, 1);
    });

    testWidgets(
      'O8. Arabic confirmation and the server language for the request',
      (tester) async {
        AppLocalizations.applyLocale(const Locale('ar'));
        final hosts = _Hosts(_shipment());
        await _pump(tester, hosts, _shipment(), locale: const Locale('ar'));
        await tester.ensureVisible(_deliverButton);
        await tester.tap(_deliverButton);
        await _settle(tester, frames: 8);
        expect(find.text('تأكيد التسليم؟'), findsOneWidget);
        expect(find.textContaining('المبلغ المطلوب تحصيله'), findsOneWidget);
        await tester.tap(
          find.widgetWithText(ElevatedButton, 'تم التسليم').last,
        );
        await _settle(tester);
        expect(hosts.instant.languages.single, 'ar');
      },
    );
  });
}
