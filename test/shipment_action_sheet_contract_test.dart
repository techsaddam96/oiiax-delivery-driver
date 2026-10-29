import 'package:blockatie/models/driver_action.dart';
import 'package:blockatie/models/shipment.dart';
import 'package:blockatie/provider/shipment_instsnt.dart';
import 'package:blockatie/utils/driver_shipment_actions.dart';
import 'package:blockatie/views/widgets/status_update_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

Shipment snapshot(
  int status, {
  bool contract = true,
  int owner = 41,
  bool held = false,
}) {
  final legal = <String>{
    if (owner == 0 && status == 1) 'accept_shipment',
    if (owner == 41 && !held && {1, 2, 3}.contains(status)) 'arrive_at_pickup',
    if (owner == 41 && !held && {2, 10}.contains(status)) 'confirm_pickup',
    if (owner == 41 && !held && status == 4) 'complete_delivery',
    if (owner == 41 && !{6, 7, 8, 11}.contains(status)) 'cancel_shipment',
    if (owner == 41 && !held && !{6, 7, 8, 11}.contains(status))
      'return_shipment',
    if (owner == 41 && !{6, 7, 8, 9, 11}.contains(status)) 'failed_delivery',
  };
  return Shipment.fromJson({
    'id': 17,
    'driver_id': owner,
    'delivery_type_id': 1,
    'shipment_status_id': status,
    'status_name_en': 'State $status',
    'status_name_ar': 'الحالة $status',
    if (contract) 'driver_action_contract_version': 1,
    'driver_lifecycle': [
      for (var id = 1; id <= 11; id++)
        {
          'id': id,
          'status_name_en': 'State $id',
          'status_name_ar': 'الحالة $id',
        },
    ],
    'driver_actions': [
      for (final entry in DriverAction.targets.entries)
        {
          'id': entry.key,
          'target_status_id': entry.value,
          'enabled': legal.contains(entry.key),
          'group':
              {7, 8, 9}.contains(entry.value) ? 'exception' : 'progression',
          'label_en':
              entry.key == 'complete_delivery'
                  ? 'Confirm delivery'
                  : 'Action ${entry.value}',
          'label_ar':
              entry.key == 'complete_delivery'
                  ? 'تم التسليم'
                  : 'إجراء ${entry.value}',
          'blocked_reason':
              legal.contains(entry.key)
                  ? null
                  : held
                  ? 'SHIPMENT_IN_WAREHOUSE'
                  : 'TRANSITION_NOT_ALLOWED',
        },
    ],
  });
}

