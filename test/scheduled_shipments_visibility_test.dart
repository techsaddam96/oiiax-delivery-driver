import 'dart:collection';
import 'dart:convert';

import 'package:blockatie/models/shipment_flow_config.dart';
import 'package:blockatie/provider/bottom_nav.dart';
import 'package:blockatie/provider/shipment_flow_config.dart';
import 'package:blockatie/services/shipment_flow_config_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

ShipmentFlowConfig flowConfig(
  String policyState, {
  String resolution = 'central_policy',
}) {
  return ShipmentFlowConfig.fromJson({
    'data': {
      'feature_policies': {
        'scheduled_shipments': {
          'policy_state': policyState,
          'resolution': resolution,
          'policy_version': 8,
          'assigned_access': 'preserved',
        },
      },
    },
  });
}

class _QueuedFlowConfigService extends ShipmentFlowConfigService {
  _QueuedFlowConfigService(Iterable<Object> outcomes)
    : _outcomes = Queue<Object>.of(outcomes),
      super(dio: Dio());

  final Queue<Object> _outcomes;

  @override
  Future<ShipmentFlowConfig> fetchConfig() async {
    final outcome = _outcomes.removeFirst();
    if (outcome is Exception) throw outcome;
    return outcome as ShipmentFlowConfig;
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test(
    'central ON, OFF, missing and unavailable map to safe visible scopes',
    () {
      expect(flowConfig('enabled').visibleShipmentScopes, [
        'instant',
        'scheduled',
        'other',
      ]);
      expect(flowConfig('disabled').visibleShipmentScopes, [
        'instant',
        'other',
      ]);
      expect(flowConfig('hidden').visibleShipmentScopes, ['instant', 'other']);
      expect(
        flowConfig(
          'missing',
          resolution: 'missing_policy',
        ).visibleShipmentScopes,
        ['instant', 'scheduled', 'other'],
      );
      expect(
        flowConfig(
          'unavailable',
          resolution: 'sync_unavailable',
        ).visibleShipmentScopes,
        ['instant', 'scheduled', 'other'],
      );
    },
  );

  test('an offline restart retains this driver\'s cached Admin OFF policy', () async {
    SharedPreferences.setMockInitialValues({
      'driver_scheduled_shipments_policy_v1.42': jsonEncode(
        flowConfig('disabled').scheduledShipments.toCacheJson(),
      ),
    });
    final provider = ShipmentFlowConfigProvider(
      service: _QueuedFlowConfigService([
        const ShipmentFlowConfigException('temporary transport failure'),
      ]),
    );
    addTearDown(provider.dispose);

    await provider.restoreCachedScheduledPolicy('42');
    await provider.fetch(force: true);

    expect(provider.config.scheduledShipments.isVisible, isFalse);
    expect(provider.lastFetchFailed, isTrue);
  });

  test('selected Scheduled tab safely resets when Admin turns it OFF', () {
    final nav = BottomNavProvider();
    addTearDown(nav.dispose);

    nav.setShipmentsTabScope('scheduled', offers: true);
    nav.reconcileShipmentTabScopes(
      flowConfig('disabled').visibleShipmentScopes,
    );

    expect(nav.shipmentsTabScope, 'instant');
    expect(nav.shipmentsOffers, isFalse);
  });

  test(
    'OFF to ON refresh restores Scheduled and preserves an OFF cache on failure',
    () async {
      final provider = ShipmentFlowConfigProvider(
        service: _QueuedFlowConfigService([
          flowConfig('disabled'),
          flowConfig('enabled'),
          const ShipmentFlowConfigException('temporary transport failure'),
        ]),
      );
      addTearDown(provider.dispose);

      await provider.fetch();
      expect(provider.config.scheduledShipments.isVisible, isFalse);

      await provider.fetch(force: true);
      expect(provider.config.scheduledShipments.isVisible, isTrue);

      await provider.fetch(force: true);
      expect(provider.config.scheduledShipments.isVisible, isTrue);
      expect(provider.lastFetchFailed, isTrue);
    },
  );

  test(
    'a failed refresh never replaces a successful Admin OFF policy',
    () async {
      final provider = ShipmentFlowConfigProvider(
        service: _QueuedFlowConfigService([
          flowConfig('disabled'),
          const ShipmentFlowConfigException('temporary transport failure'),
        ]),
      );
      addTearDown(provider.dispose);

      await provider.fetch();
      await provider.fetch(force: true);

      expect(provider.config.scheduledShipments.isVisible, isFalse);
      expect(provider.lastFetchFailed, isTrue);
    },
  );
}
