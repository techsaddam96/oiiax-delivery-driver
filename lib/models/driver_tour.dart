import 'package:blockatie/utils/time/jordan_time.dart';

/// Transport-safe driver-tour models.
///
/// These model only the fields exposed by `modules/driver_tours/api/driver_tours.php`.
/// In particular, a stop drops recipient fields unless the server has confirmed
/// that this driver has accepted the tour; callers must not infer visibility
/// from a tour state alone.
enum DriverTourState {
  ready,
  active,
  interrupted,
  completed,
  cancelled,
  superseded;

  static DriverTourState fromWire(Object? value) {
    return switch (value?.toString()) {
      'ready' => DriverTourState.ready,
      'active' => DriverTourState.active,
      'interrupted' => DriverTourState.interrupted,
      'completed' => DriverTourState.completed,
      'cancelled' => DriverTourState.cancelled,
      'superseded' => DriverTourState.superseded,
      _ => throw const DriverTourContractException('INVALID_TOUR_STATE'),
    };
  }

  String get wireName => name;
}

enum DriverTourStopState {
  pending,
  inProgress,
  delivered,
  cancelled,
  failed,
  returned,
  unattempted,
  replanned;

  static DriverTourStopState fromWire(Object? value) {
    return switch (value?.toString()) {
      'pending' => DriverTourStopState.pending,
      'in_progress' => DriverTourStopState.inProgress,
      'delivered' => DriverTourStopState.delivered,
      'cancelled' => DriverTourStopState.cancelled,
      'failed' => DriverTourStopState.failed,
      'returned' => DriverTourStopState.returned,
      'unattempted' => DriverTourStopState.unattempted,
      'replanned' => DriverTourStopState.replanned,
      _ => throw const DriverTourContractException('INVALID_STOP_STATE'),
    };
  }

  String get wireName => switch (this) {
    DriverTourStopState.inProgress => 'in_progress',
    _ => name,
  };
}

class DriverTourContractException implements Exception {
  const DriverTourContractException(this.code);

  final String code;

  @override
  String toString() => 'DriverTourContractException($code)';
}

class DriverTour {
  const DriverTour({
    required this.id,
    required this.state,
    required this.stateVersion,
    required this.plannedStopCount,
    required this.requiresExplicitStart,
    this.startedAt,
    this.interruptedAt,
    this.completedAt,
  });

  final int id;
  final DriverTourState state;
  final int stateVersion;
  final int plannedStopCount;
  final bool requiresExplicitStart;
  final DateTime? startedAt;
  final DateTime? interruptedAt;
  final DateTime? completedAt;

  factory DriverTour.fromJson(Map<String, dynamic> json) {
    final id = _positiveInt(json['tour_id']);
    final version = _positiveInt(json['state_version']);
    if (id == null || version == null) {
      throw const DriverTourContractException('INVALID_TOUR');
    }
    final count = _nonNegativeInt(json['planned_stop_count']);
    if (count == null) throw const DriverTourContractException('INVALID_TOUR');
    return DriverTour(
      id: id,
      state: DriverTourState.fromWire(json['tour_state']),
      stateVersion: version,
      plannedStopCount: count,
      requiresExplicitStart: json['requires_explicit_start'] == true,
      startedAt: _date(json['started_at_utc'] ?? json['started_at']),
      interruptedAt: _date(json['interrupted_at_utc'] ?? json['interrupted_at']),
      completedAt: _date(json['completed_at_utc'] ?? json['completed_at']),
    );
  }
}

class DriverTourSummary {
  const DriverTourSummary({
    required this.plannedStopCount,
    required this.snapshotStopCount,
    required this.outcomeStopCount,
    required this.remainingStopCount,
    required this.canComplete,
  });

  final int plannedStopCount;
  final int snapshotStopCount;
  final int outcomeStopCount;
  final int remainingStopCount;
  final bool canComplete;

  factory DriverTourSummary.fromJson(Map<String, dynamic> json) {
    final planned = _nonNegativeInt(json['planned_stop_count']);
    final snapshot = _nonNegativeInt(json['snapshot_stop_count']);
    final outcomes = _nonNegativeInt(json['outcome_stop_count']);
    final remaining = _nonNegativeInt(json['remaining_stop_count']);
    if (planned == null ||
        snapshot == null ||
        outcomes == null ||
        remaining == null) {
      throw const DriverTourContractException('INVALID_TOUR_SUMMARY');
    }
    return DriverTourSummary(
      plannedStopCount: planned,
      snapshotStopCount: snapshot,
      outcomeStopCount: outcomes,
      remainingStopCount: remaining,
      canComplete: json['can_complete'] == true,
    );
  }
}

