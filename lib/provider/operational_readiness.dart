import 'dart:async';

import 'package:blockatie/services/auth_services.dart';
import 'package:blockatie/services/user_session_state.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

enum OperationalReadinessState {
  ready,
  locationServiceOff,
  locationPermissionDenied,
  locationPermissionPermanentlyDenied,
  locationUnavailable,
  vpnActive,
}

/// Result of asking Android to display the local GPS-off warning.  Keeping
/// this explicit prevents the Dart state from claiming a notification exists
/// when Android declined it because notifications are disabled.
enum LocationOffNotificationResult { posted, permissionDenied, failed }

abstract class OperationalPlatformBridge {
  Stream<bool> get vpnChanges;
  Stream<void> get locationLaunchRequests;
  Future<bool> currentVpnState();
  Future<bool> consumePendingLocationLaunch();
  Future<LocationOffNotificationResult> showLocationOffNotification({
    required bool isArabic,
  });
  Future<void> hideLocationOffNotification();
  Future<void> startLocationReadinessMonitor({required bool isArabic});
  Future<void> stopLocationReadinessMonitor();
}

abstract class LocationReadinessBridge {
  Stream<ServiceStatus> get serviceChanges;
  Future<bool> isServiceEnabled();
  Future<LocationPermission> checkPermission();
  Future<LocationPermission> requestPermission();
  Future<bool> openLocationSettings();
  Future<bool> openAppSettings();
}

class GeolocatorReadinessBridge implements LocationReadinessBridge {
  @override
  Stream<ServiceStatus> get serviceChanges =>
      Geolocator.getServiceStatusStream();
  @override
  Future<bool> isServiceEnabled() => Geolocator.isLocationServiceEnabled();
  @override
  Future<LocationPermission> checkPermission() => Geolocator.checkPermission();
  @override
  Future<LocationPermission> requestPermission() =>
      Geolocator.requestPermission();
  @override
  Future<bool> openLocationSettings() => Geolocator.openLocationSettings();
  @override
  Future<bool> openAppSettings() => Geolocator.openAppSettings();
}

class MethodChannelOperationalBridge implements OperationalPlatformBridge {
  static const _methods = MethodChannel('blockatie.driver/readiness');
  static const _vpnEvents = EventChannel('blockatie.driver/vpn_events');
  final StreamController<void> _locationLaunchController =
      StreamController<void>.broadcast();

  MethodChannelOperationalBridge() {
    _methods.setMethodCallHandler((call) async {
      if (call.method == 'openReadiness') {
        _locationLaunchController.add(null);
      }
    });
  }

  @override
  Stream<bool> get vpnChanges =>
      _vpnEvents
          .receiveBroadcastStream()
          .map((event) => event == true)
          .distinct();

  @override
  Stream<void> get locationLaunchRequests => _locationLaunchController.stream;

