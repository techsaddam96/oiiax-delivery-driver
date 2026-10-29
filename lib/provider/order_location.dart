import 'dart:async';

import 'package:blockatie/constants/app_urls.dart';
import 'package:blockatie/models/shipmet_coords.dart';
import 'package:blockatie/services/auth_services.dart';
import 'package:blockatie/services/session_dio.dart';
import 'package:blockatie/services/user_session_state.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

enum DriverLocationTrackingStatus {
  idle,
  active,
  disabled,
  permissionRequired,
  permissionPermanentlyDenied,
  unavailable,
  syncFailed,
}

/// Server sync is deliberately separate from the device readiness and GPS-fix
/// diagnostics. A current fix can be valid while the network upload fails.
enum DriverLocationServerSyncStatus { idle, synced, failed }

typedef WorkSessionRejectionListener =
    Future<void> Function(int sessionGeneration, String code);

abstract class DriverLocationPlatform {
  Future<bool> isLocationServiceEnabled();
  Future<LocationPermission> checkPermission();
  Future<LocationPermission> requestPermission();
  Future<Position?> getLastKnownPosition();
  Future<Position> getCurrentPosition({required LocationSettings settings});
}

class GeolocatorDriverLocationPlatform implements DriverLocationPlatform {
  @override
  Future<bool> isLocationServiceEnabled() =>
      Geolocator.isLocationServiceEnabled();

  @override
  Future<LocationPermission> checkPermission() => Geolocator.checkPermission();

  @override
  Future<LocationPermission> requestPermission() =>
      Geolocator.requestPermission();

  @override
  Future<Position?> getLastKnownPosition() => Geolocator.getLastKnownPosition();

  @override
  Future<Position> getCurrentPosition({required LocationSettings settings}) =>
      Geolocator.getCurrentPosition(locationSettings: settings);
}

class OrderLocationProvider extends UserScopedNotifier {
  OrderLocationProvider({DriverLocationPlatform? locationPlatform})
    : _locationPlatform =
          locationPlatform ?? GeolocatorDriverLocationPlatform();

  final DriverLocationPlatform _locationPlatform;

  /// Stops tracking and drops the previous driver's coordinates. Called at the
  /// session boundary so a late GPS write cannot be attributed to the next
  /// driver, and so no timer survives logout.
  @override
  void clearUserState() {
    stopDriverLocationUpdates(notify: false);
    driverLocation = null;
    destinationLocation = null;
    shipmentCords = null;
    distanceInKm = null;
    driverAddress = '';
    destinationAddress = '';
    destinationTitle = 'Delivery Location';
    hasFreshDeviceLocation = false;
    isLoading = true;
    markers = <Marker>{};
    polylines = <Polyline>{};
    trackingStatus = DriverLocationTrackingStatus.idle;
    trackingMessage = null;
    lastLocationSentAt = null;
    lastGpsFixAt = null;
    locationAccuracyMeters = null;
    serverSyncStatus = DriverLocationServerSyncStatus.idle;
    _lastLocationSyncAttemptAt = null;
    _lastSentDriverLocation = null;
    _lastLoggedLocationFailureKey = null;
    _lastLoggedLocationFailureAt = null;
    _verifiedWorkSessionCapability = null;
    _verifiedWorkSessionDriverId = null;
    _verifiedWorkSessionGeneration = null;
  }

  static const Duration locationUpdateInterval = Duration(seconds: 30);
  static const Duration backendLocationUpdateInterval = Duration(seconds: 30);
  static const Duration locationFailureRetryCooldown = Duration(seconds: 60);
  static const Duration _positionTimeout = Duration(seconds: 12);
  static const double minimumLocationMoveMeters = 20;
  static const double maxOperationalRouteDistanceKm = 250;

  LatLng? driverLocation;
  LatLng? destinationLocation;
  Timer? _locationTimer;
  bool _isDisposed = false;
  bool _isTracking = false;
  bool _isStartingTracking = false;
  bool _isSendingLocation = false;
  bool _isUpdatingBackendLocation = false;
  int _trackingGeneration = 0;
  String? _verifiedWorkSessionCapability;
  String? _verifiedWorkSessionDriverId;
  int? _verifiedWorkSessionGeneration;
  WorkSessionRejectionListener? _workSessionRejectionListener;
  bool hasFreshDeviceLocation = false;

  ShipmentCordinatesResponse? shipmentCords;

