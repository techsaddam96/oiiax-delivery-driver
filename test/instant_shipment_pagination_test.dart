// Covers the Driver Instant Shipments pagination contract: the response parser
// adopts the server's page/total figures, the provider renders exactly what the
// server sent (no local slicing), the pinned instant job survives page
// navigation, and a page belonging to a previous driver session can never be
// shown to the next one.

import 'package:blockatie/models/shipment.dart';
import 'package:blockatie/provider/shipment_instsnt.dart';
import 'package:blockatie/services/user_session_state.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _shipmentJson({
  required int id,
  int driverId = 0,
  int deliveryTypeId = 1,
  int statusId = 1,
  String shipmentDate = '2026-09-16 10:00:00',
  String policyNum = '',
}) {
  final actions =
      driverId == 0
          ? <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'accept_shipment',
              'target_status_id': 2,
              'enabled': deliveryTypeId == 1 && statusId == 1,
              'group': 'progression',
              if (deliveryTypeId != 1 || statusId != 1)
                'blocked_reason': 'SERVER_REFUSED',
            },
          ]
          : <Map<String, dynamic>>[
            <String, dynamic>{
              'id': statusId == 10 ? 'confirm_pickup' : 'arrive_at_pickup',
              'target_status_id': statusId == 10 ? 4 : 10,
              'enabled': statusId == 2 || statusId == 3 || statusId == 10,
              'group': 'progression',
              if (statusId != 2 && statusId != 3 && statusId != 10)
                'blocked_reason': 'SERVER_REFUSED',
            },
          ];
  return <String, dynamic>{
    'id': id,
    'driver_id': driverId,
    'delivery_type_id': deliveryTypeId,
    'shipment_status_id': statusId,
    'shipment_status': statusId,
    'shipment_date': shipmentDate,
    'created_at': shipmentDate,
    'updated_at': shipmentDate,
    'policy_num': policyNum.isEmpty ? 'POL-$id' : policyNum,
    'driver_action_contract_version': 1,
    'driver_actions': actions,
  };
}

