import 'settlement_parsing.dart';

class DriverPerformanceSummary {
  const DriverPerformanceSummary({
    required this.averageRating,
    required this.ratingsCount,
    required this.deliveredShipments,
    required this.failedShipments,
    required this.returnedShipments,
    required this.totalShipments,
    required this.successRate,
  });
  final double averageRating;
  final int ratingsCount;
  final int deliveredShipments;
  final int failedShipments;
  final int returnedShipments;
  final int totalShipments;
  final double successRate;
  factory DriverPerformanceSummary.fromJson(Map<String, dynamic> json) {
    final shipments =
        json['shipments'] is Map
            ? Map<String, dynamic>.from(json['shipments'] as Map)
            : <String, dynamic>{};
    return DriverPerformanceSummary(
      averageRating: settlementDouble(json['average_rating']),
      ratingsCount: settlementInt(json['ratings_count']),
      deliveredShipments: settlementInt(shipments['delivered']),
      failedShipments: settlementInt(shipments['failed']),
      returnedShipments: settlementInt(shipments['returned']),
      totalShipments: settlementInt(shipments['total']),
      successRate: settlementDouble(shipments['success_rate']),
    );
  }
}
