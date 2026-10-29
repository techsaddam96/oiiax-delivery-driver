class DriverStatisticsModel {
  final bool success;
  final DriverStatisticsData data;

  DriverStatisticsModel({required this.success, required this.data});

  factory DriverStatisticsModel.fromJson(Map<String, dynamic> json) {
    final data = json['data'];
    final rootFallback = Map<String, dynamic>.from(json);
    rootFallback.remove('success');
    rootFallback.remove('status');
    rootFallback.remove('message');
    rootFallback.remove('message_en');
    rootFallback.remove('message_ar');

    return DriverStatisticsModel(
      success: _isSuccess(json['success']) || _isSuccess(json['status']),
      data: DriverStatisticsData.fromJson(
        data is Map ? Map<String, dynamic>.from(data) : rootFallback,
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {'success': success, 'data': data.toJson()};
  }
}

bool _isSuccess(dynamic value) {
  if (value == true) return true;
  final normalized = value?.toString().trim().toLowerCase();
  return normalized == 'true' || normalized == '1' || normalized == 'success';
}

class DriverStatisticsData {
  final int shipments;
  final int shipmentsInProgress;
  final int shipmentsDelivered;
  final int cancelledShipments;
  final double totalUnaccrued;
  final double totalAccrued;
  final double totalShipCost;
  final double totalDriverDue;
  final double totalCancelledUnpaid;

  /// What the backend says the driver may withdraw right now: gross commission
  /// less what pending requests reserve and what completed payouts consumed.
  ///
  /// Null means the server did not say. It is never reconstructed here — the
  /// app has no way to know what has been paid out, and guessing is what let a
  /// paid-out driver keep seeing the full amount.
  final double? availableToWithdraw;

  /// The three parts behind that number. Null means not reported.
  final double? earningsGross;
  final double? earningsReserved;
  final double? earningsPaid;

  /// Commission earned but not yet withdrawable because its delivery fee has
  /// not been collected (prepaid, unpaid cancellation, return).
  double get commissionPending => totalCancelledUnpaid;

  DriverStatisticsData({
    required this.shipments,
    required this.shipmentsInProgress,
    required this.shipmentsDelivered,
    required this.cancelledShipments,
    required this.totalUnaccrued,
    required this.totalAccrued,
    required this.totalShipCost,
    required this.totalDriverDue,
    required this.totalCancelledUnpaid,
    this.availableToWithdraw,
    this.earningsGross,
    this.earningsReserved,
    this.earningsPaid,
  });

  /// True once the server sends the explicit breakdown rather than only the
  /// legacy total.
  bool get hasWithdrawalBreakdown =>
      earningsGross != null && earningsReserved != null && earningsPaid != null;

  factory DriverStatisticsData.fromJson(Map<String, dynamic> json) {
    return DriverStatisticsData(
      shipments: _asInt(json['shipments']),
      shipmentsInProgress: _asInt(json['shipments_in_progress']),
      shipmentsDelivered: _asInt(json['shipments_delivered']),
      cancelledShipments: _asInt(json['cancelled_shipments']),
      totalUnaccrued: _asDouble(json['total_balance_of_shipments_unaccrued']),
      totalAccrued: _asDouble(json['total_balance_of_shipments_accrued']),
      totalShipCost: _asDouble(json['total_ships_cost_all_of_them']),
      totalDriverDue: _asDouble(json['total_balance_due_to_the_driver']),
      totalCancelledUnpaid: _asDouble(
        json['driver_commission_pending'] ??
            json['total_balance_of_cancelled_and_unpaid_shipments'],
      ),
      // The explicit field wins. `total_balance_due_to_the_driver` is only the
      // fallback for a server that predates it, and on the Driver endpoints it
      // now carries the same net figure.
      availableToWithdraw:
          _asOptionalDouble(json['driver_commission_withdrawable']) ??
          _asOptionalDouble(json['driver_available_to_withdraw']) ??
          _asOptionalDouble(json['total_balance_due_to_the_driver']),
      earningsGross: _asOptionalDouble(json['driver_earnings_gross']),
      earningsReserved: _asOptionalDouble(json['driver_earnings_reserved']),
      earningsPaid: _asOptionalDouble(json['driver_earnings_paid']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'shipments': shipments,
      'shipments_in_progress': shipmentsInProgress,
      'shipments_delivered': shipmentsDelivered,
      'cancelled_shipments': cancelledShipments,
      'total_balance_of_shipments_unaccrued': totalUnaccrued,
      'total_balance_of_shipments_accrued': totalAccrued,
      'total_ships_cost_all_of_them': totalShipCost,
      'total_balance_due_to_the_driver': totalDriverDue,
      'total_balance_of_cancelled_and_unpaid_shipments': totalCancelledUnpaid,
      if (availableToWithdraw != null)
        'driver_available_to_withdraw': availableToWithdraw,
      if (earningsGross != null) 'driver_earnings_gross': earningsGross,
      if (earningsReserved != null)
        'driver_earnings_reserved': earningsReserved,
      if (earningsPaid != null) 'driver_earnings_paid': earningsPaid,
    };
  }

  factory DriverStatisticsData.empty() {
    return DriverStatisticsData(
      shipments: 0,
      shipmentsInProgress: 0,
      shipmentsDelivered: 0,
      cancelledShipments: 0,
      totalUnaccrued: 0.0,
      totalAccrued: 0.0,
      totalShipCost: 0.0,
      totalDriverDue: 0.0,
      totalCancelledUnpaid: 0.0,
      // Deliberately null, not zero: this stands in for a failed read, and a
      // withdrawal must not be offered against an amount nobody confirmed.
    );
  }

  static int _asInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static double _asDouble(dynamic value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  /// Null when the key is absent or unparseable, so "not reported" and
  /// "reported as zero" stay different answers.
  static double? _asOptionalDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return double.tryParse(value.toString().trim());
  }
}