Future<void> pumpSheet(
  WidgetTester tester,
  Future<Shipment?> Function(int) load, {
  String language = 'en',
  Future<ShipmentActionResult?> Function(Shipment, DriverAction)? execute,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      locale: Locale(language),
      supportedLocales: const [Locale('en'), Locale('ar')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: ShipmentStatusUpdateSheet(
            shipmentId: 17,
            statuses: const [],
            currentStatusId: 4,
            currentStatusLabel: 'In Transit',
            loadShipment: load,
            executeProgression: execute,
            onSubmit: (_, __) async => true,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

InkWell option(WidgetTester tester, int id) => tester.widget<InkWell>(
  find
      .descendant(
        of: find.byKey(ValueKey('lifecycle_status_$id')),
        matching: find.byType(InkWell),
      )
      .first,
);

void main() {
  const expectedTargets = <int, Set<int>>{
    // A direct assignment at status 1 is still before pickup: no delivery
    // action, only its existing server-authorized off-ramps.
    1: {7, 8, 9},
    // These are pickup-source states: retain only server-authorized off-ramps.
    2: {7, 8, 9},
    3: {7, 8, 9},
    10: {7, 8, 9},
    // A server-confirmed pickup is the first state that can expose delivery.
    4: {7, 8, 9, 11},
    5: {7, 8, 9},
    6: {},
    7: {},
    8: {},
    9: {7, 8},
    11: {},
  };

  for (final status in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]) {
    testWidgets('State $status shows only its authorized sheet actions', (
      tester,
    ) async {
      final row = snapshot(status);
      await pumpSheet(tester, (_) async => row);
      final expected = expectedTargets[status]!;
      for (var id = 1; id <= 11; id++) {
        final finder = find.byKey(ValueKey('lifecycle_status_$id'));
        expect(
          finder,
          expected.contains(id) ? findsOneWidget : findsNothing,
          reason: 'state $status target $id',
        );
        if (expected.contains(id)) {
          expect(
            option(tester, id).onTap,
            isNotNull,
            reason: 'state $status target $id',
          );
        }
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'Arabic iPhone viewport keeps familiar header, colors, cards and confirm footer',
    (tester) async {
      await pumpSheet(tester, (_) async => snapshot(4), language: 'ar');
      expect(find.text('تحديث حالة الشحنة'), findsOneWidget);
      expect(find.text('تأكيد التحديث'), findsOneWidget);
      expect(find.text('تم التسليم'), findsOneWidget);
      expect(
        Directionality.of(tester.element(find.text('تحديث حالة الشحنة'))),
        TextDirection.rtl,
      );
      final card = tester.widget<AnimatedContainer>(
        find.descendant(
          of: find.byKey(const ValueKey('lifecycle_status_11')),
          matching: find.byType(AnimatedContainer),
        ),
      );
      expect(card.duration, const Duration(milliseconds: 160));
      expect(card.padding, const EdgeInsets.all(13));
      final decoration = card.decoration! as BoxDecoration;
      expect(decoration.borderRadius, BorderRadius.circular(18));
      expect(decoration.color, const Color(0xffFFFFFF));
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration! as BoxDecoration).gradient is LinearGradient &&
              ((w.decoration! as BoxDecoration).gradient! as LinearGradient)
                      .colors
                      .first ==
                  const Color(0xff004AAD),
        ),
        findsOneWidget,
      );
      expect(option(tester, 11).onTap, isNotNull);
      expect(find.byKey(const ValueKey('lifecycle_status_10')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Pre-pickup snapshots never render delivery actions', (
    tester,
  ) async {
    for (final status in [2, 3, 10]) {
      await pumpSheet(tester, (_) async => snapshot(status));
      expect(find.byKey(const ValueKey('lifecycle_status_4')), findsNothing);
      expect(find.byKey(const ValueKey('lifecycle_status_10')), findsNothing);
      expect(find.byKey(const ValueKey('lifecycle_status_11')), findsNothing);
      expect(find.byKey(const ValueKey('lifecycle_status_7')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('a fresh pre-pickup snapshot defeats a stale delivery input', (
    tester,
  ) async {
    // pumpSheet intentionally gives the widget a stale currentStatusId of 4.
    // The fetched status-10 contract must still withhold delivery actions.
    await pumpSheet(tester, (_) async => snapshot(10));
    expect(find.byKey(const ValueKey('lifecycle_status_11')), findsNothing);
    expect(find.byKey(const ValueKey('lifecycle_status_7')), findsOneWidget);
  });

  testWidgets('a reassigned shipment fails closed even with a delivery cache', (
    tester,
  ) async {
    await pumpSheet(tester, (_) async => snapshot(4, owner: 99));
    expect(find.byKey(const ValueKey('lifecycle_status_11')), findsNothing);
    expect(find.byKey(const ValueKey('lifecycle_status_7')), findsNothing);
  });

  testWidgets(
    'Missing contract and warehouse hold fail closed; rejected step refreshes',
    (tester) async {
      await pumpSheet(tester, (_) async => snapshot(4, contract: false));
      expect(find.byKey(const ValueKey('lifecycle_status_11')), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await pumpSheet(tester, (_) async => snapshot(4, held: true));
      expect(find.byKey(const ValueKey('lifecycle_status_11')), findsNothing);
      await tester.pumpWidget(const SizedBox());
      var status = 4;
      var reads = 0;
      await pumpSheet(
        tester,
        (_) async {
          reads++;
          return snapshot(status);
        },
        execute: (_, __) async {
          status = 9;
          return ShipmentActionResult(
            success: false,
            code: 'SHIPMENT_STATE_CONFLICT',
            message: 'Refresh',
          );
        },
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('lifecycle_status_11')),
      );
      await tester.tap(find.byKey(const ValueKey('lifecycle_status_11')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm update'));
      await tester.pumpAndSettle();
      expect(reads, 2);
      expect(find.byKey(const ValueKey('lifecycle_status_11')), findsNothing);
      expect(option(tester, 7).onTap, isNotNull);
      expect(option(tester, 8).onTap, isNotNull);
      expect(find.byKey(const ValueKey('lifecycle_status_9')), findsNothing);
      expect(isFinalShipmentStatus(9), isFalse);
      expect(
        driverShipmentActionsForShipment(snapshot(4, contract: false)).primary,
        isNull,
      );
    },
  );

  testWidgets('An unclaimed offer has no delivery action sheet options', (
    tester,
  ) async {
    await pumpSheet(tester, (_) async => snapshot(1, owner: 0));
    expect(find.byKey(const ValueKey('lifecycle_status_2')), findsNothing);
    expect(find.byKey(const ValueKey('lifecycle_status_11')), findsNothing);
  });
}
