import 'package:blockatie/provider/profile.dart';
import 'package:blockatie/services/user_session_state.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

class DriverLocationProvider extends UserScopedNotifier {
  static const LatLng _defaultLocation = LatLng(36.1707, -115.1394);

  LatLng driverLocation = _defaultLocation;
  bool isLoading = true;
  Set<Marker> markers = {};

  // Coordinates identify a driver; they must not carry into another account.
  @override
  void clearUserState() {
    driverLocation = _defaultLocation;
    isLoading = true;
    markers = {};
  }

  Future<void> initializeData(BuildContext context) async {
    try {
      final profileProvider = Provider.of<ProfileProvider>(
        context,
        listen: false,
      );

      await profileProvider.fetchDriverProfile();
      final driverInfo = profileProvider.profileInfo;

      if (driverInfo != null) {
        final lat = double.tryParse(driverInfo.latitude);
        final lng = double.tryParse(driverInfo.longitude);

        if (lat != null && lng != null) {
          driverLocation = LatLng(lat, lng);
        }

        createDriverMarker();
      }
    } catch (e) {
      debugPrint('Driver location initialization failed: ${e.runtimeType}');
    }

    isLoading = false;
    notifyListeners();
  }

  void createDriverMarker() {
    markers = {
      Marker(
        markerId: const MarkerId('driver'),
        position: driverLocation,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: const InfoWindow(
          title: 'Hero Location',
          snippet: 'Current hero position',
        ),
      ),
    };
  }
}
