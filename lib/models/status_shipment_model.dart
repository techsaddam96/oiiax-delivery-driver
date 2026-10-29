class StatusShipmentData {
  late bool success;
  late int count;
  late List<Status> status;

  StatusShipmentData.fromJson(Map<String, dynamic> json) {
    success = json['success'] == true;
    count = _asInt(json['count']);
    status = <Status>[];
    if (json['status'] is List) {
      for (final item in json['status']) {
        if (item is Map<String, dynamic>) {
          status.add(Status.fromJson(item));
        }
      }
    }
  }
}

class Status {
  late int id;
  late String statusNameEn;
  late String statusNameAr;
  late String statusOrder;
  late String typeColor;
  late String messageEn;
  late String messageAr;

  Status.fromJson(Map<String, dynamic> json) {
    id = _asInt(json['id']);
    statusNameEn = json['status_name_en']?.toString() ?? '';
    statusNameAr = json['status_name_ar']?.toString() ?? '';
    statusOrder = json['status_order']?.toString() ?? '';
    typeColor = json['type_color']?.toString() ?? '';
    messageEn = json['message_en']?.toString() ?? '';
    messageAr = json['message_ar']?.toString() ?? '';
  }
}

int _asInt(dynamic value) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