  bool isLoading = true;
  double? distanceInKm;
  String driverAddress = '';
  String destinationAddress = '';
  String destinationTitle = 'Delivery Location';
  Set<Marker> markers = <Marker>{};
  Set<Polyline> polylines = <Polyline>{};
  DriverLocationTrackingStatus trackingStatus =
      DriverLocationTrackingStatus.idle;
  String? trackingMessage;
  DateTime? lastLocationSentAt;
  DateTime? lastGpsFixAt;
  double? locationAccuracyMeters;
  DriverLocationServerSyncStatus serverSyncStatus =
      DriverLocationServerSyncStatus.idle;
  DateTime? _lastLocationSyncAttemptAt;
  LatLng? _lastSentDriverLocation;
  String? _lastLoggedLocationFailureKey;
  DateTime? _lastLoggedLocationFailureAt;

  bool get isTracking => _isTracking;
  bool get hasVerifiedWorkSession =>
      _verifiedWorkSessionCapability != null &&
      _verifiedWorkSessionDriverId != null &&
      _verifiedWorkSessionGeneration != null;
  bool get hasImplausibleRouteDistance {
    final distance = distanceInKm;
    return driverLocation != null &&
        destinationLocation != null &&
        distance != null &&
        distance > maxOperationalRouteDistanceKm;
  }

  @visibleForTesting
  void applyLocationForTest({
    LatLng? location,
    DriverLocationTrackingStatus status = DriverLocationTrackingStatus.idle,
    DateTime? gpsFixAt,
    DateTime? serverSyncAt,
    double? accuracyMeters,
  }) {
    driverLocation = location;
    trackingStatus = status;
    lastGpsFixAt = gpsFixAt;
    lastLocationSentAt = serverSyncAt;
    locationAccuracyMeters = accuracyMeters;
    serverSyncStatus =
        serverSyncAt == null
            ? DriverLocationServerSyncStatus.idle
            : DriverLocationServerSyncStatus.synced;
    notifyListeners();
  }

  /// Enables the v2 writer only after [DriverWorkSessionProvider] has already
  /// received a server-confirmed Start Work capability. A legacy fallback is
  /// available solely after an explicit Start Work tap received a Batch 2A
  /// disabled/unavailable response; opening Home or a map cannot opt in.
  Future<void> startDriverLocationUpdates({
    BuildContext? context,
    bool allowLegacyFallback = false,
  }) async {
    if (_isTracking || _isStartingTracking) return;
    if (AppUrls.driverWorkSessionsEnabled &&
        !hasVerifiedWorkSession &&
        !allowLegacyFallback) {
      _setTrackingState(
        DriverLocationTrackingStatus.idle,
        'Start work before sharing live location.',
      );
      return;
    }
    final generation = stateGeneration;
    final trackingGeneration = ++_trackingGeneration;
    _isStartingTracking = true;

    try {
      final session = await AuthService.getSessionSnapshot();
      if (!acceptsState(generation)) return;
      if (!session.isAuthenticated) {
        stopDriverLocationUpdates();
        _setTrackingState(
          DriverLocationTrackingStatus.idle,
          'Missing driver session.',
          generation: generation,
        );
        return;
      }

      _locationTimer?.cancel();
      _isTracking = true;
      _setTrackingState(
        DriverLocationTrackingStatus.idle,
        'Reading current location.',
        generation: generation,
      );

      await _fetchAndSendCurrentLocation(
        generation: generation,
        trackingGeneration: trackingGeneration,
      );
      if (!acceptsState(generation) ||
          !_isTracking ||
          trackingGeneration != _trackingGeneration) {
        return;
      }
      _locationTimer = Timer.periodic(locationUpdateInterval, (_) async {
        if (!_isTracking ||
            !acceptsState(generation) ||
            trackingGeneration != _trackingGeneration) {
          return;
        }
        await _fetchAndSendCurrentLocation(
          generation: generation,
          trackingGeneration: trackingGeneration,
        );
      });
    } finally {
      if (acceptsState(generation) &&
          trackingGeneration == _trackingGeneration) {
        _isStartingTracking = false;
      }
    }
  }

  /// Refreshes the authoritative location source without starting another
  /// timer or stream. The existing polling lifecycle remains the sole owner.
  Future<void> refreshCurrentLocation() async {
    final generation = stateGeneration;
    await _fetchAndSendCurrentLocation(
      generation: generation,
      trackingGeneration: _trackingGeneration,
    );
  }

