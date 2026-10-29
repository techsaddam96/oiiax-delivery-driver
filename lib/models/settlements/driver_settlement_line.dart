import 'settlement_parsing.dart';

class DriverSettlementLine {
  const DriverSettlementLine({
    required this.shipmentId,
    required this.shipmentReference,
    required this.shipmentAmount,
    required this.netAmount,
    required this.shipmentStatusId,
    required this.statusNameEn,
    required this.statusNameAr,
    required this.shipmentDate,
  });
  final int shipmentId;
  final String shipmentReference;
  final double shipmentAmount;
  final double netAmount;

  /// The stable status id. The label is resolved in the widget from the one
  /// shared table, so a language switch re-renders it without a request.
  ///
  /// This replaced a single prose string the endpoint picked by request
  /// language. It was the wrong column — a full sentence rather than a status
  /// name — and the app sends no language, so it always arrived in English.
  final int shipmentStatusId;
  final String statusNameEn;
  final String statusNameAr;

  final String shipmentDate;
  factory DriverSettlementLine.fromJson(Map<String, dynamic> json) =>
      DriverSettlementLine(
        shipmentId: settlementInt(json['shipment_id']),
        shipmentReference: settlementText(json['shipment_reference']),
        shipmentAmount: settlementDouble(json['shipment_amount']),
        netAmount: settlementDouble(json['net_amount']),
        shipmentStatusId: settlementInt(json['shipment_status_id']),
        statusNameEn: settlementText(json['status_name_en']),
        statusNameAr: settlementText(json['status_name_ar']),
        shipmentDate: settlementText(json['shipment_date']),
      );
}
