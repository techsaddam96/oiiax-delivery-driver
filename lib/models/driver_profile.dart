class DriverProfileModel {
  final String status;
  final String message;
  final DriverInfo driver;

  DriverProfileModel({
    required this.status,
    required this.message,
    required this.driver,
  });

  factory DriverProfileModel.fromJson(Map<String, dynamic> json) {
    return DriverProfileModel(
      status: json['status']?.toString() ?? '',
      message: json['message']?.toString() ?? '',
      driver: DriverInfo.fromJson(
        json['profile'] is Map<String, dynamic> ? json['profile'] : const {},
      ),
    );
  }
}

class DriverInfo {
  final int id;
  final String dname;
  final int dpercent;
  final String dphone;
  final String img;
  final String numcd;
  final String latitude;
  final String longitude;
  final int subscription;
  final int status;
  final String createdAt;

  DriverInfo({
    required this.id,
    required this.dname,
    required this.dpercent,
    required this.dphone,
    required this.img,
    required this.numcd,
    required this.latitude,
    required this.longitude,
    required this.subscription,
    required this.status,
    required this.createdAt,
  });

  factory DriverInfo.fromJson(Map<String, dynamic> json) {
    return DriverInfo(
      id: _asInt(json['id']),
      dname: json['dname']?.toString() ?? '',
      dpercent: _asInt(json['dpercent']),
      dphone: json['dphone']?.toString() ?? '',
      img: json['img']?.toString() ?? '',
      numcd: json['numcd']?.toString() ?? '',
      latitude: json['latitude']?.toString() ?? '',
      longitude: json['longitude']?.toString() ?? '',
      subscription: _asInt(json['subscription']),
      status: _asInt(json['status']),
      createdAt: json['created_at']?.toString() ?? '',
    );
  }
}

int _asInt(dynamic value) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
