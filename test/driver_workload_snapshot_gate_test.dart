import 'package:blockatie/models/shipment.dart';
import 'package:blockatie/provider/shipment_instsnt.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _response({
  Map<String, dynamic>? workloadSnapshot,
}) => <String, dynamic>{
  'status': 'success',
  'driver_id': 42,
  'count': 0,
  'shipments': <Map<String, dynamic>>[],
  'pagination': <String, dynamic>{
    'page': 1,
    'limit': 5,
    'total': 0,
    'total_pages': 0,
  },
  if (workloadSnapshot != null) 'driver_workload_snapshot': workloadSnapshot,
};

Map<String, dynamic> _snapshot({
  int driverId = 42,
  int activeOperationalTotal = 0,
  bool complete = true,
  int contractVersion = 1,
  DateTime? expiresAt,
}) => <String, dynamic>{
  'contract_version': contractVersion,
  'snapshot_id': 'qa-snapshot-1',
  'driver_id': driverId,
  'complete': complete,
  'active_operational_total': activeOperationalTotal,
  'expires_at':
      (expiresAt ?? DateTime.now().toUtc().add(const Duration(minutes: 5)))
          .toIso8601String(),
};

void main() {
  group('DriverWorkloadSnapshot', () {
    test('requires a complete, unexpired zero-work proof for this driver', () {
      final now = DateTime.now().toUtc();
      final valid = DriverWorkloadSnapshot.fromJson(
        _snapshot(expiresAt: now.add(const Duration(minutes: 1))),
      );

      expect(valid.provesNoActiveOperationalWorkFor(42, now), isTrue);
      expect(
        DriverWorkloadSnapshot.fromJson(
          _snapshot(
            activeOperationalTotal: 1,
            expiresAt: now.add(const Duration(minutes: 1)),
          ),
        ).provesNoActiveOperationalWorkFor(42, now),
        isFalse,
      );
      expect(
        DriverWorkloadSnapshot.fromJson(
          _snapshot(
            complete: false,
            expiresAt: now.add(const Duration(minutes: 1)),
          ),
        ).provesNoActiveOperationalWorkFor(42, now),
        isFalse,
      );
      expect(
        DriverWorkloadSnapshot.fromJson(
          _snapshot(
            driverId: 99,
            expiresAt: now.add(const Duration(minutes: 1)),
          ),
        ).provesNoActiveOperationalWorkFor(42, now),
        isFalse,
      );
      expect(
        DriverWorkloadSnapshot.fromJson(
          _snapshot(expiresAt: now.subtract(const Duration(seconds: 1))),
        ).provesNoActiveOperationalWorkFor(42, now),
        isFalse,
      );
    });
  });

  group('ShipmentInstantprovider offer gate', () {
    test('fails closed when the backend has no workload snapshot', () {
      final provider = ShipmentInstantprovider();
      addTearDown(provider.dispose);

      provider.applyServerPageForTest(
        ShipmentsResponse.fromJson(_response()),
        requestedPage: 1,
        driverId: 42,
      );

      expect(provider.canShowAvailableInstantOffers, isFalse);
    });

    test('opens only from a fresh matching zero-work server snapshot', () {
      final provider = ShipmentInstantprovider();
      addTearDown(provider.dispose);

      provider.applyServerPageForTest(
        ShipmentsResponse.fromJson(_response(workloadSnapshot: _snapshot())),
        requestedPage: 1,
        driverId: 42,
      );

      expect(provider.canShowAvailableInstantOffers, isTrue);
    });
  });
}