  void stopDriverLocationUpdates({bool notify = true}) {
    // Invalidate every location/GPS request before cancelling the timer. A
    // response that arrives after End Work may not update UI or start a retry.
    _trackingGeneration++;
    _locationTimer?.cancel();
    _locationTimer = null;
    _isTracking = false;
    _isStartingTracking = false;
    _isSendingLocation = false;
    _isUpdatingBackendLocation = false;
    if (notify) {
      _setTrackingState(
        DriverLocationTrackingStatus.idle,
        'Location tracking stopped.',
      );
    } else {
      trackingStatus = DriverLocationTrackingStatus.idle;
      trackingMessage = 'Location tracking stopped.';
    }
  }

  /// The work-session provider is the only caller that should provide this
  /// value. It is kept in memory only while the server has confirmed it for
  /// this exact authenticated driver/session generation.
  void activateVerifiedWorkSession({
    required String capability,
    required String driverId,
    required int sessionGeneration,
  }) {
    if (!UserSessionState.isCurrent(sessionGeneration) ||
        !RegExp(
          r'^[a-f0-9]{64}$',
          caseSensitive: false,
        ).hasMatch(capability.trim()) ||
        driverId.trim().isEmpty) {
      clearVerifiedWorkSession();
      return;
    }
    _verifiedWorkSessionCapability = capability.trim();
    _verifiedWorkSessionDriverId = driverId.trim();
    _verifiedWorkSessionGeneration = sessionGeneration;
  }

  void clearVerifiedWorkSession() {
    _verifiedWorkSessionCapability = null;
    _verifiedWorkSessionDriverId = null;
    _verifiedWorkSessionGeneration = null;
  }

  void bindWorkSessionRejectionListener(
    WorkSessionRejectionListener? listener,
  ) {
    _workSessionRejectionListener = listener;
  }

  String? _verifiedCapabilityFor(DriverSession session, int generation) {
    final capability = _verifiedWorkSessionCapability;
    if (capability == null ||
        _verifiedWorkSessionDriverId != session.driverId ||
        _verifiedWorkSessionGeneration != generation ||
        !UserSessionState.isCurrent(generation)) {
      return null;
    }
    return capability;
  }

  bool _hasAcceptableVerifiedGpsSample(
    DateTime? measuredAt,
    double? accuracyMeters,
  ) {
    if (measuredAt == null ||
        accuracyMeters == null ||
        !accuracyMeters.isFinite ||
        accuracyMeters <= 0 ||
        accuracyMeters > 100) {
      return false;
    }
    final now = DateTime.now().toUtc();
    final timestamp = measuredAt.toUtc();
    final age = now.difference(timestamp);
    return age <= const Duration(seconds: 120) &&
        age >= const Duration(seconds: -60);
  }

