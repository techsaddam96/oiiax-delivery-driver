class LoginResponse {
  final String status;
  final String message;
  final Driver driver;

  LoginResponse({
    required this.status,
    required this.message,
    required this.driver,
  });

  factory LoginResponse.fromJson(Map<String, dynamic> json) {
    final rawDriver = json['data'];
    return LoginResponse(
      status: json['status'] ?? '',
      message: json['message'] ?? '',
      driver: Driver.fromJson(
        rawDriver is Map ? Map<String, dynamic>.from(rawDriver) : const {},
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {'status': status, 'message': message, 'data': driver.toJson()};
  }
}

class Driver {
  final int id;
  final String dname;
  final int dpercent;
  final String dphone;
  final String img;
  final String numcd;
  final String regionsd;
  final String latitude;
  final String longitude;
  final String apiKey;

  Driver({
    required this.id,
    required this.dname,
    required this.dpercent,
    required this.dphone,
    required this.img,
    required this.numcd,
    required this.regionsd,
    required this.latitude,
    required this.longitude,
    required this.apiKey,
  });

  factory Driver.fromJson(Map<String, dynamic> json) {
    return Driver(
      id: _asInt(json['id'] ?? json['driver_id'] ?? json['driverId']),
      dname: json['dname']?.toString() ?? '',
      dpercent: _asInt(json['dpercent']),
      dphone: json['dphone']?.toString() ?? '',
      img: json['img']?.toString() ?? '',
      numcd: json['numcd']?.toString() ?? '',
      regionsd: json['regionsd']?.toString() ?? '',
      latitude: json['latitude']?.toString() ?? '',
      longitude: json['longitude']?.toString() ?? '',
      apiKey: json['api_key']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'dname': dname,
      'dpercent': dpercent,
      'dphone': dphone,
      'img': img,
      'numcd': numcd,
      'regionsd': regionsd,
      'latitude': latitude,
      'longitude': longitude,
      'api_key': apiKey,
    };
  }
}

int _asInt(dynamic value) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
