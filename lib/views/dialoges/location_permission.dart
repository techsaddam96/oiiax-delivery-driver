// location_service.dart
import 'dart:async';
import 'package:blockatie/services/auth_services.dart';
import 'package:blockatie/views/dialoges/sucess_dialoge.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' as geolocator;
import 'package:location/location.dart';

class LocationService {
  static final LocationService _instance = LocationService._internal();

  factory LocationService() => _instance;

  LocationService._internal();

  Location location = Location();
  StreamSubscription<LocationData>? _locationSubscription;
  Timer? _periodicCheck;
  bool _isMonitoring = false;
  bool _isLocationDialogVisible = false;
  static const Duration _serviceCheckInterval = Duration(seconds: 45);

  // Callback to show popup when location is disabled
  Function(BuildContext)? _onLocationDisabled;

  // Initialize location monitoring
  Future<void> initializeLocationMonitoring(BuildContext context) async {
    final session = await AuthService.getSessionSnapshot();
    if (!context.mounted) return;
    if (!session.isAuthenticated) {
      stopMonitoring();
      return;
    }

    _onLocationDisabled = (context) => _showLocationDialog(context);

    if (!_isMonitoring) {
      _startPeriodicLocationCheck(context);
      _isMonitoring = true;
    }
  }

  Future<bool> requestLocationAccess(BuildContext context) async {
    return _requestLocationService(context);
  }

  // Start periodic location service check
  void _startPeriodicLocationCheck(BuildContext context) {
    _periodicCheck?.cancel();
    _periodicCheck = Timer.periodic(_serviceCheckInterval, (timer) async {
      if (!_isMonitoring || !context.mounted) return;

      try {
        final serviceEnabled = await location.serviceEnabled();
        if (!context.mounted) return;
        if (!serviceEnabled && _onLocationDisabled != null) {
          _onLocationDisabled!(context);
        }
      } catch (e) {
        debugPrint('Location service check failed: ${e.runtimeType}');
      }
    });
  }

