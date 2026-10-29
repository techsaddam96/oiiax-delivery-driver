import 'package:blockatie/services/user_session_state.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:blockatie/constants/app_urls.dart';
import 'package:blockatie/models/shipment.dart';
import 'package:blockatie/services/auth_services.dart';
import 'package:blockatie/services/session_dio.dart';
import 'package:dio/dio.dart';

class DriverActionService {
  DriverActionService({Future<Shipment?> Function(int)? loader}) : _loader = loader;
  final Future<Shipment?> Function(int)? _loader;
  static DriverActionService read(BuildContext context) {
    try { return context.read<DriverActionService>(); }
    on ProviderNotFoundException { return DriverActionService(); }
  }
  Future<Shipment?> fetch(int shipmentId) async {
    final loader = _loader;
    if (loader != null) return loader(shipmentId);
    final generation = UserSessionState.generation;
    final key = await AuthService.getApiKey();
    if (!UserSessionState.isCurrent(generation)) return null;
    if (key == null || key.isEmpty) return null;
    try {
      final response = await sessionDio().post(
        '${AppUrls.baseUrl}/api_driver_shipment_actions.php',
        data: {'shipment_id': shipmentId},
        options: Options(headers: {'X-API-KEY': key,
          'Content-Type': 'application/x-www-form-urlencoded'}),
      );
      if (!UserSessionState.isCurrent(generation)) return null;
      final data = response.data;
      if (data is! Map || data['success'] != true || data['shipment'] is! Map) return null;
      return Shipment.fromJson(Map<String, dynamic>.from(data['shipment']));
    } catch (_) { return null; }
  }
}
