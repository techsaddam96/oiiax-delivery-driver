import 'package:blockatie/utils/address_geocoder.dart';
import 'package:blockatie/utils/nav.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

import '../provider/localization.dart';

mixin Helper {
  String getLocalizedTypeName(String typeName, String? arName) {
    final provider = Provider.of<LocaleProvider>(Nav.context, listen: false);
    if (provider.isArabic && arName != null && arName.isNotEmpty) {
      return arName;
    }
    return typeName;
  }

  /// One geocode per address, shared app-wide.
  ///
  /// This used to hit the geocoder on every call. Callers drive it from list
  /// rows, so the same few addresses were resolved over and over while the
  /// driver scrolled and switched tabs. [AddressGeocoder] keeps the answer and
  /// de-duplicates concurrent lookups; the behaviour on failure is unchanged
  /// (Amman, never a throw).
  Future<LatLng> getCoordinatesFromAddress(String address) =>
      AddressGeocoder.resolve(address);

  // if (AppLocalizations.isRTL && arName != null && arName.isNotEmpty) {
  //   return arName;
  // }
  // return typeName;
  //}
}
