import 'dart:async';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geocoding/geocoding.dart';
import 'package:blockatie/constants/colors.dart';
import 'package:blockatie/utils/spacing.dart';
import 'package:blockatie/views/widgets/cutom-appbar.dart';

class LocationPickerPage extends StatefulWidget {
  final double? initialLatitude;
  final double? initialLongitude;
  final Function(double latitude, double longitude, String address)
  onLocationSelected;

  const LocationPickerPage({
    super.key,
    this.initialLatitude,
    this.initialLongitude,
    required this.onLocationSelected,
  });

  @override
  State<LocationPickerPage> createState() => _LocationPickerPageState();
}

class _LocationPickerPageState extends State<LocationPickerPage> {
  late Completer<GoogleMapController> _mapController;
  late CameraPosition _cameraPosition;

  LatLng _selectedLocation = const LatLng(
    31.9539,
    35.9106,
  ); // Default to Amman, Jordan
  String _selectedAddress = '';
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _cameraPosition = CameraPosition(target: _selectedLocation, zoom: 11);

    _mapController = Completer();
    if (widget.initialLatitude != null && widget.initialLongitude != null) {
      _selectedLocation = LatLng(
        widget.initialLatitude!,
        widget.initialLongitude!,
      );
      _getAddressFromCoordinates(_selectedLocation);
    }
  }

  Future<void> _getAddressFromCoordinates(LatLng position) async {
    setState(() {
      _isLoading = true;
    });

    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      if (placemarks.isNotEmpty) {
        Placemark place = placemarks[0];
        String address = [
          place.street,
          place.subLocality,
          place.locality,
          place.administrativeArea,
          place.country,
        ].where((element) => element != null && element.isNotEmpty).join(', ');

        if (!mounted) return;
        setState(() {
          _selectedAddress = address;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _selectedAddress = tr('location_selected');
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _confirmLocation() {
    widget.onLocationSelected(
      _selectedLocation.latitude,
      _selectedLocation.longitude,
      _selectedAddress,
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgColor,
      appBar: CustomAppBar(
        title: tr('select_location'),
        subtitle: tr('tap_on_map_to_select_your_location'),
        showBtn: false,
      ),
      body: Column(
        children: [
          // Map Container
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withValues(alpha: 0.2),
                    spreadRadius: 2,
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                // child: FlutterMap(
                //   mapController: _mapController,
                //   options: MapOptions(
                //     initialCenter: _selectedLocation,
                //     initialZoom: 15,
                //     onTap: (tapPosition, point) {
                //       setState(() {
                //         _selectedLocation = point;
                //       });
                //       _getAddressFromCoordinates(point);
                //     },
                //   ),
                //   children: [
                //     TileLayer(
                //       urlTemplate:
                //           'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                //       userAgentPackageName: 'com.example.app',
                //     ),
                //     MarkerLayer(
                //       markers: [
                //         Marker(
                //           point: _selectedLocation,
                //           width: 40,
                //           height: 40,
                //           child: GestureDetector(
                //             onPanUpdate: (details) {
                //               // Handle marker drag if needed
                //             },
                //             child: Container(
                //               decoration: BoxDecoration(
                //                 color: AppColors.primary,
                //                 shape: BoxShape.circle,
                //                 border: Border.all(
                //                   color: Colors.white,
                //                   width: 2,
                //                 ),
                //                 boxShadow: [
                //                   BoxShadow(
                //                     color: Colors.black.withValues(alpha: 0.3),
                //                     spreadRadius: 1,
                //                     blurRadius: 4,
                //                     offset: const Offset(0, 2),
                //                   ),
                //                 ],
                //               ),
                //               child: const Icon(
                //                 Icons.location_on,
                //                 color: Colors.white,
                //                 size: 24,
                //               ),
                //             ),
                //           ),
                //         ),
                //       ],
                //     ),
                //   ],
                // ),
                child: GoogleMap(
                  markers: {
                    Marker(
                      markerId: MarkerId('value'),
                      position: _selectedLocation,
                    ),
                  },
                  mapType: MapType.normal,
                  onTap: (position) {
                    setState(() {
                      _selectedLocation = position;
                    });
                    _getAddressFromCoordinates(_selectedLocation);
                  },
                  onCameraIdle: () {},
                  onCameraMove: (position) {},
                  onMapCreated: (controller) {
                    _mapController.complete(controller);
                  },
                  initialCameraPosition: _cameraPosition,
                ),
              ),
            ),
          ),

          // Location Info Card
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withValues(alpha: 0.1),
                  spreadRadius: 1,
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.location_on, color: AppColors.primary, size: 20),
                    Spacing.x(1),
                    Text(
                      tr('select_location'),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
                Spacing.y(1),
                if (_isLoading)
                  Row(
                    children: [
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      Spacing.x(1),
                      Text(tr('getting_address')),
                    ],
                  )
                else
                  Text(
                    _selectedAddress.isNotEmpty
                        ? _selectedAddress
                        : tr('tap_on_map_to_select_location'),
                    style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                  ),
                Spacing.y(1),
                Text(
                  '${tr('coordinates')}: ${_selectedLocation.latitude.toStringAsFixed(6)}, ${_selectedLocation.longitude.toStringAsFixed(6)}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                ),
                Spacing.y(2),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed:
                        _selectedAddress.isNotEmpty ? _confirmLocation : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      tr('confirm_location'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
