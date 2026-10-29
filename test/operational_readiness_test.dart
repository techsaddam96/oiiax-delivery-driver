import 'dart:async';

import 'package:blockatie/provider/operational_readiness.dart';
import 'package:blockatie/provider/shipment_instsnt.dart';
import 'package:blockatie/views/widgets/operational_guard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

class _FakePlatform implements OperationalPlatformBridge {
  final vpnController = StreamController<bool>.broadcast();
  final launchController = StreamController<void>.broadcast();
  bool vpn = false;
  bool pendingLaunch = false;
  int showCalls = 0;
  int hideCalls = 0;
  int monitorStarts = 0;
  int monitorStops = 0;
  LocationOffNotificationResult notificationResult =
      LocationOffNotificationResult.posted;

  @override
  Stream<bool> get vpnChanges => vpnController.stream;
  @override
  Stream<void> get locationLaunchRequests => launchController.stream;
  @override
  Future<bool> consumePendingLocationLaunch() async => pendingLaunch;
  @override
  Future<bool> currentVpnState() async => vpn;
  @override
  Future<LocationOffNotificationResult> showLocationOffNotification({
    required bool isArabic,
  }) async {
    showCalls++;
    return notificationResult;
  }

  @override
  Future<void> hideLocationOffNotification() async {
    hideCalls++;
  }

  @override
  Future<void> startLocationReadinessMonitor({required bool isArabic}) async {
    monitorStarts++;
  }

  @override
  Future<void> stopLocationReadinessMonitor() async {
    monitorStops++;
  }
}

class _FakeLocation implements LocationReadinessBridge {
  final serviceController = StreamController<ServiceStatus>.broadcast();
  bool enabled = true;
  LocationPermission permission = LocationPermission.whileInUse;
  int locationSettingsCalls = 0;
  int appSettingsCalls = 0;
  int permissionCalls = 0;

  @override
  Stream<ServiceStatus> get serviceChanges => serviceController.stream;
  @override
  Future<LocationPermission> checkPermission() async => permission;
  @override
  Future<bool> isServiceEnabled() async => enabled;
  @override
  Future<bool> openAppSettings() async {
    appSettingsCalls++;
    return true;
  }

  @override
  Future<bool> openLocationSettings() async {
    locationSettingsCalls++;
    return true;
  }

