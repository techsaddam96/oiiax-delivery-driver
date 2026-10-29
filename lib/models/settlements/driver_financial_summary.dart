import 'settlement_parsing.dart';

class DriverFinancialSummary {
  const DriverFinancialSummary({
    required this.cashInHand,
    required this.settledTotal,
    required this.openSettlementsTotal,
    required this.deliveredUnsettledShipmentsCount,
  });
  /// Cash the driver must hand over: COD plus any delivery fee taken at the door.
  final double cashInHand;
  final double settledTotal;
  final double openSettlementsTotal;
  final int deliveredUnsettledShipmentsCount;
  factory DriverFinancialSummary.fromJson(Map<String, dynamic> json) =>
      DriverFinancialSummary(
        cashInHand: settlementDouble(
          json['driver_cash_to_remit'] ?? json['cash_in_hand'],
        ),
        settledTotal: settlementDouble(json['settled_total']),
        openSettlementsTotal: settlementDouble(json['open_settlements_total']),
        deliveredUnsettledShipmentsCount: settlementInt(
          json['delivered_unsettled_shipments_count'],
        ),
      );
}
