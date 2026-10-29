import 'package:blockatie/models/shipment.dart';
import 'package:blockatie/utils/driver_shipment_actions.dart';
import 'package:flutter_test/flutter_test.dart';

Shipment _shipment({
  required int deliveryTypeId,
  required int driverId,
  required int statusId,
  required List<String> enabledActions,
}) {
  const actionIds = <String>[
    'accept_shipment',
    'arrive_at_pickup',
    'confirm_pickup',
    'complete_delivery',
    'cancel_shipment',
    'return_shipment',
    'failed_delivery',
  ];
  const targets = <String, int>{
    'accept_shipment': 2,
    'arrive_at_pickup': 10,
    'confirm_pickup': 4,
    'complete_delivery': 11,
    'cancel_shipment': 7,
    'return_shipment': 8,
    'failed_delivery': 9,
  };
  const exceptions = <String>{
    'cancel_shipment',
    'return_shipment',
    'failed_delivery',
  };
  return Shipment.fromJson({
    'id': 7001,
    'shipment_status_id': statusId,
    'shipment_status': statusId,
    'delivery_type_id': deliveryTypeId,
    'driver_id': driverId,
    'driver_action_contract_version': 1,
    'driver_actions': [
      for (final id in actionIds)
        {
          'id': id,
          'target_status_id': targets[id],
          'group': exceptions.contains(id) ? 'exception' : 'progression',
          'enabled': enabledActions.contains(id),
        },
    ],
  });
}

void main() {
  group('server-backed driver lifecycle presentation', () {
    test('an unaccepted instant offer has no forward shipment step', () {
      final shipment = _shipment(
        deliveryTypeId: 1,
        driverId: 0,
        statusId: 1,
        enabledActions: ['accept_shipment'],
      );

      final actions = driverShipmentActionsForShipment(shipment);
      expect(actions.primary, isNull);
      expect(actions.block, DriverStepBlock.notAccepted);
      expect(shipment.allowsAction('accept_shipment'), isTrue);
      expect(
        driverStatusSheetModeForShipment(shipment),
        DriverStatusSheetMode.unavailable,
      );
    });

    test('accepted instant and direct assignments both start at the store', () {
      for (final deliveryTypeId in const [1, 2]) {
        final shipment = _shipment(
          deliveryTypeId: deliveryTypeId,
          driverId: 501,
          statusId: 2,
          enabledActions: [
            'arrive_at_pickup',
            'confirm_pickup',
            'cancel_shipment',
          ],
        );

        final actions = driverShipmentActionsForShipment(shipment);
        expect(driverShipmentIsPrePickup(shipment), isTrue);
        expect(actions.primary, DriverShipmentStep.arriveAtStore);
        expect(actions.secondary, DriverShipmentStep.pickUp);
        expect(shipment.allowsAction('accept_shipment'), isFalse);
        expect(
          driverStatusSheetCardLauncherIsVisible(shipment),
          isFalse,
          reason: 'the compact launcher waits for confirmed arrival',
        );
        expect(
          driverShipmentDetailsCardLauncherIsVisible(shipment),
          isFalse,
          reason: 'details wait for the server-confirmed store arrival',
        );
      }
    });

    test('arrival advances to pickup only after the server state is 10', () {
      final shipment = _shipment(
        deliveryTypeId: 2,
        driverId: 501,
        statusId: 10,
        enabledActions: ['confirm_pickup', 'cancel_shipment'],
      );

      final actions = driverShipmentActionsForShipment(shipment);
      expect(driverShipmentIsPrePickup(shipment), isTrue);
      expect(actions.primary, DriverShipmentStep.pickUp);
      expect(actions.secondary, isNull);
      expect(
        driverStatusSheetModeForShipment(shipment),
        DriverStatusSheetMode.prePickupExceptions,
      );
      expect(driverStatusSheetCardLauncherIsVisible(shipment), isTrue);
      expect(driverShipmentDetailsCardLauncherIsVisible(shipment), isTrue);
    });

    test('only a confirmed pickup snapshot enables delivery sheet actions', () {
      final beforePickup = _shipment(
        deliveryTypeId: 2,
        driverId: 501,
        statusId: 10,
        enabledActions: ['confirm_pickup', 'cancel_shipment'],
      );
      final afterPickup = _shipment(
        deliveryTypeId: 2,
        driverId: 501,
        statusId: 4,
        enabledActions: ['complete_delivery'],
      );

      expect(
        driverStatusSheetModeForShipment(beforePickup),
        DriverStatusSheetMode.prePickupExceptions,
      );
      expect(
        driverStatusSheetAllowsAction(
          mode: driverStatusSheetModeForShipment(beforePickup),
          actionId: 'confirm_pickup',
          actionGroup: 'progression',
          canExecute: true,
        ),
        isFalse,
      );
      expect(driverShipmentIsPrePickup(afterPickup), isFalse);
      expect(driverShipmentDetailsCardLauncherIsVisible(afterPickup), isTrue);
      expect(
        driverShipmentActionsForShipment(afterPickup).primary,
        DriverShipmentStep.deliver,
      );
      expect(
        driverStatusSheetModeForShipment(afterPickup),
        DriverStatusSheetMode.delivery,
      );
      expect(driverStatusSheetCardLauncherIsVisible(beforePickup), isTrue);
      expect(driverStatusSheetCardLauncherIsVisible(afterPickup), isTrue);
      expect(
        driverStatusSheetAllowsAction(
          mode: driverStatusSheetModeForShipment(afterPickup),
          actionId: 'complete_delivery',
          actionGroup: 'progression',
          canExecute: true,
        ),
        isTrue,
      );
    });

    test('a final shipment exposes no new forward transition', () {
      final shipment = _shipment(
        deliveryTypeId: 2,
        driverId: 501,
        statusId: 11,
        enabledActions: const [],
      );

      final actions = driverShipmentActionsForShipment(shipment);
      expect(actions.primary, isNull);
      expect(actions.block, DriverStepBlock.closed);
      expect(
        driverStatusSheetModeForShipment(shipment),
        DriverStatusSheetMode.unavailable,
      );
    });
  });
}