  // Show location dialog
  void _showLocationDialog(BuildContext context) {
    if (_isLocationDialogVisible || !context.mounted) return;
    _isLocationDialogVisible = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          contentPadding: const EdgeInsets.all(20),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Warning icon
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.warning,
                  color: Colors.orange,
                  size: 32,
                ),
              ),
              const SizedBox(height: 16),

              // Title
              Text(
                _copy(context, 'Location disabled', 'الموقع غير مفعل'),
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),

              // Description
              Text(
                _copy(
                  context,
                  'Please enable location services to update delivery tracking.',
                  'يرجى تفعيل خدمة الموقع لتحديث تتبع التوصيل.',
                ),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
              const SizedBox(height: 20),

              // Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    Navigator.of(context).pop();
                    _isLocationDialogVisible = false;
                    await _requestLocationService(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    _copy(context, 'Enable location', 'تفعيل الموقع'),
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    ).whenComplete(() => _isLocationDialogVisible = false);
  }

  // Request location service
  Future<bool> _requestLocationService(BuildContext context) async {
    try {
      bool serviceEnabled = await location.serviceEnabled();
      if (!context.mounted) return false;
      if (!serviceEnabled) {
        serviceEnabled = await location.requestService();
        if (!context.mounted) return false;
        if (!serviceEnabled) {
          await geolocator.Geolocator.openLocationSettings();
          if (!context.mounted) return false;
          _showActionSnack(
            context,
            _copy(
              context,
              'Turn on device location, then return to OIIAX.',
              'فعّل خدمة الموقع من إعدادات الجهاز ثم ارجع لتطبيق OIIAX.',
            ),
          );
          return false;
        }
      }

      var permissionGranted = await geolocator.Geolocator.checkPermission();
      if (!context.mounted) return false;
      if (permissionGranted == geolocator.LocationPermission.denied) {
        permissionGranted = await geolocator.Geolocator.requestPermission();
        if (!context.mounted) return false;
        if (permissionGranted == geolocator.LocationPermission.denied) {
          _showActionSnack(
            context,
            _copy(
              context,
              'Location permission is required for driver tracking.',
              'صلاحية الموقع مطلوبة لتتبع السائق.',
            ),
          );
          return false;
        }
      }
      if (permissionGranted == geolocator.LocationPermission.deniedForever) {
        await geolocator.Geolocator.openAppSettings();
        if (!context.mounted) return false;
        _showActionSnack(
          context,
          _copy(
            context,
            'Allow location permission from app settings, then return.',
            'اسمح بصلاحية الموقع من إعدادات التطبيق ثم ارجع.',
          ),
        );
        return false;
      }

      if (permissionGranted != geolocator.LocationPermission.whileInUse &&
          permissionGranted != geolocator.LocationPermission.always) {
        _showActionSnack(
          context,
          _copy(
            context,
            'Location permission is required for driver tracking.',
            'صلاحية الموقع مطلوبة لتتبع السائق.',
          ),
        );
        return false;
      }

      // If we reach here, location is enabled
      // ScaffoldMessenger.of(context).showSnackBar(
      //   SnackBar(
      //     content: Text(tr('locationEnabledSuccessfully')),
      //     backgroundColor: Colors.green,
      //   ),
      // );
      showSucessDialoge(
        context,
        tr('success'),
        _copy(context, 'Location is active.', 'الموقع مفعل.'),
      );
      return true;
    } catch (e) {
      debugPrint('Location service request failed: ${e.runtimeType}');
      if (context.mounted) {
        _showActionSnack(
          context,
          _copy(
            context,
            'Unable to open location settings. Please try again.',
            'تعذر فتح إعدادات الموقع. حاول مرة أخرى.',
          ),
        );
      }
      return false;
    }
  }

  void _showActionSnack(BuildContext context, String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: _copy(context, 'Settings', 'الإعدادات'),
          onPressed: geolocator.Geolocator.openAppSettings,
        ),
      ),
    );
  }

  // Get current location with permission check
  Future<LocationData?> getLocation(BuildContext context) async {
    try {
      // First check if we have permission
      bool hasPermission = await handleLocationPermission(context);
      if (!context.mounted) return null;
      if (!hasPermission) {
        return null;
      }

      // Get current location
      LocationData locationData = await location.getLocation();
      return locationData;
    } catch (e) {
      debugPrint('Location read failed: ${e.runtimeType}');
      return null;
    }
  }

  // Start location updates stream with permission check
  Stream<LocationData>? getLocationStream(BuildContext context) {
    try {
      _handleLocationPermissionAsync(context);
      return location.onLocationChanged;
    } catch (e) {
      debugPrint('Location stream start failed: ${e.runtimeType}');
      return null;
    }
  }

  // Helper method to handle permission asynchronously for stream
  Future<void> _handleLocationPermissionAsync(BuildContext context) async {
    await handleLocationPermission(context);
  }

  // Handle initial location permission (for GetStarted page)
  Future<bool> handleLocationPermission(BuildContext context) async {
    try {
      bool serviceEnabled = await location.serviceEnabled();
      if (!context.mounted) return false;
      if (!serviceEnabled) {
        serviceEnabled = await location.requestService();
        if (!context.mounted) return false;
        if (!serviceEnabled) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                _copy(
                  context,
                  'Please enable location services.',
                  'يرجى تفعيل خدمة الموقع.',
                ),
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
          return false;
        }
      }

      PermissionStatus permissionGranted = await location.hasPermission();
      if (!context.mounted) return false;
      if (permissionGranted == PermissionStatus.denied) {
        permissionGranted = await location.requestPermission();
        if (!context.mounted) return false;
        if (permissionGranted != PermissionStatus.granted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                _copy(
                  context,
                  'Please allow location access to update delivery tracking.',
                  'يرجى السماح بالوصول للموقع لتحديث حالة التوصيل.',
                ),
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
          return false;
        }
      }
      if (permissionGranted == PermissionStatus.deniedForever) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _copy(
                context,
                'Location permission is required.',
                'صلاحية الموقع مطلوبة.',
              ),
            ),
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: _copy(context, 'Open settings', 'فتح الإعدادات'),
              onPressed: geolocator.Geolocator.openAppSettings,
            ),
          ),
        );
        return false;
      }

      return true;
    } catch (e) {
      debugPrint('Location permission handling failed: ${e.runtimeType}');
      return false;
    }
  }

  // Stop monitoring
  void stopMonitoring() {
    _isMonitoring = false;
    _periodicCheck?.cancel();
    _locationSubscription?.cancel();
    _periodicCheck = null;
    _locationSubscription = null;
    _isLocationDialogVisible = false;
  }

  // Dispose
  void dispose() {
    stopMonitoring();
  }

  String _copy(BuildContext context, String en, String ar) {
    return Localizations.localeOf(context).languageCode == 'ar' ? ar : en;
  }
}
