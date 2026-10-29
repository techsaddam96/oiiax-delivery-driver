import 'package:blockatie/models/driver_action.dart';
import 'package:blockatie/models/shipment.dart';
import 'package:blockatie/provider/bottom_nav.dart';
import 'package:blockatie/provider/shipment.dart';
import 'package:blockatie/provider/shipment_instsnt.dart';
import 'package:flutter_test/flutter_test.dart';

class _Assigned extends ShipmentProvider {
  final requested = <String>[];
  @override
  Future<void> getAllShipments({bool force=false,int? page}) async {
    requested.add(shipmentScope);
  }
}
class _Offers extends ShipmentInstantprovider {
  final requested = <String>[];
  @override
  Future<void> getShipmentsInstant({bool force=false,int? page}) async {
    requested.add(shipmentScope);
  }
}

void main() {
  test('Type selection invalidates old requests and asks the server for the whole scope', () async {
    final assigned=_Assigned();final offers=_Offers();
    addTearDown(assigned.dispose);addTearDown(offers.dispose);
    final oldGeneration=assigned.stateGeneration;
    for(final scope in ['instant','scheduled','other']) {
      await assigned.selectShipmentScope(scope);
    }
    expect(assigned.requested,['instant','scheduled','other']);
    expect(assigned.acceptsState(oldGeneration),isFalse);
    await offers.selectShipmentScope('instant');
    await offers.selectShipmentScope('other');
    expect(offers.requested,['instant','other']);
    await assigned.selectShipmentScope('unknown');
    expect(assigned.requested.length,3);
  });

  test('Top-level type navigation and secondary offer notification state remain valid', () {
    final nav=BottomNavProvider();addTearDown(nav.dispose);
    nav.setShipmentsTab(0,offers:true);
    expect(nav.shipmentsTabIndex,0);expect(nav.shipmentsOffers,isTrue);
    nav.setShipmentsTab(1);expect(nav.shipmentsOffers,isFalse);
    nav.setShipmentsTab(2);expect(nav.shipmentsTabIndex,2);
    nav.setShipmentsTab(3);expect(nav.shipmentsTabIndex,2);
    nav.resetUserState();expect(nav.shipmentsTabIndex,0);
  });

  test('Changing shipment state withdraws old capabilities; missing or malformed contracts fail closed', () {
    final row=Shipment.fromJson({'id':17,'driver_id':41,'delivery_type_id':1,'shipment_status_id':4,
      'driver_action_contract_version':1,'driver_actions':[{
        'id':'complete_delivery','target_status_id':11,'enabled':true,'group':'progression',
      }]});
    expect(row.allowsAction('complete_delivery'),isTrue);
    expect(row.copyWith(shipmentStatusId:9).allowsAction('complete_delivery'),isFalse);
    expect(row.copyWith(driverId:42).hasActionContract,isFalse);
    expect(Shipment.fromJson({'shipment_status_id':4}).allowsAction('complete_delivery'),isFalse);
    expect(DriverAction.fromJson({'id':'admin_override','enabled':true,'target_status_id':11,'group':'progression'}).canExecute,isFalse);
    expect(DriverAction.fromJson({'id':'complete_delivery','enabled':true,'target_status_id':6,'group':'progression'}).canExecute,isFalse);
    expect(DriverAction.fromJson({'id':'complete_delivery','enabled':true,'target_status_id':11,'group':'exception'}).canExecute,isFalse);
  });
}
