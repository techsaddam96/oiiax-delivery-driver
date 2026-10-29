import 'settlement_parsing.dart';

class DriverSettlement {
  const DriverSettlement({
    required this.settlementId,
    required this.statementNumber,
    required this.periodFrom,
    required this.periodTo,
    required this.netAmount,
    required this.remainingAmount,
    required this.status,
    required this.createdAt,
    required this.paidAt,
    required this.shipmentsCount,
    required this.hasPdf,
  });
  final int settlementId;
  final String statementNumber;
  final String periodFrom;
  final String periodTo;
  final double netAmount;
  final double remainingAmount;
  final String status;
  final String createdAt;
  final String paidAt;
  final int shipmentsCount;
  final bool hasPdf;
  factory DriverSettlement.fromJson(Map<String, dynamic> json) =>
      DriverSettlement(
        settlementId: settlementInt(json['settlement_id']),
        statementNumber: settlementText(json['statement_number']),
        periodFrom: settlementText(json['period_from']),
        periodTo: settlementText(json['period_to']),
        netAmount: settlementDouble(
          json['net_amount'] ?? json['settlement_amount'],
        ),
        remainingAmount: settlementDouble(json['remaining_amount']),
        status: settlementText(json['status']).toLowerCase(),
        createdAt: settlementText(json['created_at']),
        paidAt: settlementText(json['paid_at']),
        shipmentsCount: settlementInt(json['shipments_count']),
        hasPdf: settlementBool(json['has_pdf']),
      );
}
