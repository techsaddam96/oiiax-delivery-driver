/// The driver's side of one shipment's money, exactly as the server computed
/// it. Display only: the app never recomputes these amounts or sends them back
/// as authority (a door fee the driver enters is re-validated by the server).
///
/// Older shipments (before the financial model) carry only [productToCollect];
/// every fee figure is null and the UI hides it.
class DriverShipmentFinancial {
  final String paymentType;
  final double productToCollect;
  final double? feeDue;
  final double? feeCollected;
  final double? feeRemaining;
  final String? collectionStatus;
  final double? driverCommission;
  final double? driverCommissionWithdrawable;
  final double? driverCashToRemit;

  /// The most the server accepts as a delivery fee taken at the door if the
  /// parcel comes back now (return, or a customer/merchant cancel after the
  /// driver left). 0 when there is nothing to collect.
  final double doorFeeCollectable;

  const DriverShipmentFinancial({
    required this.paymentType,
    required this.productToCollect,
    this.feeDue,
    this.feeCollected,
    this.feeRemaining,
    this.collectionStatus,
    this.driverCommission,
    this.driverCommissionWithdrawable,
    this.driverCashToRemit,
    this.doorFeeCollectable = 0,
  });

  bool get isPrepaid => paymentType == 'prepaid';

  /// True when the server tracks this shipment's fee (not a legacy row).
  bool get isTracked => feeDue != null;

  static DriverShipmentFinancial? tryParse(dynamic json) {
    if (json is! Map) {
      return null;
    }
    final map = Map<String, dynamic>.from(json);
    return DriverShipmentFinancial(
      paymentType: map['payment_type'] == 'prepaid' ? 'prepaid' : 'cod',
      productToCollect: financialMoney(map['product_to_collect']) ?? 0,
      feeDue: financialMoney(map['fee_due']),
      feeCollected: financialMoney(map['fee_collected']),
      feeRemaining: financialMoney(map['fee_remaining']),
      collectionStatus: map['collection_status']?.toString(),
      driverCommission: financialMoney(map['driver_commission']),
      driverCommissionWithdrawable:
          financialMoney(map['driver_commission_withdrawable']),
      driverCashToRemit: financialMoney(map['driver_cash_to_remit']),
      doorFeeCollectable: financialMoney(map['door_fee_collectable']) ?? 0,
    );
  }
}

/// Parses a server money value (number or numeric string); null when absent.
double? financialMoney(dynamic value) {
  if (value == null) {
    return null;
  }
  if (value is num) {
    return value.toDouble();
  }
  return double.tryParse(value.toString());
}
