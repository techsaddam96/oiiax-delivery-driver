import 'package:blockatie/models/shipment.dart';
import 'package:blockatie/provider/shipment.dart';
import 'package:blockatie/provider/shipment_instsnt.dart';
import 'package:blockatie/utils/driver_shipment_list_rules.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _action(
  String id,
  int targetStatusId, {
  bool enabled = true,
  String group = 'progression',
}) => <String, dynamic>{
  'id': id,
  'target_status_id': targetStatusId,
  'enabled': enabled,
  'group': group,
  if (!enabled) 'blocked_reason': 'SERVER_REFUSED',
};

Map<String, dynamic> _shipmentJson({
  required int id,
  int driverId = 0,
  int deliveryTypeId = 1,
  int statusId = 1,
  List<Map<String, dynamic>> actions = const <Map<String, dynamic>>[],
  Map<String, dynamic>? custodyState,
}) => <String, dynamic>{
  'id': id,
  'driver_id': driverId,
  'delivery_type_id': deliveryTypeId,
  'shipment_status_id': statusId,
  'shipment_status': statusId,
  'shipment_date': '2026-10-28 09:00:00',
  'created_at': '2026-10-28 09:00:00',
  'updated_at': '2026-10-28 09:00:00',
  'policy_num': 'QA-$id',
  'driver_action_contract_version': 1,
  'driver_actions': actions,
  if (custodyState != null) 'custody_state': custodyState,
};

Shipment _shipment({
  required int id,
  int driverId = 0,
  int deliveryTypeId = 1,
  int statusId = 1,
  List<Map<String, dynamic>> actions = const <Map<String, dynamic>>[],
  Map<String, dynamic>? custodyState,
}) => Shipment.fromJson(
  _shipmentJson(
    id: id,
    driverId: driverId,
    deliveryTypeId: deliveryTypeId,
    statusId: statusId,
    actions: actions,
    custodyState: custodyState,
  ),
);

Map<String, dynamic> _page(
  List<Map<String, dynamic>> shipments, {
  Map<String, dynamic>? activeInstant,
}) => <String, dynamic>{
  'status': 'success',
  'driverId': 42,
  'count': shipments.length,
  'shipments': shipments,
  'active_instant': activeInstant,
  'pagination': <String, dynamic>{
    'page': 1,
    'limit': 5,
    'total': shipments.length,
    'total_pages': 1,
  },
};