  Future<void> _fetchAndSendCurrentLocation({
    required int generation,
    required int trackingGeneration,
  }) async {
    if (!acceptsState(generation) ||
        !_isTracking ||
        trackingGeneration != _trackingGeneration ||
        _isSendingLocation) {
      return;
    }

    final session = await AuthService.getSessionSnapshot();
    if (!acceptsState(generation) ||
        trackingGeneration != _trackingGeneration) {
      return;
    }
    if (!session.isAuthenticated) {
      stopDriverLocationUpdates();
      return;
    }

    _isSendingLocation = true;
    try {
      // This preflight is deliberately repeated for every timer tick. A
      // retained permission never proves that Android Location Service is on.
      if (!await _ensureLocationReady(generation: generation)) return;
      if (!acceptsState(generation) ||
          trackingGeneration != _trackingGeneration) {
        return;
      }

      final previousDriverLocation = driverLocation;
      final previousDriverAddress = driverAddress;
      final previousFreshDeviceLocation = hasFreshDeviceLocation;

      // A last-known position is display-only. It may predate a service-off
      // transition, so it must never be sent to api_update_location.php.
      final lastKnownPosition = await _locationPlatform.getLastKnownPosition();
      if (!acceptsState(generation) ||
          trackingGeneration != _trackingGeneration) {
        return;
      }
      if (lastKnownPosition != null &&
          (!kReleaseMode || !lastKnownPosition.isMocked)) {
        final lastKnownLatLng = _normalizeLatLng(
          LatLng(lastKnownPosition.latitude, lastKnownPosition.longitude),
        );
        if (lastKnownLatLng != null) {
          driverLocation = lastKnownLatLng;
          hasFreshDeviceLocation = false;
          lastGpsFixAt = lastKnownPosition.timestamp;
          locationAccuracyMeters = lastKnownPosition.accuracy;
          driverAddress =
              '${lastKnownLatLng.latitude.toStringAsFixed(5)}, '
              '${lastKnownLatLng.longitude.toStringAsFixed(5)}';

          await _calculateDistance();
          if (!acceptsState(generation) ||
              trackingGeneration != _trackingGeneration) {
            return;
          }
          if (hasImplausibleRouteDistance && previousDriverLocation != null) {
            driverLocation = previousDriverLocation;
            driverAddress = previousDriverAddress;
            hasFreshDeviceLocation = previousFreshDeviceLocation;
            await _calculateDistance();
          } else {
            _createMapElements();
            _notifyListeners(generation: generation);
          }
        }
      }

      final position = await _locationPlatform.getCurrentPosition(
        settings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: _positionTimeout,
        ),
      );
      if (!acceptsState(generation) ||
          trackingGeneration != _trackingGeneration) {
        return;
      }

      if (kReleaseMode && position.isMocked) {
        debugPrint('Mocked driver location rejected.');
        _setTrackingState(
          DriverLocationTrackingStatus.unavailable,
          'Mocked location is not allowed.',
          generation: generation,
        );
        return;
      }

      final latLng = _normalizeLatLng(
        LatLng(position.latitude, position.longitude),
      );
      if (latLng == null) {
        _setTrackingState(
          DriverLocationTrackingStatus.unavailable,
          'Invalid location coordinates.',
          generation: generation,
        );
        return;
      }

      driverLocation = latLng;
      hasFreshDeviceLocation = true;
      lastGpsFixAt = position.timestamp;
      locationAccuracyMeters = position.accuracy;
      driverAddress =
          '${latLng.latitude.toStringAsFixed(5)}, '
          '${latLng.longitude.toStringAsFixed(5)}';

      await _calculateDistance();
      if (!acceptsState(generation) ||
          trackingGeneration != _trackingGeneration) {
        return;
      }
      if (hasImplausibleRouteDistance && previousDriverLocation != null) {
        driverLocation = previousDriverLocation;
        driverAddress = previousDriverAddress;
        hasFreshDeviceLocation = previousFreshDeviceLocation;
        await _calculateDistance();
        _createMapElements();
        _notifyListeners(generation: generation);
        _setTrackingState(
          DriverLocationTrackingStatus.unavailable,
          'Current location is not usable.',
          generation: generation,
        );
        return;
      }

      _createMapElements();
      _notifyListeners(generation: generation);
      await updateDriverLocation(
        generation: generation,
        trackingGeneration: trackingGeneration,
      );
      if (!acceptsState(generation) ||
          !_isTracking ||
          trackingGeneration != _trackingGeneration) {
        return;
      }
      _setTrackingState(
        serverSyncStatus == DriverLocationServerSyncStatus.synced
            ? DriverLocationTrackingStatus.active
            : DriverLocationTrackingStatus.syncFailed,
        serverSyncStatus == DriverLocationServerSyncStatus.synced
            ? 'Location updated successfully.'
            : 'Current location is available; server sync failed.',
        generation: generation,
      );
    } on TimeoutException {
      debugPrint('Driver location timeout while reading current position.');
      if (!acceptsState(generation) ||
          trackingGeneration != _trackingGeneration) {
        return;
      }
      _setTrackingState(
        DriverLocationTrackingStatus.unavailable,
        'Location update timed out.',
        generation: generation,
      );
    } catch (e) {
      debugPrint('Driver location read failed: ${e.runtimeType}');
      if (!acceptsState(generation) ||
          trackingGeneration != _trackingGeneration) {
        return;
      }
      _setTrackingState(
        DriverLocationTrackingStatus.unavailable,
        'Unable to read current location.',
        generation: generation,
      );
    } finally {
      if (acceptsState(generation) &&
          trackingGeneration == _trackingGeneration) {
        _isSendingLocation = false;
      }
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    stopDriverLocationUpdates(notify: false);
    super.dispose();
  }

  Future<void> getShipmentCords(int shipmentId) async {
    isLoading = true;
    destinationTitle = 'Delivery Location';
    _notifyListeners();

    try {
      final apiKey = await AuthService.getApiKey();
      if (apiKey == null || apiKey.trim().isEmpty) {
        isLoading = false;
        _notifyListeners();
        return;
      }

      final response = await sessionDio().post(
        AppUrls.getdrivershipmentcordinates,
        options: Options(
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
            'X-API-KEY': apiKey,
          },
        ),
        data: {'shipment_id': shipmentId},
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        shipmentCords = ShipmentCordinatesResponse.fromJson(response.data);
        await _processShipmentData();
        debugPrint('Shipment coordinates processed.');
      } else {
        debugPrint(
          'Shipment coordinates request failed: ${response.statusCode}',
        );
      }
    } catch (e) {
      debugPrint('Shipment coordinates fetch failed: ${e.runtimeType}');
    }

