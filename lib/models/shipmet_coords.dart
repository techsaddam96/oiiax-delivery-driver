class ShipmentCordinatesResponse {
  final bool success;
  final ShipmentData data;

  ShipmentCordinatesResponse({required this.success, required this.data});

  factory ShipmentCordinatesResponse.fromJson(Map<String, dynamic> json) {
    return ShipmentCordinatesResponse(
      success: json['success'] ?? false,
      data: ShipmentData.fromJson(
        json['data'] is Map<String, dynamic> ? json['data'] : const {},
      ),
    );
  }
}

class ShipmentData {
  final int shipmentId;
  final String recipientName;
  final String recipientPhone;
  final String deliveryAddress;
  final int storeId;
  final int driverId;
  final String driverPhone;
  final String latitude;
  final String longitude;

  ShipmentData({
    required this.shipmentId,
    required this.recipientName,
    required this.recipientPhone,
    required this.deliveryAddress,
    required this.storeId,
    required this.driverId,
    required this.driverPhone,
    required this.latitude,
    required this.longitude,
  });

  factory ShipmentData.fromJson(Map<String, dynamic> json) {
    return ShipmentData(
      shipmentId: _asInt(json['shipment_id']),
      recipientName: json['recipient_name']?.toString() ?? '',
      recipientPhone: json['recipient_phone']?.toString() ?? '',
      deliveryAddress: json['delivery_address']?.toString() ?? '',
      storeId: _asInt(json['store_id']),
      driverId: _asInt(json['driver_id']),
      driverPhone: json['driver_phone']?.toString() ?? '',
      latitude: json['latitude']?.toString() ?? '',
      longitude: json['longitude']?.toString() ?? '',
    );
  }
}

int _asInt(dynamic value) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