class DriverTourStop {
  const DriverTourStop({
    required this.id,
    required this.shipmentId,
    required this.order,
    required this.state,
    required this.driverHasAccepted,
    this.policyNumber,
  });

  final int id;
  final int shipmentId;
  final int order;
  final DriverTourStopState state;
  final bool driverHasAccepted;

  /// Available only after the server confirms tour acceptance. Recipient
  /// fields are intentionally not modelled here; the app must use the existing
  /// shipment workflow for any authorized details.
  final String? policyNumber;

  factory DriverTourStop.fromJson(Map<String, dynamic> json) {
    final id = _positiveInt(json['stop_id']);
    final shipmentId = _positiveInt(json['shipment_id']);
    final order = _positiveInt(json['stop_order']);
    if (id == null || shipmentId == null || order == null) {
      throw const DriverTourContractException('INVALID_TOUR_STOP');
    }
    final accepted = json['driver_has_accepted'] == true;
    return DriverTourStop(
      id: id,
      shipmentId: shipmentId,
      order: order,
      state: DriverTourStopState.fromWire(json['stop_state']),
      driverHasAccepted: accepted,
      // Deliberately ignore policy/customer fields unless the server provided
      // explicit acceptance evidence on this exact stop response.
      policyNumber: accepted ? _nullableString(json['policy_num']) : null,
    );
  }
}

class DriverTourDetails {
  const DriverTourDetails({
    required this.tour,
    required this.summary,
    required this.stops,
  });

  final DriverTour tour;
  final DriverTourSummary summary;
  final List<DriverTourStop> stops;

  factory DriverTourDetails.fromJson(Map<String, dynamic> json) {
    final tour = _map(json['tour']);
    final summary = _map(json['summary']);
    final rawStops = json['stops'];
    if (tour == null || summary == null || rawStops is! List) {
      throw const DriverTourContractException('INVALID_TOUR_DETAILS');
    }
    final stops = rawStops
      .map((row) => _map(row))
      .map((row) {
        if (row == null) {
          throw const DriverTourContractException('INVALID_TOUR_STOP');
        }
        return DriverTourStop.fromJson(row);
      })
      .toList(growable: false)..sort((a, b) => a.order.compareTo(b.order));
    return DriverTourDetails(
      tour: DriverTour.fromJson(tour),
      summary: DriverTourSummary.fromJson(summary),
      stops: stops,
    );
  }
}

class DriverTourCommandResult {
  const DriverTourCommandResult({
    required this.tourId,
    required this.state,
    required this.idempotent,
  });

  final int tourId;
  final DriverTourState state;
  final bool idempotent;

  factory DriverTourCommandResult.fromJson(Map<String, dynamic> json) {
    final tourId = _positiveInt(json['tour_id']);
    if (tourId == null) {
      throw const DriverTourContractException('INVALID_TOUR_COMMAND_RESULT');
    }
    return DriverTourCommandResult(
      tourId: tourId,
      state: DriverTourState.fromWire(json['state']),
      idempotent: json['idempotent'] == true,
    );
  }
}

Map<String, dynamic>? _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : null;

int? _positiveInt(Object? value) {
  final parsed = _nonNegativeInt(value);
  return parsed != null && parsed > 0 ? parsed : null;
}

int? _nonNegativeInt(Object? value) {
  if (value is int) return value >= 0 ? value : null;
  if (value is String) {
    final parsed = int.tryParse(value);
    return parsed != null && parsed >= 0 ? parsed : null;
  }
  return null;
}

String? _nullableString(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

DateTime? _date(Object? value) {
  final text = _nullableString(value);
  if (text == null || text.startsWith('0000-00-00')) return null;
  // Lifecycle columns are written by DriverTourLifecycleService::now() in UTC
  // but the legacy driver route returns the raw DATETIME without an offset.
  return JordanTime.parse(text, assumeUtcWithoutTimezone: true);
}
