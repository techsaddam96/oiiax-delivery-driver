import 'package:blockatie/models/settlements/driver_financial_summary.dart';
import 'package:blockatie/models/settlements/driver_performance_summary.dart';
import 'package:blockatie/models/settlements/driver_settlement.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('settlement parsing accepts numeric and string financial values', () {
    final settlement = DriverSettlement.fromJson({
      'settlement_id': '7',
      'statement_number': 'DS-7',
      'net_amount': '125.50',
      'remaining_amount': 0,
      'shipments_count': '3',
      'has_pdf': 1,
    });

    expect(settlement.settlementId, 7);
    expect(settlement.netAmount, 125.50);
    expect(settlement.hasPdf, isTrue);
  });

  test('summary models safely parse empty and zero values', () {
    final financial = DriverFinancialSummary.fromJson(const {});
    final performance = DriverPerformanceSummary.fromJson({
      'average_rating': null,
      'ratings_count': 0,
      'shipments': {'success_rate': '0.0'},
    });

    expect(financial.cashInHand, 0);
    expect(performance.averageRating, 0);
    expect(performance.successRate, 0);
  });
}
