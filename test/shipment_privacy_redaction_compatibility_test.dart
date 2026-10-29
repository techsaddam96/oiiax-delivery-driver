import 'package:blockatie/models/shipment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a redacted pre-pickup driver response remains a valid Shipment', () {
    final shipment = Shipment.fromJson({
      'id': 7001,
      'policy_num': 'BLK-7001',
      'driver_id': 501,
      'delivery_type_id': 2,
      'shipment_status_id': 10,
      'shipment_status': 10,
      // Pickup/store fields still supplied by the driver API.
      'nstore': 'Demo Store',
      'phclient': '0788888888',
      'lclient': 'Store Street 1',
      'latitude': '31.9550',
      'longitude': '35.9100',
    });

    expect(shipment.nstore, 'Demo Store');
    expect(shipment.phclient, '0788888888');
    expect(shipment.lclient, 'Store Street 1');
    expect(shipment.recipientName, isEmpty);
    expect(shipment.recipientPhone, isEmpty);
    expect(shipment.deliveryAddress, isEmpty);
    expect(shipment.deliveryLatitude, isNull);
    expect(shipment.deliveryLongitude, isNull);
    expect(shipment.shipmentNote, isEmpty);
  });
}