  @override
  Future<LocationPermission> requestPermission() async {
    permissionCalls++;
    return permission;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('GPS transitions de-duplicate the ongoing notification', () async {
    final platform = _FakePlatform();
    final location = _FakeLocation();
    final provider = OperationalReadinessProvider(
      platform: platform,
      location: location,
    );
    addTearDown(() async {
      provider.dispose();
      await platform.vpnController.close();
      await platform.launchController.close();
      await location.serviceController.close();
    });

    provider.applyTestState(
      serviceEnabled: true,
      permission: LocationPermission.whileInUse,
      vpnActive: false,
    );
    expect(provider.state, OperationalReadinessState.ready);

    provider.applyTestState(
      serviceEnabled: false,
      permission: LocationPermission.whileInUse,
      vpnActive: false,
    );
    await Future<void>.delayed(Duration.zero);
    expect(provider.state, OperationalReadinessState.locationServiceOff);
    expect(platform.showCalls, 1);

    provider.applyTestState(
      serviceEnabled: false,
      permission: LocationPermission.whileInUse,
      vpnActive: false,
    );
    await Future<void>.delayed(Duration.zero);
    expect(platform.showCalls, 1);

    provider.applyTestState(
      serviceEnabled: true,
      permission: LocationPermission.whileInUse,
      vpnActive: false,
    );
    await Future<void>.delayed(Duration.zero);
    expect(provider.state, OperationalReadinessState.ready);
    expect(platform.hideCalls, 1);
  });

  test('VPN and location/network failure remain distinct states', () {
    final provider = OperationalReadinessProvider(
      platform: _FakePlatform(),
      location: _FakeLocation(),
    );
    addTearDown(provider.dispose);

    provider.applyTestState(
      serviceEnabled: true,
      permission: LocationPermission.whileInUse,
      vpnActive: false,
      locationUnavailable: true,
    );
    expect(provider.state, OperationalReadinessState.locationUnavailable);

    provider.applyTestState(
      serviceEnabled: true,
      permission: LocationPermission.whileInUse,
      vpnActive: true,
      locationUnavailable: true,
    );
    expect(provider.state, OperationalReadinessState.vpnActive);

    provider.applyTestState(
      serviceEnabled: true,
      permission: LocationPermission.whileInUse,
      vpnActive: false,
    );
    expect(provider.state, OperationalReadinessState.ready);
  });

  test(
    'foreground fallback detects a missed location-service transition',
    () async {
      final platform = _FakePlatform();
      final location = _FakeLocation();
      final provider = OperationalReadinessProvider(
        platform: platform,
        location: location,
      );
      addTearDown(provider.dispose);

      provider.applyTestState(
        serviceEnabled: true,
        permission: LocationPermission.whileInUse,
        vpnActive: false,
      );
      location.enabled =
          false; // No stream event: emulate the Android regression.

      await provider.refreshServiceStateForTesting(isArabic: false);
      await Future<void>.delayed(Duration.zero);

      expect(provider.state, OperationalReadinessState.locationServiceOff);
      expect(platform.showCalls, 1);
    },
  );

  test(
    'notification failure is retried only by the bounded fallback',
    () async {
      final platform =
          _FakePlatform()
            ..notificationResult =
                LocationOffNotificationResult.permissionDenied;
      final location = _FakeLocation()..enabled = false;
      final provider = OperationalReadinessProvider(
        platform: platform,
        location: location,
      );
      addTearDown(provider.dispose);

      provider.applyTestState(
        serviceEnabled: false,
        permission: LocationPermission.whileInUse,
        vpnActive: false,
      );
      await Future<void>.delayed(Duration.zero);
      expect(platform.showCalls, 1);

      // Repeated callbacks cannot spin native notification calls.
      provider.applyTestState(
        serviceEnabled: false,
        permission: LocationPermission.whileInUse,
        vpnActive: false,
      );
      await Future<void>.delayed(Duration.zero);
      expect(platform.showCalls, 1);

      platform.notificationResult = LocationOffNotificationResult.posted;
      await provider.refreshServiceStateForTesting(isArabic: false);
      await Future<void>.delayed(Duration.zero);
      expect(platform.showCalls, 2);
    },
  );

  test('foreground fallback never creates duplicate timers', () {
    final provider = OperationalReadinessProvider(
      platform: _FakePlatform(),
      location: _FakeLocation(),
    );
    addTearDown(provider.dispose);

    provider.startServiceFallbackForTesting(isArabic: false);
    provider.startServiceFallbackForTesting(isArabic: false);

    expect(provider.hasServiceFallbackTimer, isTrue);
  });

  test('settings action selects system, app, or permission flow', () async {
    final location = _FakeLocation();
    final provider = OperationalReadinessProvider(
      platform: _FakePlatform(),
      location: location,
    );
    addTearDown(provider.dispose);

    location.enabled = false;
    provider.applyTestState(
      serviceEnabled: false,
      permission: LocationPermission.whileInUse,
      vpnActive: false,
    );
    await provider.requestPermission(isArabic: false);
    expect(location.locationSettingsCalls, 1);

    location.enabled = true;
    location.permission = LocationPermission.deniedForever;
    provider.applyTestState(
      serviceEnabled: true,
      permission: LocationPermission.deniedForever,
      vpnActive: false,
    );
    await provider.requestPermission(isArabic: false);
    expect(location.appSettingsCalls, 1);

    location.permission = LocationPermission.denied;
    provider.applyTestState(
      serviceEnabled: true,
      permission: LocationPermission.denied,
      vpnActive: false,
    );
    await provider.requestPermission(isArabic: false);
    expect(location.permissionCalls, 1);
  });

  test(
    'logout/session cleanup resets state and removes notification',
    () async {
      final platform = _FakePlatform();
      final provider = OperationalReadinessProvider(
        platform: platform,
        location: _FakeLocation(),
      );
      addTearDown(provider.dispose);
      provider.applyTestState(
        serviceEnabled: false,
        permission: LocationPermission.whileInUse,
        vpnActive: false,
      );
      await Future<void>.delayed(Duration.zero);

      provider.clearUserState();
      await Future<void>.delayed(Duration.zero);
      expect(provider.hasStarted, isFalse);
      expect(provider.state, OperationalReadinessState.locationUnavailable);
      expect(
        OperationalReadinessProvider.currentState,
        OperationalReadinessState.locationUnavailable,
      );
      expect(platform.hideCalls, greaterThanOrEqualTo(1));
      expect(platform.monitorStops, greaterThanOrEqualTo(1));
    },
  );

  testWidgets('VPN guard is single and leaves Support and Logout accessible', (
    tester,
  ) async {
    final provider = OperationalReadinessProvider(
      platform: _FakePlatform(),
      location: _FakeLocation(),
    );
    provider.applyTestState(
      serviceEnabled: true,
      permission: LocationPermission.whileInUse,
      vpnActive: true,
    );
    addTearDown(provider.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<OperationalReadinessProvider>.value(
        value: provider,
        child: const MaterialApp(
          home: Scaffold(body: Stack(children: [OperationalGuardOverlay()])),
        ),
      ),
    );
    expect(find.text('VPN detected'), findsOneWidget);
    expect(find.text('Support'), findsOneWidget);
    expect(find.text('Logout'), findsOneWidget);
    expect(find.byType(OperationalGuardOverlay), findsOneWidget);
  });

  test(
    'all operational shipment entry points fail closed while blocked',
    () async {
      OperationalReadinessProvider.currentState =
          OperationalReadinessState.vpnActive;
      addTearDown(() {
        OperationalReadinessProvider.currentState =
            OperationalReadinessState.locationUnavailable;
      });
      final shipments = ShipmentInstantprovider();
      addTearDown(shipments.dispose);

      final results = await Future.wait([
        shipments.acceptShipment(11),
        shipments.markArrivedAtStore(11),
        shipments.pickupShipmentFromStore(11),
        shipments.deliverShipment(11),
      ]);
      expect(results, everyElement(isA<ShipmentActionResult>()));
      expect(results.every((result) => !result.success), isTrue);
      expect(
        results.every(
          (result) => result.code == 'DRIVER_NOT_OPERATIONALLY_READY',
        ),
        isTrue,
      );
    },
  );

  test('notification launch signal is forwarded without duplication', () async {
    final platform = _FakePlatform()..pendingLaunch = true;
    final provider = OperationalReadinessProvider(
      platform: platform,
      location: _FakeLocation(),
    );
    addTearDown(provider.dispose);

    expect(await provider.consumePendingLocationLaunch(), isTrue);
    var launches = 0;
    final subscription = provider.locationLaunchRequests.listen((_) {
      launches++;
    });
    addTearDown(subscription.cancel);
    platform.launchController.add(null);
    await Future<void>.delayed(Duration.zero);
    expect(launches, 1);
  });
}
