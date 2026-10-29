import 'package:blockatie/models/shipment.dart';

/// Presentation-only classification for the Driver App's operational lists.
///
/// The API's action contract is the authority for eligibility. These rules
/// deliberately do not infer availability from a status label: a shipment can
/// be withdrawn, reserved, expired, or reassigned without a client-visible
/// status changing at the same time.
abstract final class DriverShipmentListRules {
  /// Terminal shipment states from the existing driver lifecycle. Status 9 is
  /// deliberately absent: failed delivery can still lead to a return/custody
  /// branch and must be decided by the action contract.
  static const Set<int> _terminalStatusIds = <int>{6, 7, 8, 11};

  static int _statusIdOf(Shipment shipment) =>
      shipment.shipmentStatusId != 0
          ? shipment.shipmentStatusId
          : shipment.shipmentStatus;

  /// An offer belongs in Available only when the API currently authorizes this
  /// driver to claim an unassigned instant shipment.
  static bool isAvailableInstantOffer(Shipment shipment) {
    return shipment.id > 0 &&
        shipment.deliveryTypeId == 1 &&
        shipment.driverId == 0 &&
        !_terminalStatusIds.contains(_statusIdOf(shipment)) &&
        shipment.hasActionContract &&
        shipment.allowsAction('accept_shipment');
  }

  /// A shipment belongs in the current driver's Active work only while the
  /// response still grants an operational action, or explicitly says this
  /// driver retains custody. The latter preserves unresolved return/handover
  /// work without inventing a status-based transition.
  static bool isActiveForCurrentDriver(Shipment shipment, int? driverId) {
    if (driverId == null || driverId <= 0) return false;
    if (shipment.id <= 0 || shipment.driverId != driverId) return false;
    if (!shipment.hasActionContract) return false;

    final custody = shipment.custodyState;
    final heldInCurrentDriverCustody =
        custody?['state']?.toString() == 'driver' &&
        custody?['held_by_current_driver'] == true;
    if (heldInCurrentDriverCustody) return true;

    // A malformed cached contract must not revive a delivered, cancelled or
    // returned card. Current driver custody above remains visible because it
    // is operational work even when the display status is terminal.
    if (_terminalStatusIds.contains(_statusIdOf(shipment))) return false;

    if (shipment.driverActions.any((action) => action.canExecute)) {
      return true;
    }

    return false;
  }
}
