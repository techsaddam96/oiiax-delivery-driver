class DriverRating {
  final int driverId;
  final String driverName;
  final String driverImage;
  final int reviewsCount;
  final double avgRating;

  DriverRating({
    required this.driverId,
    required this.driverName,
    required this.driverImage,
    required this.reviewsCount,
    required this.avgRating,
  });

  factory DriverRating.fromJson(Map<String, dynamic> json) {
    return DriverRating(
      driverId: _asInt(json['driver_id']),
      driverName: json['driver_name']?.toString() ?? '',
      driverImage: json['driver_image']?.toString() ?? '',
      reviewsCount: _asInt(json['reviews_count']),
      avgRating: _asDouble(json['avg_rating']),
    );
  }
}

int _asInt(dynamic value) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

double _asDouble(dynamic value) {
  if (value is double) return value;
  if (value is int) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0.0;
}