void main() {
  group('DriverShipmentListRules available offers', () {
    test('shows only an unassigned, server-authorized instant offer', () {
      final eligible = _shipment(
        id: 1,
        actions: [_action('accept_shipment', 2)],
      );
      final anotherDriversOffer = _shipment(
        id: 2,
        driverId: 77,
        actions: [_action('accept_shipment', 2)],
      );
      final scheduled = _shipment(
        id: 3,
        deliveryTypeId: 2,
        actions: [_action('accept_shipment', 2)],
      );
      final expired = _shipment(
        id: 4,
        actions: [_action('accept_shipment', 2, enabled: false)],
      );
      final closedWithStaleAction = _shipment(
        id: 40,
        statusId: 6,
        actions: [_action('accept_shipment', 2)],
      );
      final withoutContract = Shipment.fromJson(<String, dynamic>{
        ..._shipmentJson(id: 5, actions: [_action('accept_shipment', 2)]),
        'driver_action_contract_version': 0,
      });

      expect(DriverShipmentListRules.isAvailableInstantOffer(eligible), isTrue);
      expect(
        DriverShipmentListRules.isAvailableInstantOffer(anotherDriversOffer),
        isFalse,
      );
      expect(
        DriverShipmentListRules.isAvailableInstantOffer(scheduled),
        isFalse,
      );
      expect(DriverShipmentListRules.isAvailableInstantOffer(expired), isFalse);
      expect(
        DriverShipmentListRules.isAvailableInstantOffer(closedWithStaleAction),
        isFalse,
      );
      expect(
        DriverShipmentListRules.isAvailableInstantOffer(withoutContract),
        isFalse,
      );
    });
  });

  group('DriverShipmentListRules active work', () {
    test(
      'requires current-driver ownership and the server action contract',
      () {
        final accepted = _shipment(
          id: 10,
          driverId: 42,
          statusId: 2,
          actions: [_action('arrive_at_pickup', 10)],
        );
        final directAdminAssignment = _shipment(
          id: 11,
          driverId: 42,
          statusId: 10,
          actions: [_action('confirm_pickup', 4)],
        );
        final reassigned = _shipment(
          id: 12,
          driverId: 77,
          statusId: 2,
          actions: [_action('arrive_at_pickup', 10)],
        );
        final completed = _shipment(
          id: 13,
          driverId: 42,
          statusId: 11,
          // A stale/malformed response must not revive a completed card.
          actions: [_action('complete_delivery', 11)],
        );
        final cancelled = _shipment(
          id: 15,
          driverId: 42,
          statusId: 7,
          actions: [_action('cancel_shipment', 7, group: 'exception')],
        );
        final returnInCurrentCustody = _shipment(
          id: 14,
          driverId: 42,
          statusId: 8,
          actions: [
            _action('return_shipment', 8, enabled: false, group: 'exception'),
          ],
          custodyState: const <String, dynamic>{
            'state': 'driver',
            'held_by_current_driver': true,
          },
        );

        expect(
          DriverShipmentListRules.isActiveForCurrentDriver(accepted, 42),
          isTrue,
        );
        expect(
          DriverShipmentListRules.isActiveForCurrentDriver(
            directAdminAssignment,
            42,
          ),
          isTrue,
        );
        expect(
          DriverShipmentListRules.isActiveForCurrentDriver(reassigned, 42),
          isFalse,
        );
        expect(
          DriverShipmentListRules.isActiveForCurrentDriver(completed, 42),
          isFalse,
        );
        expect(
          DriverShipmentListRules.isActiveForCurrentDriver(cancelled, 42),
          isFalse,
        );
        expect(
          DriverShipmentListRules.isActiveForCurrentDriver(
            returnInCurrentCustody,
            42,
          ),
          isTrue,
        );
      },
    );
  });

  test(
    'instant provider separates server-confirmed active work from offers',
    () {
      final provider = ShipmentInstantprovider();
      addTearDown(provider.dispose);

      provider.applyServerPageForTest(
        ShipmentsResponse.fromJson(
          _page(
            [
              _shipmentJson(id: 1, actions: [_action('accept_shipment', 2)]),
              _shipmentJson(
                id: 2,
                actions: [_action('accept_shipment', 2, enabled: false)],
              ),
              _shipmentJson(
                id: 3,
                driverId: 77,
                actions: [_action('arrive_at_pickup', 10)],
              ),
              _shipmentJson(
                id: 4,
                driverId: 42,
                statusId: 2,
                actions: [_action('arrive_at_pickup', 10)],
              ),
              _shipmentJson(
                id: 5,
                driverId: 42,
                deliveryTypeId: 2,
                actions: [_action('arrive_at_pickup', 10)],
              ),
            ],
            activeInstant: _shipmentJson(
              id: 6,
              driverId: 42,
              statusId: 10,
              actions: [_action('confirm_pickup', 4)],
            ),
          ),
        ),
        requestedPage: 1,
        driverId: 42,
      );

      expect(
        provider.availableInstantShipments.map((shipment) => shipment.id),
        [1],
      );
      expect(provider.paginatedShipments.map((shipment) => shipment.id), [1]);
      expect(provider.activeInstantShipment?.id, 6);
      expect(provider.activeInstantShipments.map((shipment) => shipment.id), [
        4,
      ]);
      expect(provider.totalCount, 1);
    },
  );

  test('assigned provider exposes only current operational work as active', () {
    final provider = ShipmentProvider();
    addTearDown(provider.dispose);

    provider.applyServerPageForTest(
      ShipmentsResponse.fromJson(
        _page([
          _shipmentJson(
            id: 20,
            driverId: 42,
            statusId: 2,
            actions: [_action('arrive_at_pickup', 10)],
          ),
          _shipmentJson(
            id: 21,
            driverId: 42,
            statusId: 9,
            actions: [_action('return_shipment', 8, group: 'exception')],
          ),
          _shipmentJson(
            id: 22,
            driverId: 42,
            statusId: 11,
            actions: [_action('complete_delivery', 11, enabled: false)],
          ),
          _shipmentJson(
            id: 23,
            driverId: 77,
            statusId: 2,
            actions: [_action('arrive_at_pickup', 10)],
          ),
        ]),
      ),
      requestedPage: 1,
      driverId: 42,
    );

    expect(provider.activeOperationalShipments.map((shipment) => shipment.id), [
      20,
      21,
    ]);
  });
}
