import 'package:blockatie/models/login.dart';
import 'package:blockatie/models/shipment.dart';
import 'package:blockatie/models/statistics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('login response parses numeric strings and api key', () {
    final response = LoginResponse.fromJson({
      'status': 'success',
      'message': 'ok',
      'data': {
        'id': '42',
        'dname': 'Driver',
        'dpercent': '15',
        'dphone': '0790000000',
        'api_key': 'key',
      },
    });

    expect(response.driver.id, 42);
    expect(response.driver.dpercent, 15);
    expect(response.driver.apiKey, 'key');
  });

  test('shipment response accepts driverId fallback and empty shipments', () {
    final response = ShipmentsResponse.fromJson({
      'status': 'success',
      'message': 'ok',
      'driverId': '7',
      'count': '0',
      'shipments': null,
    });

    expect(response.driverId, 7);
    expect(response.count, 0);
    expect(response.shipments, isEmpty);
  });

  test('driver statistics parses string totals safely', () {
    final response = DriverStatisticsModel.fromJson({
      'success': true,
      'data': {
        'shipments': '3',
        'shipments_in_progress': '1',
        'shipments_delivered': '2',
        'cancelled_shipments': null,
        'total_balance_due_to_the_driver': '12.50',
      },
    });

    expect(response.data.shipments, 3);
    expect(response.data.shipmentsInProgress, 1);
    expect(response.data.shipmentsDelivered, 2);
    expect(response.data.cancelledShipments, 0);
    expect(response.data.totalDriverDue, 12.5);
  });
}