    isLoading = false;
    _notifyListeners();
  }

  Future<void> loadDriverLocationFallback(int shipmentId) async {
    try {
      final session = await AuthService.getSessionSnapshot();
      if (!session.isAuthenticated) return;

      final response = await sessionDio().post(
        AppUrls.profileInfo,
        options: Options(
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
            'X-API-KEY': session.apiKey,
          },
        ),
        data: {'driverId': session.driverId},
      );

      final data = response.data;
      if (response.statusCode != 200 ||
          data is! Map ||
          data['status']?.toString().toLowerCase() != 'success') {
        return;
      }

      final profile =
          data['profile'] is Map<String, dynamic>
              ? data['profile'] as Map<String, dynamic>
              : <String, dynamic>{};
      final driverLat =
          double.tryParse(profile['latitude']?.toString() ?? '') ?? 0;
      final driverLng =
          double.tryParse(profile['longitude']?.toString() ?? '') ?? 0;
      final fallbackDriverLocation = _normalizeLatLng(
        LatLng(driverLat, driverLng),
      );

      if (fallbackDriverLocation == null) return;

      driverLocation = fallbackDriverLocation;
      hasFreshDeviceLocation = false;
      await _calculateDistance();
      await _getReadableAddresses(
        keepProvidedDestinationAddress: destinationAddress.isNotEmpty,
      );
      _createMapElements();
      if (!hasImplausibleRouteDistance) {
        _setTrackingState(
          DriverLocationTrackingStatus.active,
          'Using the last synced driver location.',
        );
      }
      _notifyListeners();
    } catch (e) {
      debugPrint('Driver fallback location fetch failed: ${e.runtimeType}');
    }
  }

  Future<void> startRouteTracking({
    LatLng? destination,
    String destinationAddressValue = '',
    String destinationTitleValue = 'Delivery Location',
  }) async {
    isLoading = true;
    _notifyListeners();

    destinationTitle =
        destinationTitleValue.trim().isEmpty
            ? 'Delivery Location'
            : destinationTitleValue.trim();
    destinationLocation =
        _isValidNullableLatLng(destination)
            ? _normalizeLatLng(destination!)
            : null;
    destinationAddress = _cleanDisplayText(destinationAddressValue);

    if (destinationLocation == null && destinationAddress.isNotEmpty) {
      try {
        final locations = await locationFromAddress(destinationAddress);
        if (locations.isNotEmpty) {
          destinationLocation = LatLng(
            locations.first.latitude,
            locations.first.longitude,
          );
        }
      } catch (e) {
        debugPrint('Route destination geocoding failed: ${e.runtimeType}');
      }
    }

    await _calculateDistance();
    await _getReadableAddresses(
      keepProvidedDestinationAddress: destinationAddress.isNotEmpty,
    );
    _createMapElements();

    isLoading = false;
    _notifyListeners();
  }

  Future<void> updateDriverLocation({
    required int generation,
    required int trackingGeneration,
  }) async {
    if (!acceptsState(generation) ||
        trackingGeneration != _trackingGeneration ||
        _isUpdatingBackendLocation ||
        !hasFreshDeviceLocation) {
      return;
    }

    final session = await AuthService.getSessionSnapshot();
    if (!acceptsState(generation) ||
        trackingGeneration != _trackingGeneration) {
      return;
    }
    final location = driverLocation;
    final workSessionCapability = _verifiedCapabilityFor(session, generation);
    final sessionIsVerified = hasVerifiedWorkSession;

    if (!session.isAuthenticated ||
        location == null ||
        !_isValidLatLng(location)) {
      return;
    }

    // A stale/mismatched in-memory capability must never silently downgrade to
    // a legacy payload. The provider stops and lets the work-session owner
    // clear secure storage for the current driver only.
    if (sessionIsVerified && workSessionCapability == null) {
      clearVerifiedWorkSession();
      stopDriverLocationUpdates(notify: false);
      final listener = _workSessionRejectionListener;
      if (listener != null) {
        unawaited(listener(generation, 'WORK_SESSION_NOT_ACTIVE'));
      }
      return;
    }
    if (workSessionCapability != null &&
        !_hasAcceptableVerifiedGpsSample(
          lastGpsFixAt,
          locationAccuracyMeters,
        )) {
      serverSyncStatus = DriverLocationServerSyncStatus.failed;
      _setTrackingState(
        DriverLocationTrackingStatus.syncFailed,
        'Current GPS accuracy or timestamp is not usable.',
        generation: generation,
      );
      return;
    }

    try {
      final now = DateTime.now();
      final lastAttemptAt = _lastLocationSyncAttemptAt;
      final lastSentAt = lastLocationSentAt;

      if (lastAttemptAt != null &&
          now.difference(lastAttemptAt) < locationFailureRetryCooldown &&
          lastSentAt == null) {
        return;
      }

      if (lastSentAt != null &&
          now.difference(lastSentAt) < backendLocationUpdateInterval &&
          !_hasMeaningfulMovement(location)) {
        return;
      }

      _isUpdatingBackendLocation = true;
      _lastLocationSyncAttemptAt = now;

      final requestData = <String, String>{
        'latitude': location.latitude.toString(),
        'longitude': location.longitude.toString(),
        if (workSessionCapability != null) ...{
          'accuracy_meters': locationAccuracyMeters!.toString(),
          'measured_at_ms':
              lastGpsFixAt!.toUtc().millisecondsSinceEpoch.toString(),
        },
      };

      final response = await sessionDio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 10),
          sendTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 15),
          responseType: ResponseType.json,
          validateStatus: (_) => true,
        ),
      ).post(
        AppUrls.updateDriverLocation,
        data: requestData,
        options: Options(
          headers: {
            'X-API-KEY': session.apiKey,
            if (workSessionCapability != null)
              'X-DRIVER-WORK-SESSION': workSessionCapability,
            'Content-Type': 'application/x-www-form-urlencoded',
          },
        ),
      );
      if (!acceptsState(generation) ||
          trackingGeneration != _trackingGeneration) {
        return;
      }

      final data = response.data;
      if (response.statusCode == 200 &&
          data is Map &&
          (_isSuccess(data['success']) || _isSuccess(data['status']))) {
        lastLocationSentAt = now;
        _lastSentDriverLocation = location;
        serverSyncStatus = DriverLocationServerSyncStatus.synced;
        _lastLoggedLocationFailureAt = null;
        _lastLoggedLocationFailureKey = null;
        _setTrackingState(
          DriverLocationTrackingStatus.active,
          'Location updated successfully.',
          generation: generation,
        );
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        _logLocationSyncFailure(
          'auth_${response.statusCode}',
          'Driver location update rejected: unauthorized session.',
        );
        stopDriverLocationUpdates(notify: false);
        _setTrackingState(
          DriverLocationTrackingStatus.unavailable,
          'Driver session is invalid.',
          generation: generation,
        );
      } else if (workSessionCapability != null &&
          data is Map &&
          (data['code'] == 'WORK_SESSION_NOT_ACTIVE' ||
              data['code'] == 'WORK_SESSION_REQUIRED')) {
        clearVerifiedWorkSession();
        stopDriverLocationUpdates(notify: false);
        _setTrackingState(
          DriverLocationTrackingStatus.unavailable,
          'Work session ended. Start work again to share location.',
          generation: generation,
        );
        final listener = _workSessionRejectionListener;
        if (listener != null) {
          unawaited(listener(generation, data['code'].toString()));
        }
      } else {
        _logLocationSyncFailure(
          'status_${response.statusCode}',
          'Driver location update rejected: '
              'status=${response.statusCode} code=${_safeCode(data)}',
        );
        serverSyncStatus = DriverLocationServerSyncStatus.failed;
        _setTrackingState(
          DriverLocationTrackingStatus.syncFailed,
          'Location is active; server sync failed.',
          generation: generation,
        );
      }
    } catch (e) {
      if (!acceptsState(generation) ||
          trackingGeneration != _trackingGeneration) {
        return;
      }
      _logLocationSyncFailure(
        'runtime_${e.runtimeType}',
        'Driver location update failed: ${e.runtimeType}',
      );
      serverSyncStatus = DriverLocationServerSyncStatus.failed;
      _setTrackingState(
        DriverLocationTrackingStatus.syncFailed,
        'Location is active; server sync failed.',
        generation: generation,
      );
    } finally {
      if (acceptsState(generation) &&
          trackingGeneration == _trackingGeneration) {
        _isUpdatingBackendLocation = false;
      }
    }
  }

  Future<void> _processShipmentData() async {
    if (shipmentCords?.data == null) return;

    final data = shipmentCords!.data;
    final driverLat = double.tryParse(data.latitude) ?? 0;
    final driverLng = double.tryParse(data.longitude) ?? 0;
    final apiDriverLocation = _normalizeLatLng(LatLng(driverLat, driverLng));

    if (driverLocation == null && apiDriverLocation != null) {
      driverLocation = apiDriverLocation;
      hasFreshDeviceLocation = false;
      _setTrackingState(
        DriverLocationTrackingStatus.active,
        'Using the last synced driver location.',
      );
    }

    final deliveryAddress = data.deliveryAddress;
    if (deliveryAddress.isNotEmpty && deliveryAddress.toLowerCase() != 'null') {
      try {
        final locations = await locationFromAddress(deliveryAddress);
        if (locations.isNotEmpty) {
          destinationLocation = LatLng(
            locations.first.latitude,
            locations.first.longitude,
          );
        }
      } catch (e) {
        debugPrint('Delivery geocoding failed: ${e.runtimeType}');
        destinationLocation = const LatLng(31.9539, 35.9106);
      }
    } else {
      destinationLocation = const LatLng(31.9539, 35.9106);
    }

    await _calculateDistance();
    await _getReadableAddresses();
    _createMapElements();
  }

  Future<void> _calculateDistance() async {
    if (driverLocation == null || destinationLocation == null) {
      distanceInKm = 0;
      return;
    }

    try {
      final distanceInMeters = Geolocator.distanceBetween(
        driverLocation!.latitude,
        driverLocation!.longitude,
        destinationLocation!.latitude,
        destinationLocation!.longitude,
      );
      distanceInKm = distanceInMeters / 1000;
    } catch (e) {
      debugPrint('Distance calculation failed: ${e.runtimeType}');
      distanceInKm = 0;
    }
  }

  Future<void> _getReadableAddresses({
    bool keepProvidedDestinationAddress = false,
  }) async {
    if (driverLocation != null) {
      try {
        final driverPlacemarks = await placemarkFromCoordinates(
          driverLocation!.latitude,
          driverLocation!.longitude,
        );

        if (driverPlacemarks.isNotEmpty) {
          driverAddress = _formatAddress(driverPlacemarks.first);
        }
      } catch (e) {
        debugPrint('Driver address lookup failed: ${e.runtimeType}');
        driverAddress = 'Driver Location';
      }
    }

    if (destinationLocation != null && !keepProvidedDestinationAddress) {
      try {
        final destPlacemarks = await placemarkFromCoordinates(
          destinationLocation!.latitude,
          destinationLocation!.longitude,
        );

        if (destPlacemarks.isNotEmpty) {
          destinationAddress = _formatAddress(destPlacemarks.first);
        }
      } catch (e) {
        debugPrint('Destination address lookup failed: ${e.runtimeType}');
        destinationAddress =
            shipmentCords?.data.deliveryAddress ?? 'Delivery Location';
      }
    }
  }

  String _formatAddress(Placemark placemark) {
    final parts = <String>[];

    if (placemark.street?.isNotEmpty == true) {
      parts.add(placemark.street!);
    }
    if (placemark.locality?.isNotEmpty == true) {
      parts.add(placemark.locality!);
    }
    if (placemark.administrativeArea?.isNotEmpty == true) {
      parts.add(placemark.administrativeArea!);
    }

    return parts.isNotEmpty ? parts.join(', ') : 'Unknown Location';
  }

  void starTrackStore({required LatLng storeLocation}) {
    unawaited(
      startRouteTracking(
        destination: storeLocation,
        destinationTitleValue: 'Store Location',
      ),
    );
  }

  void _createMapElements() {
    markers.clear();
    polylines.clear();

    if (driverLocation != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('driver'),
          position: driverLocation!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
          infoWindow: const InfoWindow(title: 'Driver Location'),
        ),
      );
    }

    if (destinationLocation != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('destination'),
          position: destinationLocation!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: InfoWindow(title: destinationTitle),
        ),
      );
    }

    if (driverLocation != null &&
        destinationLocation != null &&
        !hasImplausibleRouteDistance) {
      polylines.add(
        Polyline(
          polylineId: const PolylineId('route'),
          points: [driverLocation!, destinationLocation!],
          color: Colors.blue,
          width: 4,
        ),
      );
    }

    _debugRouteState();
  }

  String get recipientName => shipmentCords?.data.recipientName ?? '';

  String get recipientPhone => shipmentCords?.data.recipientPhone ?? '';

  String get driverPhone => shipmentCords?.data.driverPhone ?? '';

  int get shipmentId => shipmentCords?.data.shipmentId ?? 0;

  Future<bool> _ensureLocationReady({required int generation}) async {
    try {
      final serviceEnabled = await _locationPlatform.isLocationServiceEnabled();
      if (!acceptsState(generation)) return false;
      if (!serviceEnabled) {
        hasFreshDeviceLocation = false;
        _setTrackingState(
          DriverLocationTrackingStatus.disabled,
          'Location services are disabled.',
          generation: generation,
        );
        return false;
      }

      var permission = await _locationPlatform.checkPermission();
      if (!acceptsState(generation)) return false;
      if (permission == LocationPermission.denied) {
        permission = await _locationPlatform.requestPermission();
        if (!acceptsState(generation)) return false;
      }

      if (permission == LocationPermission.denied) {
        hasFreshDeviceLocation = false;
        _setTrackingState(
          DriverLocationTrackingStatus.permissionRequired,
          'Location permission is required.',
          generation: generation,
        );
        return false;
      }

      if (permission == LocationPermission.deniedForever) {
        hasFreshDeviceLocation = false;
        _setTrackingState(
          DriverLocationTrackingStatus.permissionPermanentlyDenied,
          'Location permission is permanently denied.',
          generation: generation,
        );
        return false;
      }

      return true;
    } catch (e) {
      debugPrint('Location permission check failed: ${e.runtimeType}');
      if (!acceptsState(generation)) return false;
      hasFreshDeviceLocation = false;
      _setTrackingState(
        DriverLocationTrackingStatus.unavailable,
        'Location permission check failed.',
        generation: generation,
      );
      return false;
    }
  }

  void _setTrackingState(
    DriverLocationTrackingStatus status,
    String? message, {
    int? generation,
  }) {
    if (generation != null && !acceptsState(generation)) return;
    trackingStatus = status;
    trackingMessage = message;
    _notifyListeners(generation: generation);
  }

  void _notifyListeners({int? generation}) {
    if (generation != null && !acceptsState(generation)) return;
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  bool _isValidLatLng(LatLng location) {
    final lat = location.latitude;
    final lng = location.longitude;
    // Finiteness first: NaN compares false against every bound, so a NaN pair
    // used to pass the range check untouched.
    if (!lat.isFinite || !lng.isFinite) return false;
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return false;
    if (lat == 0 && lng == 0) return false;
    return true;
  }

  bool _isValidNullableLatLng(LatLng? location) {
    if (location == null) return false;
    return _isValidLatLng(location);
  }

  LatLng? _normalizeLatLng(LatLng location) {
    final lat = location.latitude;
    final lng = location.longitude;

    if (_looksLikeSwappedJordanPair(lat, lng)) {
      return LatLng(lng, lat);
    }

    if (!_isValidLatLng(location)) return null;
    return location;
  }

  bool _looksLikeSwappedJordanPair(double lat, double lng) {
    return !_isJordanLatitude(lat) &&
        !_isJordanLongitude(lng) &&
        _isJordanLongitude(lat) &&
        _isJordanLatitude(lng);
  }

  bool _isJordanLatitude(double value) => value >= 29.0 && value <= 34.0;

  bool _isJordanLongitude(double value) => value >= 34.0 && value <= 40.0;

  void _debugRouteState() {
    if (!kDebugMode) return;
    debugPrint(
      'Tracking route updated: '
      'distanceKm=${(distanceInKm ?? 0).toStringAsFixed(2)}, '
      'plausible=${!hasImplausibleRouteDistance}',
    );
  }

  String _cleanDisplayText(String value) {
    final clean = value.trim();
    if (clean.isEmpty || clean.toLowerCase() == 'null') return '';
    if (clean == 'غير متوفر' || clean == 'Not available') return '';
    return clean;
  }

  bool _isSuccess(dynamic value) {
    if (value == true) return true;
    final normalized = value?.toString().trim().toLowerCase();
    return normalized == 'true' || normalized == '1' || normalized == 'success';
  }

  bool _hasMeaningfulMovement(LatLng currentLocation) {
    final lastLocation = _lastSentDriverLocation;
    if (lastLocation == null) return true;

    final movedMeters = Geolocator.distanceBetween(
      lastLocation.latitude,
      lastLocation.longitude,
      currentLocation.latitude,
      currentLocation.longitude,
    );
    return movedMeters >= minimumLocationMoveMeters;
  }

  void _logLocationSyncFailure(String key, String message) {
    final now = DateTime.now();
    if (_lastLoggedLocationFailureKey == key &&
        _lastLoggedLocationFailureAt != null &&
        now.difference(_lastLoggedLocationFailureAt!) <
            locationFailureRetryCooldown) {
      return;
    }

    _lastLoggedLocationFailureKey = key;
    _lastLoggedLocationFailureAt = now;
    debugPrint(message);
  }

  String _safeCode(dynamic data) {
    if (data is! Map) return 'unknown';
    return data['code']?.toString() ?? data['status']?.toString() ?? 'unknown';
  }
}
