import 'driver_settlement.dart';
import 'driver_settlement_line.dart';
import 'settlement_pagination.dart';

class DriverSettlementDetails {
  const DriverSettlementDetails({
    required this.settlement,
    required this.lines,
    required this.pagination,
  });
  final DriverSettlement settlement;
  final List<DriverSettlementLine> lines;
  final SettlementPagination pagination;
  factory DriverSettlementDetails.fromJson(Map<String, dynamic> json) {
    final rawLines = json['lines'] is List ? json['lines'] as List : const [];
    return DriverSettlementDetails(
      settlement: DriverSettlement.fromJson(
        Map<String, dynamic>.from(json['settlement'] as Map? ?? const {}),
      ),
      lines: rawLines
          .whereType<Map>()
          .map(
            (item) =>
                DriverSettlementLine.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(growable: false),
      pagination: SettlementPagination.fromJson(
        json['pagination'] is Map
            ? Map<String, dynamic>.from(json['pagination'] as Map)
            : null,
      ),
    );
  }
}
