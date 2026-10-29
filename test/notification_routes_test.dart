// Verifies notification tap routing: every driver-facing payload the backend
// emits resolves to the right destination, malformed payloads are inert, and
// duplicate deliveries collapse to a single navigation.

import 'package:blockatie/constants/notification_routes.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mirrors NotificationSystem's per-driver de-duplication key.
String dedupeKeyFor(DriverNotificationTarget target, String driverId) =>
    '${target.dedupeKey}:$driverId';

void main() {
  group('driver_settlement', () {
    test('resolves to the settlement detail screen', () {
      final target = resolveDriverNotificationTarget({
        'type': 'driver_settlement',
        'event': 'settlement_confirmed',
        'settlement_id': '412',
      });

      expect(target, isNotNull);
      expect(
        target!.destination,
        DriverNotificationDestination.settlementDetails,
      );
      expect(target.settlementId, 412);
      expect(target.shipmentId, isNull);
    });

    test('is ignored without a usable settlement_id', () {
      for (final bad in [null, '', '0', '-3', 'abc', {}]) {
        expect(
          resolveDriverNotificationTarget({
            'type': 'driver_settlement',
            if (bad != null) 'settlement_id': bad,
          }),
          isNull,
          reason: 'settlement_id=$bad must not route',
        );
      }
    });
  });

  group('assigned shipment types', () {
    // Exactly the types the backend sends to hero_<driverId>.
    const types = [
      'shipment_assigned',
      'shipment_updated',
      'shipment_status_updated',
      'shipment_collected',
      'shipment',
      'new_shipment',
    ];

    for (final type in types) {
      test('$type resolves to shipment details', () {
        final target = resolveDriverNotificationTarget({
          'type': type,
          'shipment_id': '900002',
          'policy_num': 'AMM-900002',
          'url': '/shipment_info_details/OTAwMDAy/en/',
        });

        expect(target, isNotNull, reason: '$type must route');
        expect(
          target!.destination,
          DriverNotificationDestination.shipmentDetails,
        );
        expect(target.shipmentId, 900002);
        expect(target.policyNum, 'AMM-900002');
        expect(target.type, type);
      });
    }

    test('an int shipment_id is accepted as well as a string', () {
      final target = resolveDriverNotificationTarget({
        'type': 'shipment_assigned',
        'shipment_id': 900002,
      });

      expect(target!.shipmentId, 900002);
    });

    test('is ignored without a usable shipment_id', () {
      for (final bad in [null, '', '0', '-1', 'not-a-number']) {
        expect(
          resolveDriverNotificationTarget({
            'type': 'shipment_assigned',
            if (bad != null) 'shipment_id': bad,
          }),
          isNull,
          reason: 'shipment_id=$bad must not route',
        );
      }
    });

    test('a literal "null" policy_num is normalised away', () {
      final target = resolveDriverNotificationTarget({
        'type': 'shipment_updated',
        'shipment_id': '5',
        'policy_num': 'null',
      });

      expect(target!.policyNum, isNull);
    });
  });

  group('available_shipment', () {
    test('resolves to the available shipments tab', () {
      final target = resolveDriverNotificationTarget({
        'type': 'available_shipment',
        'shipment_id': '900050',
        'policy_num': 'AMM-900050',
        'delivery_type_id': '1',
      });

      expect(
        target!.destination,
        DriverNotificationDestination.availableShipments,
      );
      expect(target.shipmentId, 900050);
    });

    test('still routes to the tab when the id is missing', () {
      // The offer list is a valid destination on its own.
      final target = resolveDriverNotificationTarget({
        'type': 'available_shipment',
      });

      expect(
        target!.destination,
        DriverNotificationDestination.availableShipments,
      );
      expect(target.shipmentId, isNull);
    });
  });

  group('malformed and unknown payloads are inert', () {
    test('an empty payload does not route', () {
      expect(resolveDriverNotificationTarget({}), isNull);
    });

    test('a missing or blank type does not route', () {
      expect(resolveDriverNotificationTarget({'shipment_id': '1'}), isNull);
      expect(
        resolveDriverNotificationTarget({'type': '   ', 'shipment_id': '1'}),
        isNull,
      );
    });

    test('client-facing and unrelated types do not route', () {
      for (final type in [
        'driver_assigned', // sent to the client, not the driver
        'client_statement',
        'admin',
        'employee',
        'subscription_test',
        'totally_unknown',
      ]) {
        expect(
          resolveDriverNotificationTarget({
            'type': type,
            'shipment_id': '1',
            'settlement_id': '1',
          }),
          isNull,
          reason: '$type must not route',
        );
      }
    });

    test('a non-string type value does not crash the resolver', () {
      expect(
        resolveDriverNotificationTarget({'type': 42, 'shipment_id': '1'}),
        isNull,
      );
    });
  });

  group('duplicate suppression', () {
    test('the same notification yields a stable key', () {
      Map<String, dynamic> payload() => {
        'type': 'shipment_assigned',
        'shipment_id': '900002',
        'policy_num': 'AMM-900002',
      };

      final first = resolveDriverNotificationTarget(payload())!;
      final second = resolveDriverNotificationTarget(payload())!;

      expect(dedupeKeyFor(first, '900004'), dedupeKeyFor(second, '900004'));
    });

    test('the same shipment under different types collapses to one key', () {
      // An assignment followed by an update for the same shipment should not
      // open the detail screen twice.
      final assigned = resolveDriverNotificationTarget({
        'type': 'shipment_assigned',
        'shipment_id': '900002',
      })!;
      final updated = resolveDriverNotificationTarget({
        'type': 'shipment_updated',
        'shipment_id': '900002',
      })!;

      expect(
        dedupeKeyFor(assigned, '900004'),
        dedupeKeyFor(updated, '900004'),
      );
    });

    test('different shipments stay distinct', () {
      final a = resolveDriverNotificationTarget({
        'type': 'shipment_assigned',
        'shipment_id': '1',
      })!;
      final b = resolveDriverNotificationTarget({
        'type': 'shipment_assigned',
        'shipment_id': '2',
      })!;

      expect(dedupeKeyFor(a, '900004'), isNot(dedupeKeyFor(b, '900004')));
    });

    test('settlements and shipments never share a key', () {
      final settlement = resolveDriverNotificationTarget({
        'type': 'driver_settlement',
        'settlement_id': '7',
      })!;
      final shipment = resolveDriverNotificationTarget({
        'type': 'shipment_assigned',
        'shipment_id': '7',
      })!;

      expect(
        dedupeKeyFor(settlement, '900004'),
        isNot(dedupeKeyFor(shipment, '900004')),
      );
    });

    test('the key is driver-scoped so Driver B is not suppressed by A', () {
      final target = resolveDriverNotificationTarget({
        'type': 'shipment_assigned',
        'shipment_id': '900002',
      })!;

      expect(
        dedupeKeyFor(target, '900004'),
        isNot(dedupeKeyFor(target, '900012')),
      );
    });

    test('a simulated double delivery navigates once', () {
      final handled = <String>{};
      bool register(String key) => handled.add(key);

      final target = resolveDriverNotificationTarget({
        'type': 'shipment_assigned',
        'shipment_id': '900002',
      })!;
      final key = dedupeKeyFor(target, '900004');

      expect(register(key), isTrue); // first tap navigates
      expect(register(key), isFalse); // replayed delivery does not
      expect(register(key), isFalse);
    });
  });
}
