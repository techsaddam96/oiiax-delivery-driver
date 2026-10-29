import 'package:blockatie/models/shipment.dart';
import 'package:blockatie/provider/driver_shipment_sections.dart';
import 'package:blockatie/views/pages/shipments/shipments_page.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _snapshot({
  int driverId = 42,
  int total = 0,
  int version = 1,
  bool complete = true,
  DateTime? expiresAt,
}) => <String, dynamic>{
  'contract_version': version,
  'snapshot_id': 'synthetic-snapshot-$driverId-$total',
  'driver_id': driverId,
  'complete': complete,
  'active_operational_total': total,
  'expires_at':
      (expiresAt ?? DateTime.now().toUtc().add(const Duration(minutes: 5)))
          .toIso8601String(),
};

Map<String, dynamic> _shipment({
  required int id,
  int driverId = 42,
  int deliveryTypeId = 2,
  int statusId = 2,
  String? policy,
}) => <String, dynamic>{
  'id': id,
  'policy_num': policy ?? 'SYN-$id',
  'driver_id': driverId,
  'delivery_type_id': deliveryTypeId,
  'shipment_status_id': statusId,
  'shipment_status': statusId,
  'driver_action_contract_version': 1,
  'driver_actions': <Map<String, dynamic>>[
    <String, dynamic>{
      'id': driverId == 0 ? 'accept_shipment' : 'arrive_at_pickup',
      'enabled': true,
      'group': 'progression',
    },
  ],
};

ShipmentsResponse _response({
  required List<Map<String, dynamic>> shipments,
  Map<String, dynamic>? snapshot,
  int driverId = 42,
  int page = 1,
  int limit = 10,
  int? total,
  int? totalPages,
}) => ShipmentsResponse.fromJson(<String, dynamic>{
  // This is the actual new endpoint's root envelope, not the legacy `data`
  // wrapper. The parser needs to support it exactly.
  'success': true,
  'status': 'success',
  'driver_id': driverId,
  'count': shipments.length,
  'shipments': shipments,
  'pagination': <String, dynamic>{
    'page': page,
    'limit': limit,
    'total': total ?? shipments.length,
    'total_pages': totalPages ?? (shipments.isEmpty ? 0 : 1),
  },
  if (snapshot != null) 'driver_workload_snapshot': snapshot,
});

void _applyZeroWork(
  DriverShipmentSectionsProvider provider, {
  List<Map<String, dynamic>> available = const <Map<String, dynamic>>[],
}) {
  final snapshot = _snapshot();
  provider.applyServerResponseForTest(
    DriverShipmentSection.activeWork,
    _response(shipments: const <Map<String, dynamic>>[], snapshot: snapshot),
    authenticatedDriverId: 42,
  );
  provider.applyServerResponseForTest(
    DriverShipmentSection.availableInstant,
    _response(
      shipments: available,
      snapshot: snapshot,
      total: available.length,
    ),
    authenticatedDriverId: 42,
  );
}

