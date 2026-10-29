import 'package:blockatie/constants/app_urls.dart';
import 'package:blockatie/models/shipment_flow_config.dart';
import 'package:blockatie/services/auth_services.dart';
import 'package:dio/dio.dart';

import 'session_dio.dart';

class ShipmentFlowConfigService {
  ShipmentFlowConfigService({Dio? dio})
    : _dio = protectSessionDio(dio ?? Dio());

  final Dio _dio;

  Future<ShipmentFlowConfig> fetchConfig() async {
    final driverId = await AuthService.getuserId();
    final apiKey = await AuthService.getApiKey();

    if (driverId == null ||
        driverId.trim().isEmpty ||
        apiKey == null ||
        apiKey.trim().isEmpty) {
      throw const ShipmentFlowConfigException('Missing driver session');
    }

    final response = await _dio.post(
      AppUrls.driverShipmentFlowConfig,
      options: Options(
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'X-API-KEY': apiKey,
        },
      ),
      data: {'driver_id': driverId},
    );

    final data = response.data;
    if (response.statusCode == 200 && data is Map && _isSuccess(data)) {
      return ShipmentFlowConfig.fromJson(Map<String, dynamic>.from(data));
    }

    throw const ShipmentFlowConfigException('Unable to load flow config');
  }

  bool _isSuccess(Map<dynamic, dynamic> data) {
    final success = data['success']?.toString().toLowerCase();
    final status = data['status']?.toString().toLowerCase();
    return data['success'] == true ||
        success == 'true' ||
        success == '1' ||
        status == 'success';
  }
}

class ShipmentFlowConfigException implements Exception {
  const ShipmentFlowConfigException(this.message);

  final String message;

  @override
  String toString() => message;
}
