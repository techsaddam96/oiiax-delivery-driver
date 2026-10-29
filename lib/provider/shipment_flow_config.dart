import 'dart:convert';
import 'dart:developer';

import 'package:blockatie/models/shipment_flow_config.dart';
import 'package:blockatie/services/auth_services.dart';
import 'package:blockatie/services/shipment_flow_config_service.dart';
import 'package:blockatie/services/user_session_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ShipmentFlowConfigProvider extends UserScopedNotifier {
  ShipmentFlowConfigProvider({ShipmentFlowConfigService? service})
    : _service = service ?? ShipmentFlowConfigService();

  final ShipmentFlowConfigService _service;

  ShipmentFlowConfig _config = ShipmentFlowConfig.fallback();
  bool _isLoading = false;
  bool _hasLoadedRemote = false;
  bool _hasCachedPolicy = false;
  bool _lastFetchFailed = false;
  String? _errorMessage;

  static const _scheduledPolicyCachePrefix =
      'driver_scheduled_shipments_policy_v1.';

  // The config is fetched with driver credentials, so the next driver must
  // re-fetch it rather than inherit the previous driver's copy.
  @override
  void clearUserState() {
    _config = ShipmentFlowConfig.fallback();
    _isLoading = false;
    _hasLoadedRemote = false;
    _hasCachedPolicy = false;
    _lastFetchFailed = false;
    _errorMessage = null;
  }

  ShipmentFlowConfig get config => _config;
  bool get isLoading => _isLoading;
  bool get hasLoadedRemote => _hasLoadedRemote;
  bool get isFallback => !_hasLoadedRemote && !_hasCachedPolicy;
  bool get lastFetchFailed => _lastFetchFailed;
  String? get errorMessage => _errorMessage;
  ShipmentPrivacyProfile get beforeAcceptPrivacy =>
      _config.privacyRules.beforeAccept;
  ShipmentPrivacyProfile get afterAcceptPrivacy =>
      _config.privacyRules.afterAccept;

  /// Restores only a policy already resolved by the backend for [driverId].
  /// It is intentionally keyed to the driver so account A can never lend its
  /// Scheduled visibility to account B. The next authenticated fetch remains
  /// authoritative and replaces this cached value when it succeeds.
  Future<void> restoreCachedScheduledPolicy(String driverId) async {
    final normalizedDriverId = driverId.trim();
    if (normalizedDriverId.isEmpty || _hasLoadedRemote) return;

    final generation = stateGeneration;
    try {
      final preferences = await SharedPreferences.getInstance();
      final raw = preferences.getString(_cacheKey(normalizedDriverId));
      if (raw == null || !acceptsState(generation)) return;

      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final visibility = ScheduledShipmentsVisibility.fromJson(
        Map<String, dynamic>.from(decoded),
      );

      // `unavailable` is never a decision to cache or replay: it merely says
      // that Central Control could not be reached at the time of the response.
      if (visibility.policyState == 'unavailable') return;

      _config = _config.withScheduledShipments(visibility);
      _hasCachedPolicy = true;
      notifyListeners();
    } catch (e) {
      // A malformed/stale local value must not affect an authenticated flow.
      log('Scheduled shipment policy cache unavailable: ${e.runtimeType}');
    }
  }

  Future<void> fetch({bool force = false}) async {
    if (_isLoading) return;
    if (_hasLoadedRemote && !force) return;

    final generation = stateGeneration;
    _isLoading = true;
    _lastFetchFailed = false;
    _errorMessage = null;
    notifyListeners();

    try {
      final config = await guardSession(_service.fetchConfig(), generation);
      if (!acceptsState(generation)) return;
      _config = config;
      _hasLoadedRemote = true;
      _hasCachedPolicy = false;
      await _persistResolvedScheduledPolicy(config, generation);
    } catch (e) {
      if (!acceptsState(generation)) return;
      // A failed refresh is not proof an Admin hid the module. Preserve the
      // last successfully resolved policy (including OFF) when one exists.
      if (!_hasLoadedRemote && !_hasCachedPolicy) {
        _config = ShipmentFlowConfig.fallback();
      }
      _lastFetchFailed = true;
      _errorMessage = _hasCachedPolicy
          ? 'Using cached shipment flow config'
          : 'Using fallback shipment flow config';
      log('Shipment flow config fallback: ${e.runtimeType}');
    } finally {
      if (acceptsState(generation)) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> _persistResolvedScheduledPolicy(
    ShipmentFlowConfig config,
    int generation,
  ) async {
    final visibility = config.scheduledShipments;
    if (visibility.policyState == 'unavailable') return;

    try {
      final driverId = (await AuthService.getSessionSnapshot()).driverId?.trim();
      if (driverId == null || driverId.isEmpty || !acceptsState(generation)) {
        return;
      }
      final preferences = await SharedPreferences.getInstance();
      if (!acceptsState(generation)) return;
      await preferences.setString(
        _cacheKey(driverId),
        jsonEncode(visibility.toCacheJson()),
      );
    } catch (e) {
      // The remote result is still valid even if local persistence is not.
      log('Scheduled shipment policy cache write failed: ${e.runtimeType}');
    }
  }

  String _cacheKey(String driverId) =>
      '$_scheduledPolicyCachePrefix${Uri.encodeComponent(driverId)}';

  String statusLabelFor({
    required int statusId,
    required String languageCode,
    required String fallback,
  }) {
    for (final status in _config.statuses) {
      if (status.id == statusId) {
        final value = languageCode == 'ar' ? status.nameAr : status.nameEn;
        if (value.trim().isNotEmpty) return value;
      }
    }
    return fallback;
  }

  String actionLabelFor({
    required String actionKey,
    required String languageCode,
    required String fallback,
  }) {
    for (final action in _config.actions) {
      if (action.actionKey == actionKey) {
        final value = languageCode == 'ar' ? action.labelAr : action.labelEn;
        if (value.trim().isNotEmpty) return value;
      }
    }
    return fallback;
  }
}
