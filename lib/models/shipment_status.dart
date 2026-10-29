class ShipmentStatusResponse {
  final String status;
  final String message;
  final ShipmentStatus shipmentStatus;

  ShipmentStatusResponse({
    required this.status,
    required this.message,
    required this.shipmentStatus,
  });

  factory ShipmentStatusResponse.fromJson(Map<String, dynamic> json) {
    return ShipmentStatusResponse(
      status: json['status']?.toString() ?? '',
      message: json['message']?.toString() ?? '',
      shipmentStatus: ShipmentStatus.fromJson(
        json['shipment_status'] is Map<String, dynamic>
            ? json['shipment_status']
            : const {},
      ),
    );
  }
}

class ShipmentStatus {
  final int shipmentId;
  final String statusNameEn;
  final String statusNameAr;
  final String typeColor;
  final String messageEn;
  final String messageAr;

  ShipmentStatus({
    required this.shipmentId,
    required this.statusNameEn,
    required this.statusNameAr,
    required this.typeColor,
    required this.messageEn,
    required this.messageAr,
  });

  factory ShipmentStatus.fromJson(Map<String, dynamic> json) {
    return ShipmentStatus(
      shipmentId: _asInt(json['shipment_id']),
      statusNameEn: json['status_name_en']?.toString() ?? '',
      statusNameAr: json['status_name_ar']?.toString() ?? '',
      typeColor: json['type_color']?.toString() ?? '',
      messageEn: json['message_en']?.toString() ?? '',
      messageAr: json['message_ar']?.toString() ?? '',
    );
  }
}

int _asInt(dynamic value) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