Map<String, dynamic> _pageJson({
  required List<Map<String, dynamic>> shipments,
  required int page,
  required int limit,
  required int total,
  required int totalPages,
  Map<String, dynamic>? activeInstant,
  int driverId = 7,
}) {
  return <String, dynamic>{
    'status': 'success',
    'message': 'Shipments fetched successfully',
    'driverId': driverId,
    'count': shipments.length,
    'shipments': shipments,
    'active_instant': activeInstant,
    'pagination': <String, dynamic>{
      'page': page,
      'limit': limit,
      'total': total,
      'total_pages': totalPages,
    },
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ShipmentsResponse pagination parsing', () {
    test('reads the server pagination block', () {
      final response = ShipmentsResponse.fromJson(
        _pageJson(
          shipments: [
            _shipmentJson(id: 10),
            _shipmentJson(id: 9),
            _shipmentJson(id: 8),
          ],
          page: 2,
          limit: 5,
          total: 13,
          totalPages: 3,
        ),
      );

      expect(response.pagination, isNotNull);
      expect(response.pagination!.page, 2);
      expect(response.pagination!.limit, 5);
      expect(response.pagination!.total, 13);
      expect(response.pagination!.totalPages, 3);
      expect(response.shipments.length, 3);
    });

    test('tolerates a backend that sends no pagination block', () {
      final response = ShipmentsResponse.fromJson(<String, dynamic>{
        'status': 'success',
        'driverId': 7,
        'shipments': [_shipmentJson(id: 1)],
      });

      expect(response.pagination, isNull);
      expect(response.activeInstant, isNull);
      expect(response.shipments.length, 1);
    });

    test('parses the pinned active instant shipment when present', () {
      final response = ShipmentsResponse.fromJson(
        _pageJson(
          shipments: [_shipmentJson(id: 4, deliveryTypeId: 3)],
          page: 1,
          limit: 5,
          total: 1,
          totalPages: 1,
          activeInstant: _shipmentJson(
            id: 99,
            driverId: 7,
            deliveryTypeId: 1,
            statusId: 2,
          ),
        ),
      );

      expect(response.activeInstant, isNotNull);
      expect(response.activeInstant!.id, 99);
      expect(response.activeInstant!.driverId, 7);
    });

    test('parses numeric strings in the pagination block', () {
      final response = ShipmentsResponse.fromJson(<String, dynamic>{
        'status': 'success',
        'shipments': <dynamic>[],
        'pagination': <String, dynamic>{
          'page': '3',
          'limit': '15',
          'total': '42',
          'total_pages': '3',
        },
      });

      expect(response.pagination!.page, 3);
      expect(response.pagination!.limit, 15);
      expect(response.pagination!.total, 42);
      expect(response.pagination!.totalPages, 3);
    });
  });

  group('ShipmentInstantprovider renders one server page', () {
    late ShipmentInstantprovider provider;

    setUp(() {
      provider = ShipmentInstantprovider();
    });

    tearDown(() {
      provider.dispose();
    });

    test('a full page is rendered whole, never sliced to itemsPerPage', () {
      // The backend may return up to 50 rows. Nothing may be dropped locally.
      final rows = List.generate(20, (i) => _shipmentJson(id: 100 - i));
      provider.applyServerPageForTest(
        ShipmentsResponse.fromJson(
          _pageJson(
            shipments: rows,
            page: 1,
            limit: 20,
            total: 57,
            totalPages: 3,
          ),
        ),
        requestedPage: 1,
        driverId: 7,
      );

      expect(provider.paginatedShipments.length, 20);
      expect(provider.currentPage, 1);
      expect(provider.totalPages, 3);
      // The API's aggregate may include assigned rows. The Available header
      // counts only the current page's contract-authorized offers.
      expect(provider.totalCount, 20);
    });

    test('server order is preserved exactly', () {
      // Deliberately not in id order: the server decides, the client obeys.
      final rows = [
        _shipmentJson(id: 3),
        _shipmentJson(id: 91),
        _shipmentJson(id: 12),
      ];
      provider.applyServerPageForTest(
        ShipmentsResponse.fromJson(
          _pageJson(
            shipments: rows,
            page: 1,
            limit: 5,
            total: 3,
            totalPages: 1,
          ),
        ),
        requestedPage: 1,
        driverId: 7,
      );

      expect(provider.paginatedShipments.map((s) => s.id).toList(), <int>[
        3,
        91,
        12,
      ]);
    });

    test('page 2 replaces page 1 rather than appending', () {
      provider.applyServerPageForTest(
        ShipmentsResponse.fromJson(
          _pageJson(
            shipments: [_shipmentJson(id: 10), _shipmentJson(id: 9)],
            page: 1,
            limit: 2,
            total: 4,
            totalPages: 2,
          ),
        ),
        requestedPage: 1,
        driverId: 7,
      );
      expect(provider.paginatedShipments.map((s) => s.id), <int>[10, 9]);

      provider.applyServerPageForTest(
        ShipmentsResponse.fromJson(
          _pageJson(
            shipments: [_shipmentJson(id: 8), _shipmentJson(id: 7)],
            page: 2,
            limit: 2,
            total: 4,
            totalPages: 2,
          ),
        ),
        requestedPage: 2,
        driverId: 7,
      );

      expect(provider.paginatedShipments.map((s) => s.id), <int>[8, 7]);
      expect(provider.currentPage, 2);
      // No row from page 1 leaked into page 2.
      expect(provider.paginatedShipments.any((s) => s.id == 10), isFalse);
    });

    test('an empty page reports no rows but keeps the server totals', () {
      provider.applyServerPageForTest(
        ShipmentsResponse.fromJson(
          _pageJson(
            shipments: const [],
            page: 1,
            limit: 5,
            total: 0,
            totalPages: 0,
          ),
        ),
        requestedPage: 1,
        driverId: 7,
      );

      expect(provider.paginatedShipments, isEmpty);
      expect(provider.totalCount, 0);
      // The UI only shows the pager when totalPages > 1, so 0 collapses to 1.
      expect(provider.totalPages, 1);
    });

    test('falls back to the requested page when pagination is missing', () {
      provider.applyServerPageForTest(
        ShipmentsResponse.fromJson(<String, dynamic>{
          'status': 'success',
          'shipments': [_shipmentJson(id: 5)],
        }),
        requestedPage: 4,
        driverId: 7,
      );

      expect(provider.currentPage, 4);
      expect(provider.totalCount, 1);
    });
  });

  group('pinned instant job and ownership rules', () {
    late ShipmentInstantprovider provider;

    setUp(() {
      provider = ShipmentInstantprovider();
    });

    tearDown(() {
      provider.dispose();
    });

    test('the pinned job stays visible on a later page', () {
      final pinned = _shipmentJson(
        id: 500,
        driverId: 7,
        deliveryTypeId: 1,
        statusId: 2,
      );

      provider.applyServerPageForTest(
        ShipmentsResponse.fromJson(
          _pageJson(
            shipments: [_shipmentJson(id: 30)],
            page: 3,
            limit: 5,
            total: 11,
            totalPages: 3,
            activeInstant: pinned,
          ),
        ),
        requestedPage: 3,
        driverId: 7,
      );

      expect(provider.activeInstantShipment?.id, 500);
      expect(provider.hasActiveInstantShipment, isTrue);
      // It has its own card, so it is not repeated in the list.
      expect(provider.paginatedShipments.any((s) => s.id == 500), isFalse);
      // Available totals never include a driver's active assignment.
      expect(provider.totalCount, 1);
    });

    test(
      'keeps additional admin-assigned instant shipments beside the pinned job',
      () {
        provider.applyServerPageForTest(
          ShipmentsResponse.fromJson(
            _pageJson(
              shipments: [
                _shipmentJson(
                  id: 501,
                  driverId: 7,
                  deliveryTypeId: 1,
                  statusId: 2,
                ),
                _shipmentJson(
                  id: 502,
                  driverId: 7,
                  deliveryTypeId: 1,
                  statusId: 3,
                ),
              ],
              page: 1,
              limit: 5,
              total: 2,
              totalPages: 1,
              activeInstant: _shipmentJson(
                id: 500,
                driverId: 7,
                deliveryTypeId: 1,
                statusId: 2,
              ),
            ),
          ),
          requestedPage: 1,
          driverId: 7,
        );

        expect(provider.activeInstantShipment?.id, 500);
        expect(provider.paginatedShipments, isEmpty);
        expect(provider.activeInstantShipments.map((s) => s.id), <int>[
          501,
          502,
        ]);
        expect(provider.totalCount, 0);
      },
    );

    test('a row owned by another driver is never rendered', () {
      provider.applyServerPageForTest(
        ShipmentsResponse.fromJson(
          _pageJson(
            shipments: [
              _shipmentJson(id: 1),
              // Should be impossible from the backend; refused here as well.
              _shipmentJson(id: 2, driverId: 999),
              _shipmentJson(id: 3, driverId: 7, statusId: 2),
            ],
            page: 1,
            limit: 5,
            total: 3,
            totalPages: 1,
          ),
        ),
        requestedPage: 1,
        driverId: 7,
      );

      expect(provider.paginatedShipments.map((s) => s.id), <int>[1]);
      expect(provider.activeInstantShipments.map((s) => s.id), <int>[3]);
    });

    test('closed shipments are not rendered in the available queue', () {
      provider.applyServerPageForTest(
        ShipmentsResponse.fromJson(
          _pageJson(
            shipments: [
              _shipmentJson(id: 1),
              _shipmentJson(id: 2, statusId: 6),
              _shipmentJson(id: 3, statusId: 9),
            ],
            page: 1,
            limit: 5,
            total: 3,
            totalPages: 1,
          ),
        ),
        requestedPage: 1,
        driverId: 7,
      );

      expect(provider.paginatedShipments.map((s) => s.id), <int>[1]);
    });
  });

  group('session isolation for the instant page', () {
    test('logout drops the page, totals, pinned job and search', () {
      final provider = ShipmentInstantprovider();
      addTearDown(provider.dispose);

      provider.applyServerPageForTest(
        ShipmentsResponse.fromJson(
          _pageJson(
            shipments: [_shipmentJson(id: 44)],
            page: 2,
            limit: 5,
            total: 9,
            totalPages: 2,
            activeInstant: _shipmentJson(
              id: 77,
              driverId: 7,
              deliveryTypeId: 1,
              statusId: 2,
            ),
          ),
        ),
        requestedPage: 2,
        driverId: 7,
      );
      expect(provider.paginatedShipments, isNotEmpty);
      expect(provider.activeInstantShipment, isNotNull);

      UserSessionState.reset(SessionResetReason.logout);

      expect(provider.paginatedShipments, isEmpty);
      expect(provider.activeInstantShipment, isNull);
      expect(provider.shipmentInstantResponse, isNull);
      expect(provider.currentPage, 1);
      expect(provider.totalCount, 0);
      expect(provider.totalPages, 1);
      expect(provider.searchQuery, '');
      expect(provider.hasLoaded, isFalse);
    });

    test(
      'a page fetched under driver A cannot populate driver B\'s session',
      () {
        final provider = ShipmentInstantprovider();
        addTearDown(provider.dispose);

        // Driver A's request is captured mid-flight.
        final staleGeneration = provider.stateGeneration;

        // Driver A logs out, driver B signs in.
        UserSessionState.reset(SessionResetReason.logout);

        expect(provider.acceptsState(staleGeneration), isFalse);

        // Driver A's reply lands late and must be refused.
        provider.applyServerPageForTest(
          ShipmentsResponse.fromJson(
            _pageJson(
              shipments: [_shipmentJson(id: 4242)],
              page: 1,
              limit: 5,
              total: 1,
              totalPages: 1,
              driverId: 7,
            ),
          ),
          requestedPage: 1,
          driverId: 7,
          generation: staleGeneration,
        );

        expect(provider.paginatedShipments, isEmpty);
        expect(provider.shipmentInstantResponse, isNull);
        expect(provider.totalCount, 0);
      },
    );

    test('a page fetched in the current session is accepted', () {
      final provider = ShipmentInstantprovider();
      addTearDown(provider.dispose);

      final generation = provider.stateGeneration;
      provider.applyServerPageForTest(
        ShipmentsResponse.fromJson(
          _pageJson(
            shipments: [_shipmentJson(id: 11)],
            page: 1,
            limit: 5,
            total: 1,
            totalPages: 1,
          ),
        ),
        requestedPage: 1,
        driverId: 7,
        generation: generation,
      );

      expect(provider.paginatedShipments.map((s) => s.id), <int>[11]);
    });
  });
}
