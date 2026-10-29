import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:geocoding/geocoding.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Amman. Used whenever an address cannot be resolved, so a tile still has a
/// map to show instead of an error or a spinner that never ends.
const LatLng kFallbackLatLng = LatLng(31.9539, 35.9106);

/// Resolves a postal address to coordinates once per address, app-wide.
///
/// The shipment tiles used to call `locationFromAddress` straight out of
/// `build()`, through `FutureBuilder(future: getCoordinatesFromAddress(...))`.
/// A `future` built inside `build` is rebuilt with the widget, so every
/// provider notification, every `setState` and every tab switch started a
/// fresh network geocode for every visible row. The requests queued behind
/// each other and the UI stalled — and it got worse the longer the driver
/// navigated, because nothing ever settled.
///
/// Two things fix that: an address is looked up once and remembered, and rows
/// asking for the same address at the same time share one in-flight request
/// instead of starting one each.
class AddressGeocoder {
  AddressGeocoder._();

  /// Lookups that have not answered yet, keyed by address.
  static final Map<String, Future<LatLng>> _inFlight = {};

  /// Answers already received. Never expires: a street address does not move,
  /// and the map is bounded by how many distinct addresses one driver sees.
  static final Map<String, LatLng> _resolved = {};

  /// The coordinates for [address] if they are already known, else null.
  ///
  /// Lets a tile paint its map on the first frame instead of showing a spinner
  /// for an address that was resolved earlier in the session.
  static LatLng? cached(String address) => _resolved[_key(address)];

  /// The coordinates for [address], resolving it at most once.
  ///
  /// Never throws: a failed or empty lookup resolves to [kFallbackLatLng].
  static Future<LatLng> resolve(String address) {
    final key = _key(address);

    final known = _resolved[key];
    if (known != null) return Future<LatLng>.value(known);

    return _inFlight[key] ??= _lookup(key)
        .then((value) {
          _resolved[key] = value;
          return value;
        })
        .whenComplete(() {
          // A block body on purpose. `=> _inFlight.remove(key)` returns the
          // removed Future — which is this very future — and whenComplete
          // waits on whatever its callback returns, so the arrow form
          // deadlocks and resolve() never completes.
          _inFlight.remove(key);
        });
  }

  /// Replaces the platform geocoder in tests.
  ///
  /// Without this a unit test has no geocoding channel, so `locationFromAddress`
  /// never completes and the test hangs rather than failing.
  @visibleForTesting
  static Future<LatLng> Function(String address)? debugLookupOverride;

  static Future<LatLng> _lookup(String key) async {
    if (key.isEmpty) return kFallbackLatLng;
    try {
      final override = debugLookupOverride;
      if (override != null) return await override(key);

      final locations = await locationFromAddress(key);
      if (locations.isEmpty) return kFallbackLatLng;
      return LatLng(locations.first.latitude, locations.first.longitude);
    } catch (_) {
      // A geocoder that is unavailable, rate-limited or given an address it
      // cannot parse must not surface as an error inside a list row.
      return kFallbackLatLng;
    }
  }

  static String _key(String address) => address.trim();

  @visibleForTesting
  static void resetForTesting() {
    _inFlight.clear();
    _resolved.clear();
    debugLookupOverride = null;
  }

  @visibleForTesting
  static void seedForTesting(String address, LatLng value) {
    _resolved[_key(address)] = value;
  }
}
