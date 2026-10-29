import 'package:blockatie/utils/address_geocoder.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// The small map thumbnail shown at the top of a shipment row.
///
/// Every shipment row used to build a full interactive [GoogleMap]. On Android
/// each one is a platform view: a native MapView with its own GL surface and
/// render thread. A list of twenty shipments therefore created twenty map
/// engines, and because the bottom navigation keeps visited tabs alive, the
/// ones from a previous tab stayed running too. That is what made moving
/// between screens stall.
///
/// This is the same picture at a fraction of the cost:
///
///   * **Lite mode** (Android) renders a static bitmap instead of starting the
///     interactive engine. It is silently ignored on iOS, where the saving
///     comes from the list building only the rows it shows.
///   * **Gestures off**, because a pannable map inside a scrolling list steals
///     the drag from the list anyway. The row stays tappable.
///
/// The full interactive map lives on the Order Location screen, which is where
/// a driver actually navigates.
class ShipmentMapPreview extends StatelessWidget {
  const ShipmentMapPreview({
    super.key,
    required this.markerId,
    required this.target,
    this.height = 120,
  });

  /// Where to centre the preview, or null when the shipment carries no usable
  /// coordinates — the preview then shows the city without a pin.
  final LatLng? target;

  final String markerId;
  final double height;

  @override
  Widget build(BuildContext context) {
    final position = target;

    return SizedBox(
      height: height,
      width: double.infinity,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: GoogleMap(
          liteModeEnabled: true,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          compassEnabled: false,
          mapToolbarEnabled: false,
          // A preview, not a controllable map: leave the gestures to the list.
          zoomGesturesEnabled: false,
          scrollGesturesEnabled: false,
          rotateGesturesEnabled: false,
          tiltGesturesEnabled: false,
          initialCameraPosition: CameraPosition(
            target: position ?? kFallbackLatLng,
            zoom: position == null ? 12 : 15,
          ),
          markers: {
            if (position != null)
              Marker(
                markerId: MarkerId(markerId),
                position: position,
                icon: BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueRed,
                ),
              ),
          },
        ),
      ),
    );
  }
}