  @override
  Future<bool> consumePendingLocationLaunch() async {
    try {
      return await _methods.invokeMethod<bool>('consumeReadinessLaunch') ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<bool> currentVpnState() async {
    try {
      return await _methods.invokeMethod<bool>('isVpnActive') ?? false;
    } on MissingPluginException {
      // iOS cannot reliably identify arbitrary third-party VPNs with the
      // app's current public entitlements, so it deliberately fails open.
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<LocationOffNotificationResult> showLocationOffNotification({
    required bool isArabic,
  }) async {
    try {
      final result = await _methods.invokeMethod<String>(
        'showLocationOffNotification',
        {'isArabic': isArabic},
      );
      return switch (result) {
        'POSTED' => LocationOffNotificationResult.posted,
        'PERMISSION_DENIED' => LocationOffNotificationResult.permissionDenied,
        _ => LocationOffNotificationResult.failed,
      };
    } on PlatformException {
      return LocationOffNotificationResult.failed;
    } on MissingPluginException {
      return LocationOffNotificationResult.failed;
    }
  }

  @override
  Future<void> hideLocationOffNotification() async {
    try {
      await _methods.invokeMethod<void>('hideLocationOffNotification');
    } on PlatformException {
      // Already absent or unavailable.
    } on MissingPluginException {
      // iOS: intentionally unsupported.
    }
  }

  @override
  Future<void> startLocationReadinessMonitor({required bool isArabic}) async {
    try {
      await _methods.invokeMethod<void>('startLocationReadinessMonitor', {
        'isArabic': isArabic,
      });
    } on PlatformException {
      // The in-app readiness guard remains available on unsupported devices.
    } on MissingPluginException {
      // Android-only background monitor.
    }
  }

  @override
  Future<void> stopLocationReadinessMonitor() async {
    try {
      await _methods.invokeMethod<void>('stopLocationReadinessMonitor');
    } on PlatformException {
      // Best-effort session cleanup.
    } on MissingPluginException {
      // Android-only background monitor.
    }
  }
}

/// One session-scoped source of truth for operational GPS and VPN readiness.
class OperationalReadinessProvider extends UserScopedNotifier {
  OperationalReadinessProvider({
    OperationalPlatformBridge? platform,
    LocationReadinessBridge? location,
  }) : _platform = platform ?? MethodChannelOperationalBridge(),
       _location = location ?? GeolocatorReadinessBridge();

  final OperationalPlatformBridge _platform;
  final LocationReadinessBridge _location;
  StreamSubscription<ServiceStatus>? _serviceSubscription;
  StreamSubscription<bool>? _vpnSubscription;
  Timer? _serviceFallbackTimer;
  bool _started = false;
  bool _locationServiceEnabled = true;
  LocationPermission _permission = LocationPermission.denied;
  bool _vpnActive = false;
  bool _locationUnavailable = false;
  bool _notificationVisible = false;
  bool _notificationSyncInFlight = false;
  bool _notificationRetryPending = false;
  bool _serviceFallbackCheckInFlight = false;

  static const Duration serviceStateFallbackInterval = Duration(seconds: 8);

  static OperationalReadinessState currentState =
      OperationalReadinessState.locationUnavailable;

  OperationalReadinessState state =
      OperationalReadinessState.locationUnavailable;
  bool get isReady => state == OperationalReadinessState.ready;
  bool get hasStarted => _started;
  bool get vpnActive => _vpnActive;
  bool get locationServiceEnabled => _locationServiceEnabled;
  LocationPermission get permission => _permission;
  @visibleForTesting
  bool get hasServiceFallbackTimer => _serviceFallbackTimer != null;
  Stream<void> get locationLaunchRequests => _platform.locationLaunchRequests;
  Future<bool> consumePendingLocationLaunch() =>
      _platform.consumePendingLocationLaunch();

  Future<void> start({required bool isArabic}) async {
    if (_started) {
      final generation = stateGeneration;
      await refresh(isArabic: isArabic);
      if (!acceptsState(generation) || !_started) return;
      _startServiceFallback(isArabic: isArabic);
      unawaited(_platform.startLocationReadinessMonitor(isArabic: isArabic));
      return;
    }
    final generation = stateGeneration;
    final session = await AuthService.getSessionSnapshot();
    if (!acceptsState(generation) || !session.isAuthenticated) return;
    _started = true;

    await refresh(isArabic: isArabic);
    if (!acceptsState(generation) || !_started) return;

    _serviceSubscription = _location.serviceChanges.listen((status) {
      if (!acceptsState(generation) || !_started) return;
      _locationServiceEnabled = status == ServiceStatus.enabled;
      _locationUnavailable = false;
      _recompute(isArabic: isArabic);
    });

    try {
      _vpnSubscription = _platform.vpnChanges.listen(
        (active) {
          if (!acceptsState(generation) || !_started) return;
          if (_vpnActive == active) return;
          _vpnActive = active;
          _recompute(isArabic: isArabic);
        },
        onError: (_) {
          if (!acceptsState(generation) || !_started) return;
          // Missing/unsupported platform streams must not become a false VPN
          // positive. Android still uses the native event-driven detector.
          if (_vpnActive) {
            _vpnActive = false;
            _recompute(isArabic: isArabic);
          }
        },
      );
    } catch (_) {
      _vpnActive = false;
    }
    _startServiceFallback(isArabic: isArabic);
    unawaited(_platform.startLocationReadinessMonitor(isArabic: isArabic));
  }

  Future<void> refresh({required bool isArabic}) async {
    final generation = stateGeneration;
    try {
      final results = await Future.wait<dynamic>([
        _location.isServiceEnabled(),
        _location.checkPermission(),
        _platform.currentVpnState(),
      ]);
      if (!acceptsState(generation)) return;
      _locationServiceEnabled = results[0] == true;
      _permission = results[1] as LocationPermission;
      _vpnActive = results[2] == true;
      _locationUnavailable = false;
      _recompute(isArabic: isArabic);
    } catch (_) {
      if (!acceptsState(generation)) return;
      _locationUnavailable = true;
      _recompute(isArabic: isArabic);
    }
  }

  void _startServiceFallback({required bool isArabic}) {
    if (_serviceFallbackTimer != null) return;
    _serviceFallbackTimer = Timer.periodic(serviceStateFallbackInterval, (_) {
      unawaited(_refreshServiceState(isArabic: isArabic));
    });
  }

  Future<void> _refreshServiceState({required bool isArabic}) async {
    if (!_started || _serviceFallbackCheckInFlight) return;
    final generation = stateGeneration;
    _serviceFallbackCheckInFlight = true;
    try {
      final enabled = await _location.isServiceEnabled();
      if (!acceptsState(generation) || !_started) return;
      _locationServiceEnabled = enabled;
      _locationUnavailable = false;
      _recompute(isArabic: isArabic, retryNotification: true);
    } catch (_) {
      if (!acceptsState(generation) || !_started) return;
      _locationUnavailable = true;
      _recompute(isArabic: isArabic, retryNotification: true);
    } finally {
      if (acceptsState(generation)) {
        _serviceFallbackCheckInFlight = false;
      }
    }
  }

  @visibleForTesting
  Future<void> refreshServiceStateForTesting({required bool isArabic}) =>
      _refreshServiceState(isArabic: isArabic);

  @visibleForTesting
  void startServiceFallbackForTesting({required bool isArabic}) =>
      _startServiceFallback(isArabic: isArabic);

  Future<void> requestPermission({required bool isArabic}) async {
    final generation = stateGeneration;
    if (!_locationServiceEnabled) {
      await _location.openLocationSettings();
    } else if (_permission == LocationPermission.deniedForever) {
      await _location.openAppSettings();
    } else {
      await _location.requestPermission();
    }
    if (!acceptsState(generation)) return;
    await refresh(isArabic: isArabic);
    if (acceptsState(generation) && _started) {
      // Android refuses a location-type foreground service before the runtime
      // location permission exists. Try again immediately after a grant.
      unawaited(_platform.startLocationReadinessMonitor(isArabic: isArabic));
    }
  }

  void _recompute({required bool isArabic, bool retryNotification = false}) {
    final next = switch ((_vpnActive, _locationServiceEnabled, _permission)) {
      (true, _, _) => OperationalReadinessState.vpnActive,
      (_, false, _) => OperationalReadinessState.locationServiceOff,
      (_, _, LocationPermission.deniedForever) =>
        OperationalReadinessState.locationPermissionPermanentlyDenied,
      (_, _, LocationPermission.denied) =>
        OperationalReadinessState.locationPermissionDenied,
      _ when _locationUnavailable =>
        OperationalReadinessState.locationUnavailable,
      _ => OperationalReadinessState.ready,
    };

    final changed = next != state;
    state = next;
    currentState = next;
    _syncNotification(
      isArabic: isArabic,
      retryFailedNotification: retryNotification,
    );
    if (changed) notifyListeners();
  }

  void _syncNotification({
    required bool isArabic,
    bool retryFailedNotification = false,
  }) {
    final shouldShow = state == OperationalReadinessState.locationServiceOff;
    if (shouldShow == _notificationVisible ||
        _notificationSyncInFlight ||
        (shouldShow && _notificationRetryPending && !retryFailedNotification)) {
      return;
    }
    unawaited(
      _syncNotificationAsync(
        shouldShow: shouldShow,
        isArabic: isArabic,
        generation: stateGeneration,
      ),
    );
  }

  Future<void> _syncNotificationAsync({
    required bool shouldShow,
    required bool isArabic,
    required int generation,
  }) async {
    _notificationSyncInFlight = true;
    try {
      if (shouldShow) {
        final result = await _platform.showLocationOffNotification(
          isArabic: isArabic,
        );
        if (!acceptsState(generation) || !_started) {
          if (result == LocationOffNotificationResult.posted) {
            await _platform.hideLocationOffNotification();
          }
          return;
        }
        _notificationVisible = result == LocationOffNotificationResult.posted;
        _notificationRetryPending =
            result != LocationOffNotificationResult.posted;
      } else {
        await _platform.hideLocationOffNotification();
        if (!acceptsState(generation) || !_started) return;
        _notificationVisible = false;
        _notificationRetryPending = false;
      }
    } finally {
      if (acceptsState(generation)) {
        _notificationSyncInFlight = false;
        final shouldShowNow =
            state == OperationalReadinessState.locationServiceOff;
        // Retry a denied notification on the next bounded fallback check, not
        // in a tight async loop. Only immediately reconcile if the readiness
        // state changed while the native call was in flight.
        if (shouldShowNow != shouldShow &&
            shouldShowNow != _notificationVisible) {
          _syncNotification(isArabic: isArabic);
        }
      }
    }
  }

  @visibleForTesting
  void applyTestState({
    required bool serviceEnabled,
    required LocationPermission permission,
    required bool vpnActive,
    bool locationUnavailable = false,
    bool started = true,
  }) {
    _started = started;
    _locationServiceEnabled = serviceEnabled;
    _permission = permission;
    _vpnActive = vpnActive;
    _locationUnavailable = locationUnavailable;
    _recompute(isArabic: false);
  }

  @override
  void clearUserState() {
    _started = false;
    _serviceFallbackTimer?.cancel();
    _serviceFallbackTimer = null;
    unawaited(_serviceSubscription?.cancel());
    unawaited(_vpnSubscription?.cancel());
    _serviceSubscription = null;
    _vpnSubscription = null;
    _locationServiceEnabled = true;
    _permission = LocationPermission.denied;
    _vpnActive = false;
    _locationUnavailable = false;
    _notificationVisible = false;
    _notificationSyncInFlight = false;
    _notificationRetryPending = false;
    _serviceFallbackCheckInFlight = false;
    state = OperationalReadinessState.locationUnavailable;
    currentState = state;
    unawaited(_platform.hideLocationOffNotification());
    unawaited(_platform.stopLocationReadinessMonitor());
  }

  @override
  void dispose() {
    clearUserState();
    super.dispose();
  }
}
