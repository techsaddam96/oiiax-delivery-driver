import 'dart:async';
import 'package:blockatie/main.dart';
import 'package:blockatie/utils/location_failure.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:logging/logging.dart';
import 'package:permission_handler/permission_handler.dart'
    as ph
    show openAppSettings;

class LocationServiceNoContext {
  final Logger _logger = Logger('LocationService');

  /// Resolves the driver's country, or the reason it could not be resolved.
  ///
  /// Every exit carries a [LocationFailure] value. Nothing here builds a
  /// sentence, so the message the driver reads and the action offered beside
  /// it are both decided from the failure type rather than from prose.
  Future<LocationLookup> lookup() async {
    _logger.info('Getting location with Geolocator...');

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      _logger.info('Service enabled: $serviceEnabled');
      if (!serviceEnabled) {
        return const LocationLookup.failed(LocationFailure.serviceDisabled);
      }

      LocationPermission permission = await Geolocator.checkPermission();
      _logger.info('Permission status: $permission');

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        _logger.info('Request permission result: $permission');

        if (permission == LocationPermission.denied) {
          return const LocationLookup.failed(LocationFailure.permissionDenied);
        }
      }

      if (permission == LocationPermission.deniedForever) {
        return const LocationLookup.failed(
          LocationFailure.permissionPermanentlyDenied,
        );
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          _logger.warning('Location request timed out');
          throw TimeoutException('Failed to get location within time limit');
        },
      );

      _logger.info(
        'Position: lat=${position.latitude}, lng=${position.longitude}',
      );

      final country = await _getAddressFromLatLng(
        latitude: position.latitude,
        longitude: position.longitude,
      );

      _logger.info('Country: $country');
      return LocationLookup.success(country);
    } catch (e, st) {
      // The exception is logged, never surfaced: it used to be interpolated
      // straight into the driver's message as "Failed to get location: $e".
      _logger.severe('Error in getUserLocation: ${e.runtimeType}', e, st);
      return const LocationLookup.failed(LocationFailure.unavailable);
    }
  }

  /// Resolves the country and reports a failure to the driver.
  ///
  /// Kept as the entry point existing callers use; the address contract is
  /// unchanged, and the reporting now actually reaches the screen.
  Future<String?> getUserLocation() async {
    final result = await lookup();
    if (result.isSuccess) {
      return result.address;
    }
    showLocationFailure(result.failure!);
    return null;
  }

  Future<String> _getAddressFromLatLng({
    required double latitude,
    required double longitude,
  }) async {
    try {
      _logger.info('Getting address for lat=$latitude, lng=$longitude');
      final placemarks = await placemarkFromCoordinates(latitude, longitude);
      _logger.info('Placemarks found: ${placemarks.length}');
      return placemarks.isNotEmpty
          ? placemarks.first.country ?? 'Unknown country'
          : 'Unknown country';
    } catch (e, st) {
      _logger.severe('Error in _getAddressFromLatLng: ${e.runtimeType}', e, st);
      return 'Unknown country';
    }
  }
}

/// Shows a location failure on the app-wide messenger.
///
/// Free function rather than a private method so a test can drive it without
/// reaching the platform channels [LocationServiceNoContext] depends on.
///
/// The messenger is the one `MaterialApp.scaffoldMessengerKey` owns. Before
/// that key was wired, `currentState` was always null here and every location
/// failure was silent.
void showLocationFailure(LocationFailure failure) {
  final messenger = rootScaffoldMessengerKey.currentState;
  if (messenger == null) {
    return;
  }

  messenger.showSnackBar(
    SnackBar(
      content: Text(locationFailureMessage(failure)),
      duration: const Duration(seconds: 4),
      // Offered because of what went wrong, not because the sentence happened
      // to contain the word "settings".
      action:
          locationFailureOffersSettings(failure)
              ? SnackBarAction(
                label: openSettingsActionLabel(),
                onPressed: ph.openAppSettings,
              )
              : null,
    ),
  );
}