void main() {
  group('DriverShipmentSectionsProvider', () {
    late DriverShipmentSectionsProvider provider;

    setUp(() => provider = DriverShipmentSectionsProvider());
    tearDown(() => provider.dispose());

    test('shows Available for Acceptance with five synthetic offers', () {
      _applyZeroWork(
        provider,
        available: List<Map<String, dynamic>>.generate(
          5,
          (index) => _shipment(id: 100 + index, driverId: 0, deliveryTypeId: 1),
        ),
      );

      final offers = provider.stateFor(DriverShipmentSection.availableInstant);
      expect(provider.canShowAvailableInstantOffers, isTrue);
      expect(offers.shipments, hasLength(5));
      expect(offers.total, 5);
    });

    test(
      'keeps Available for Acceptance visible when zero-work has no offers',
      () {
        _applyZeroWork(provider);

        final offers = provider.stateFor(
          DriverShipmentSection.availableInstant,
        );
        expect(provider.canShowAvailableInstantOffers, isTrue);
        expect(offers.shipments, isEmpty);
        expect(offers.total, 0);
      },
    );

    test('one accepted instant shipment hides only the offer category', () {
      final activeSnapshot = _snapshot(total: 1);
      provider.applyServerResponseForTest(
        DriverShipmentSection.activeWork,
        _response(
          shipments: <Map<String, dynamic>>[
            _shipment(id: 1, deliveryTypeId: 1, statusId: 2),
          ],
          snapshot: activeSnapshot,
        ),
        authenticatedDriverId: 42,
      );
      provider.applyServerResponseForTest(
        DriverShipmentSection.availableInstant,
        _response(
          shipments: const <Map<String, dynamic>>[],
          snapshot: activeSnapshot,
        ),
        authenticatedDriverId: 42,
      );
      provider.applyServerResponseForTest(
        DriverShipmentSection.history,
        _response(
          shipments: const <Map<String, dynamic>>[],
          snapshot: activeSnapshot,
        ),
        authenticatedDriverId: 42,
      );

      expect(
        provider.stateFor(DriverShipmentSection.activeWork).shipments,
        hasLength(1),
      );
      expect(
        provider.stateFor(DriverShipmentSection.history).hasLoaded,
        isTrue,
      );
      expect(provider.hasActiveOperationalWork, isTrue);
      expect(provider.canShowAvailableInstantOffers, isFalse);
    });

    test('preserves all simultaneous Admin and Instant assignments', () {
      final rows = <Map<String, dynamic>>[
        ...List<Map<String, dynamic>>.generate(
          2,
          (index) => _shipment(id: index + 1, deliveryTypeId: 1),
        ),
        ...List<Map<String, dynamic>>.generate(
          3,
          (index) => _shipment(id: index + 10, deliveryTypeId: 2),
        ),
      ];
      final snapshot = _snapshot(total: 5);
      provider.applyServerResponseForTest(
        DriverShipmentSection.activeWork,
        _response(shipments: rows, snapshot: snapshot, total: 5),
        authenticatedDriverId: 42,
      );
      provider.applyServerResponseForTest(
        DriverShipmentSection.availableInstant,
        _response(
          shipments: const <Map<String, dynamic>>[],
          snapshot: snapshot,
        ),
        authenticatedDriverId: 42,
      );

      final active = provider.stateFor(DriverShipmentSection.activeWork);
      expect(
        active.shipments.map((shipment) => shipment.id).toSet(),
        hasLength(5),
      );
      expect(active.total, 5);
      expect(provider.canShowAvailableInstantOffers, isFalse);
    });

    test(
      'keeps unresolved return/custody work in the server active category',
      () {
        final snapshot = _snapshot(total: 1);
        provider.applyServerResponseForTest(
          DriverShipmentSection.activeWork,
          _response(
            shipments: <Map<String, dynamic>>[
              _shipment(id: 88, deliveryTypeId: 2, statusId: 8),
            ],
            snapshot: snapshot,
          ),
          authenticatedDriverId: 42,
        );
        provider.applyServerResponseForTest(
          DriverShipmentSection.availableInstant,
          _response(
            shipments: const <Map<String, dynamic>>[],
            snapshot: snapshot,
          ),
          authenticatedDriverId: 42,
        );

        // The client does not reclassify terminal-looking status 8. It renders
        // the row where the custody-aware backend returned it.
        expect(
          provider
              .stateFor(DriverShipmentSection.activeWork)
              .shipments
              .single
              .id,
          88,
        );
        expect(provider.canShowAvailableInstantOffers, isFalse);
      },
    );

    test('uses the backend pagination total rather than a page row count', () {
      _applyZeroWork(provider);
      provider.applyServerResponseForTest(
        DriverShipmentSection.history,
        _response(
          shipments: <Map<String, dynamic>>[_shipment(id: 900, statusId: 11)],
          snapshot: _snapshot(),
          page: 2,
          limit: 10,
          total: 21,
          totalPages: 3,
        ),
        authenticatedDriverId: 42,
        requestedPage: 2,
      );

      final history = provider.stateFor(DriverShipmentSection.history);
      expect(history.shipments, hasLength(1));
      expect(history.total, 21);
      expect(history.totalPages, 3);
      expect(history.page, 2);
    });

    test(
      'keeps a completed history row separate from a zero-work offer gate',
      () {
        _applyZeroWork(provider);
        provider.applyServerResponseForTest(
          DriverShipmentSection.history,
          _response(
            shipments: <Map<String, dynamic>>[_shipment(id: 611, statusId: 11)],
            snapshot: _snapshot(),
          ),
          authenticatedDriverId: 42,
        );

        expect(
          provider.stateFor(DriverShipmentSection.history).shipments.single.id,
          611,
        );
        expect(provider.canShowAvailableInstantOffers, isTrue);
      },
    );

    test(
      'fails closed for missing, invalid, expired, or mismatched snapshots',
      () {
        final invalidSnapshots = <Map<String, dynamic>?>[
          null,
          _snapshot(version: 99),
          _snapshot(complete: false),
          _snapshot(
            expiresAt: DateTime.now().toUtc().subtract(
              const Duration(seconds: 1),
            ),
          ),
          _snapshot(driverId: 99),
        ];

        for (final snapshot in invalidSnapshots) {
          final isolated = DriverShipmentSectionsProvider();
          addTearDown(isolated.dispose);
          isolated.applyServerResponseForTest(
            DriverShipmentSection.activeWork,
            _response(
              shipments: const <Map<String, dynamic>>[],
              snapshot: snapshot,
            ),
            authenticatedDriverId: 42,
          );
          isolated.applyServerResponseForTest(
            DriverShipmentSection.availableInstant,
            _response(
              shipments: const <Map<String, dynamic>>[],
              snapshot: snapshot,
            ),
            authenticatedDriverId: 42,
          );
          expect(isolated.canShowAvailableInstantOffers, isFalse);
          expect(isolated.availabilityVerificationFailed, isTrue);
        }
      },
    );

    test('rejects an envelope for a different authenticated driver', () {
      provider.applyServerResponseForTest(
        DriverShipmentSection.activeWork,
        _response(
          shipments: const <Map<String, dynamic>>[],
          driverId: 99,
          snapshot: _snapshot(driverId: 99),
        ),
        authenticatedDriverId: 42,
      );
      _applyZeroWork(provider);

      expect(
        provider.stateFor(DriverShipmentSection.activeWork).hasError,
        isFalse,
      );
      // The valid fresh read replaces the rejected envelope; no old mismatch
      // can keep the category hidden or visible.
      expect(provider.canShowAvailableInstantOffers, isTrue);
    });

    test('a failed available request cannot be rendered as zero offers', () {
      _applyZeroWork(provider);
      provider.applyFailureForTest(
        DriverShipmentSection.availableInstant,
        DriverShipmentSectionFailure.network,
      );

      expect(provider.canShowAvailableInstantOffers, isFalse);
      expect(provider.availabilityVerificationFailed, isTrue);
      expect(provider.availabilityVerificationPending, isFalse);
    });

    test(
      'an Admin assignment arriving while offers are open hides only section 3',
      () {
        _applyZeroWork(provider);
        expect(provider.canShowAvailableInstantOffers, isTrue);

        final afterAssignment = _snapshot(total: 1);
        provider.applyServerResponseForTest(
          DriverShipmentSection.activeWork,
          _response(
            shipments: <Map<String, dynamic>>[
              _shipment(id: 312, deliveryTypeId: 2, statusId: 2),
            ],
            snapshot: afterAssignment,
          ),
          authenticatedDriverId: 42,
        );

        expect(
          provider
              .stateFor(DriverShipmentSection.activeWork)
              .shipments
              .single
              .id,
          312,
        );
        expect(provider.canShowAvailableInstantOffers, isFalse);
      },
    );

    test(
      'a session reset removes every cached category and workload proof',
      () {
        _applyZeroWork(provider);
        expect(provider.canShowAvailableInstantOffers, isTrue);

        provider.resetUserState();

        for (final section in DriverShipmentSection.values) {
          expect(provider.stateFor(section).hasLoaded, isFalse);
          expect(provider.stateFor(section).shipments, isEmpty);
        }
        expect(provider.canShowAvailableInstantOffers, isFalse);
      },
    );

    test(
      'a confirmed accept transition is represented only by fresh category data',
      () {
        _applyZeroWork(
          provider,
          available: <Map<String, dynamic>>[
            _shipment(id: 777, driverId: 0, deliveryTypeId: 1),
          ],
        );
        expect(provider.canShowAvailableInstantOffers, isTrue);

        final afterAccept = _snapshot(total: 1);
        provider.applyServerResponseForTest(
          DriverShipmentSection.activeWork,
          _response(
            shipments: <Map<String, dynamic>>[
              _shipment(id: 777, deliveryTypeId: 1, statusId: 2),
            ],
            snapshot: afterAccept,
          ),
          authenticatedDriverId: 42,
        );
        provider.applyServerResponseForTest(
          DriverShipmentSection.availableInstant,
          _response(
            shipments: const <Map<String, dynamic>>[],
            snapshot: afterAccept,
          ),
          authenticatedDriverId: 42,
        );

        expect(
          provider
              .stateFor(DriverShipmentSection.activeWork)
              .shipments
              .single
              .id,
          777,
        );
        expect(provider.canShowAvailableInstantOffers, isFalse);
      },
    );

    test('exposes exact Arabic and English section labels', () {
      expect(
        driverShipmentSectionLabel(DriverShipmentSection.activeWork, true),
        'المتاحة والمسندة',
      );
      expect(
        driverShipmentSectionLabel(DriverShipmentSection.history, true),
        'سجل الشحنات',
      );
      expect(
        driverShipmentSectionLabel(
          DriverShipmentSection.availableInstant,
          true,
        ),
        'المتاحة للاستلام',
      );
      expect(
        driverShipmentSectionLabel(DriverShipmentSection.activeWork, false),
        'Available & Assigned',
      );
      expect(
        driverShipmentSectionLabel(DriverShipmentSection.history, false),
        'Shipment History',
      );
      expect(
        driverShipmentSectionLabel(
          DriverShipmentSection.availableInstant,
          false,
        ),
        'Available for Acceptance',
      );
      expect(
        driverShipmentSectionEmptyTitle(
          DriverShipmentSection.availableInstant,
          true,
        ),
        'لا توجد شحنات متاحة حاليًا',
      );
      expect(
        driverShipmentSectionEmptyTitle(
          DriverShipmentSection.availableInstant,
          false,
        ),
        'No shipments available right now',
      );
    });
  });
}
