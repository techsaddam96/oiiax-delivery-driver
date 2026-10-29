// models/client_model.dart
class ClientModel {
  final String id;
  final String nclient;
  final String nstore;
  final String? loshop;
  final String subscription;
  final String status;

  ClientModel({
    required this.id,
    required this.nclient,
    required this.nstore,
    this.loshop,
    required this.subscription,
    required this.status,
  });

  factory ClientModel.fromJson(Map<String, dynamic> json) {
    return ClientModel(
      id: json['id'],
      nclient: json['nclient'],
      nstore: json['nstore'],
      loshop: json['loshop'],
      subscription: json['subscription'],
      status: json['status'],
    );
  }
}

class ClientListResponse {
  final bool success;
  final int count;
  final List<ClientModel> clients;

  ClientListResponse({
    required this.success,
    required this.count,
    required this.clients,
  });

  factory ClientListResponse.fromJson(Map<String, dynamic> json) {
    return ClientListResponse(
      success: json['success'],
      count: json['count'],
      clients:
          (json['clients'] as List)
              .map((e) => ClientModel.fromJson(e))
              .toList(),
    );
  }
}
