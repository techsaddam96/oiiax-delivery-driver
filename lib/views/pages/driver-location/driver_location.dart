// // import 'dart:async';

// // import 'package:flutter/material.dart';
// // import 'package:google_maps_flutter/google_maps_flutter.dart';
// // import 'package:blockatie/constants/colors.dart';
// // import 'package:blockatie/provider/location_order.dart';
// // import 'package:blockatie/views/widgets/cutom-appbar.dart';
// // import 'package:provider/provider.dart';

// // class LocationOrderPage extends StatefulWidget {
// //   const LocationOrderPage({super.key});

// //   @override
// //   State<LocationOrderPage> createState() => _LocationOrderPageState();
// // }

// // class _LocationOrderPageState extends State<LocationOrderPage> {
// //   final Completer<GoogleMapController> _controller =
// //       Completer<GoogleMapController>();
// //   final DraggableScrollableController _scrollController =
// //       DraggableScrollableController();

// //   @override
// //   void initState() {
// //     super.initState();
// //     // Initialize provider data
// //     WidgetsBinding.instance.addPostFrameCallback((_) {
// //       Provider.of<LocationOrderProvider>(
// //         context,
// //         listen: false,
// //       ).initializeData();
// //     });
// //   }

// //   @override
// //   Widget build(BuildContext context) {
// //     return Scaffold(
// //       backgroundColor: AppColors.bgColor,
// //       appBar: const CustomAppBar(
// //         title: 'Location Order',
// //         subtitle: 'Custom order for visiting locations.',
// //         showBackBtn: false,
// //       ),
// //       body: Consumer<LocationOrderProvider>(
// //         builder: (context, provider, child) {
// //           return Stack(
// //             children: [
// //               // Google Map - Full Screen
// //               GoogleMap(
// //                 mapType: MapType.normal,
// //                 initialCameraPosition: CameraPosition(
// //                   target: provider.driverLocation,
// //                   zoom: 14.0,
// //                 ),
// //                 onMapCreated: (GoogleMapController controller) {
// //                   _controller.complete(controller);
// //                 },
// //                 markers: provider.markers,
// //                 polylines: provider.polylines,
// //                 myLocationEnabled: false,
// //                 myLocationButtonEnabled: false,
// //                 zoomControlsEnabled: false,
// //                 mapToolbarEnabled: false,
// //                 compassEnabled: false,
// //                 trafficEnabled: false,
// //               ),

// //               // Bottom Sheet
// //               DraggableScrollableSheet(
// //                 controller: _scrollController,
// //                 initialChildSize: 0.35,
// //                 minChildSize: 0.35,
// //                 maxChildSize: 0.8,
// //                 snap: true,
// //                 snapSizes: const [0.35, 0.6, 0.8],
// //                 builder: (
// //                   BuildContext context,
// //                   ScrollController scrollController,
// //                 ) {
// //                   return Container(
// //                     decoration: const BoxDecoration(
// //                       color: Colors.white,
// //                       borderRadius: BorderRadius.vertical(
// //                         top: Radius.circular(20),
// //                       ),
// //                       boxShadow: [
// //                         BoxShadow(
// //                           color: Colors.black26,
// //                           blurRadius: 10,
// //                           offset: Offset(0, -2),
// //                         ),
// //                       ],
// //                     ),
// //                     child: Column(
// //                       mainAxisSize:
// //                           MainAxisSize.min, // Use min to avoid extra space
// //                       children: [
// //                         // Handle Bar - Non-clickable
// //                         Container(
// //                           width: double.infinity,
// //                           padding: const EdgeInsets.symmetric(vertical: 12),
// //                           child: Center(
// //                             child: Container(
// //                               width: 50,
// //                               height: 4,
// //                               decoration: BoxDecoration(
// //                                 color: Colors.grey[400],
// //                                 borderRadius: BorderRadius.circular(4),
// //                               ),
// //                             ),
// //                           ),
// //                         ),

// //                         // New Order Title - Draggable
// //                         GestureDetector(
// //                           onVerticalDragUpdate: (details) {
// //                             double newSize =
// //                                 _scrollController.size -
// //                                 (details.delta.dy / context.size!.height);
// //                             newSize = newSize.clamp(0.35, 0.8);
// //                             _scrollController.jumpTo(newSize);
// //                           },
// //                           onVerticalDragEnd: (details) {
// //                             double targetSize = 0.35;
// //                             if (_scrollController.size > 0.7) {
// //                               targetSize = 0.8;
// //                             } else if (_scrollController.size > 0.475) {
// //                               targetSize = 0.6;
// //                             }
// //                             _scrollController.animateTo(
// //                               targetSize,
// //                               duration: const Duration(milliseconds: 300),
// //                               curve: Curves.easeInOut,
// //                             );
// //                           },
// //                           child: Container(
// //                             width: double.infinity,
// //                             padding: const EdgeInsets.symmetric(vertical: 8),
// //                             child: const Text(
// //                               'New Order!',
// //                               textAlign: TextAlign.center,
// //                               style: TextStyle(
// //                                 fontSize: 20,
// //                                 fontWeight: FontWeight.bold,
// //                               ),
// //                             ),
// //                           ),
// //                         ),

// //                         const SizedBox(height: 8),

// //                         // Full-width Divider
// //                         const Divider(thickness: 1, height: 1),

// //                         // Scrollable Content
// //                         Flexible(
// //                           child: SingleChildScrollView(
// //                             controller: scrollController,
// //                             padding: const EdgeInsets.all(20),
// //                             child: Column(
// //                               mainAxisSize:
// //                                   MainAxisSize.min, // Minimize column size
// //                               children: [
// //                                 // Order Distance Row
// //                                 _buildDistanceRow(provider),

// //                                 const SizedBox(height: 24),

// //                                 // Location Route
// //                                 _buildLocationRoute(provider),

// //                                 const SizedBox(height: 32),

// //                                 // Action Buttons
// //                                 _buildActionButtons(provider),
// //                               ],
// //                             ),
// //                           ),
// //                         ),
// //                       ],
// //                     ),
// //                   );
// //                 },
// //               ),

// //               // DraggableScrollableSheet(
// //               //   controller: _scrollController,
// //               //   initialChildSize: 0.35,
// //               //   minChildSize: 0.35,
// //               //   maxChildSize: 0.8,
// //               //   snap: true,
// //               //   snapSizes: const [0.35, 0.6, 0.8],
// //               //   builder: (
// //               //     BuildContext context,
// //               //     ScrollController scrollController,
// //               //   ) {
// //               //     return Container(
// //               //       decoration: const BoxDecoration(
// //               //         color: Colors.white,
// //               //         borderRadius: BorderRadius.vertical(
// //               //           top: Radius.circular(20),
// //               //         ),
// //               //         boxShadow: [
// //               //           BoxShadow(
// //               //             color: Colors.black26,
// //               //             blurRadius: 10,
// //               //             offset: Offset(0, -2),
// //               //           ),
// //               //         ],
// //               //       ),
// //               //       child: Column(
// //               //         children: [
// //               //           // Handle Bar - Make it clickable
// //               //           GestureDetector(
// //               //             onTap: () {
// //               //               // Toggle between min and expanded size
// //               //               if (_scrollController.size < 0.6) {
// //               //                 _scrollController.animateTo(
// //               //                   0.8,
// //               //                   duration: const Duration(milliseconds: 300),
// //               //                   curve: Curves.easeInOut,
// //               //                 );
// //               //               } else {
// //               //                 _scrollController.animateTo(
// //               //                   0.35,
// //               //                   duration: const Duration(milliseconds: 300),
// //               //                   curve: Curves.easeInOut,
// //               //                 );
// //               //               }
// //               //             },
// //               //             child: Container(
// //               //               width: double.infinity,
// //               //               padding: const EdgeInsets.symmetric(vertical: 12),
// //               //               child: Center(
// //               //                 child: Container(
// //               //                   width: 50,
// //               //                   height: 4,
// //               //                   decoration: BoxDecoration(
// //               //                     color: Colors.grey[400],
// //               //                     borderRadius: BorderRadius.circular(4),
// //               //                   ),
// //               //                 ),
// //               //               ),
// //               //             ),
// //               //           ),

// //               //           // New Order Title
// //               //           const Text(
// //               //             'New Order!',
// //               //             style: TextStyle(
// //               //               fontSize: 20,
// //               //               fontWeight: FontWeight.bold,
// //               //             ),
// //               //           ),

// //               //           const SizedBox(height: 8),

// //               //           // Full-width Divider
// //               //           const Divider(thickness: 1, height: 1),

// //               //           // Scrollable Content
// //               //           Expanded(
// //               //             child: SingleChildScrollView(
// //               //               controller: scrollController,
// //               //               padding: const EdgeInsets.all(20),
// //               //               child: Column(
// //               //                 children: [
// //               //                   // Order Distance Row
// //               //                   _buildDistanceRow(provider),

// //               //                   const SizedBox(height: 24),

// //               //                   // Location Route
// //               //                   _buildLocationRoute(provider),

// //               //                   const SizedBox(height: 32),

// //               //                   // Action Buttons
// //               //                   _buildActionButtons(provider),
// //               //                 ],
// //               //               ),
// //               //             ),
// //               //           ),
// //               //         ],
// //               //       ),
// //               //     );
// //               //   },
// //               // ),
// //             ],
// //           );
// //         },
// //       ),
// //     );
// //   }

// //   Widget _buildDistanceRow(LocationOrderProvider provider) {
// //     return Row(
// //       children: [
// //         Image.asset(
// //           'assets/images/order_distance.png',
// //           width: 22,
// //           height: 22,
// //           errorBuilder: (context, error, stackTrace) {
// //             return const Icon(Icons.place, size: 22, color: Colors.grey);
// //           },
// //         ),
// //         const SizedBox(width: 12),
// //         const Text("Order Distance", style: TextStyle(fontSize: 16)),
// //         const Spacer(),
// //         Text(
// //           provider.totalDistance,
// //           style: TextStyle(
// //             fontSize: 16,
// //             fontWeight: FontWeight.bold,
// //             color: Colors.red.shade600,
// //           ),
// //         ),
// //       ],
// //     );
// //   }

// //   Widget _buildLocationRoute(LocationOrderProvider provider) {
// //     return Row(
// //       crossAxisAlignment: CrossAxisAlignment.start,
// //       children: [
// //         Column(
// //           children: [
// //             Container(
// //               width: 12,
// //               height: 12,
// //               decoration: BoxDecoration(
// //                 color: Colors.green,
// //                 borderRadius: BorderRadius.circular(6),
// //               ),
// //             ),
// //             // Dotted line
// //             Container(
// //               width: 2,
// //               height: 30,
// //               margin: const EdgeInsets.symmetric(vertical: 4),
// //               child: CustomPaint(painter: DottedLinePainter()),
// //             ),
// //             Container(
// //               width: 12,
// //               height: 12,
// //               decoration: BoxDecoration(
// //                 color: Colors.red,
// //                 borderRadius: BorderRadius.circular(6),
// //               ),
// //             ),
// //           ],
// //         ),
// //         const SizedBox(width: 16),
// //         Expanded(
// //           child: Column(
// //             crossAxisAlignment: CrossAxisAlignment.start,
// //             children: [
// //               Text(
// //                 provider.pickupAddress,
// //                 style: const TextStyle(fontSize: 14, color: Colors.black87),
// //               ),
// //               const SizedBox(height: 18),
// //               Text(
// //                 provider.dropoffAddress,
// //                 style: const TextStyle(fontSize: 14, color: Colors.black87),
// //               ),
// //             ],
// //           ),
// //         ),
// //       ],
// //     );
// //   }

// //   Widget _buildActionButtons(LocationOrderProvider provider) {
// //     return Row(
// //       children: [
// //         Expanded(
// //           child: ElevatedButton(
// //             onPressed: provider.trackOrder,
// //             style: ElevatedButton.styleFrom(
// //               backgroundColor: Colors.redAccent,
// //               padding: const EdgeInsets.symmetric(vertical: 16),
// //               shape: RoundedRectangleBorder(
// //                 borderRadius: BorderRadius.circular(12),
// //               ),
// //               elevation: 0,
// //             ),
// //             child: const Text(
// //               "Track Order",
// //               style: TextStyle(
// //                 color: Colors.white,
// //                 fontSize: 16,
// //                 fontWeight: FontWeight.w600,
// //               ),
// //             ),
// //           ),
// //         ),
// //         const SizedBox(width: 16),
// //         Expanded(
// //           child: ElevatedButton(
// //             onPressed: provider.callCustomer,
// //             style: ElevatedButton.styleFrom(
// //               backgroundColor: const Color(0xFF3B60E4),
// //               padding: const EdgeInsets.symmetric(vertical: 16),
// //               shape: RoundedRectangleBorder(
// //                 borderRadius: BorderRadius.circular(12),
// //               ),
// //               elevation: 0,
// //             ),
// //             child: const Text(
// //               "Call Customer",
// //               style: TextStyle(
// //                 color: Colors.white,
// //                 fontSize: 16,
// //                 fontWeight: FontWeight.w600,
// //               ),
// //             ),
// //           ),
// //         ),
// //       ],
// //     );
// //   }
// // }

// // // CustomPainter to draw vertical dotted line
// // class DottedLinePainter extends CustomPainter {
// //   @override
// //   void paint(Canvas canvas, Size size) {
// //     const double dashHeight = 4;
// //     const double dashSpace = 4;
// //     double startY = 0;
// //     final paint =
// //         Paint()
// //           ..color = Colors.grey[400]!
// //           ..strokeWidth = 2;

// //     while (startY < size.height) {
// //       canvas.drawLine(
// //         Offset(size.width / 2, startY),
// //         Offset(size.width / 2, startY + dashHeight),
// //         paint,
// //       );
// //       startY += dashHeight + dashSpace;
// //     }
// //   }

// //   @override
// //   bool shouldRepaint(CustomPainter oldDelegate) => false;
// // }

// import 'dart:async';

// import 'package:blockatie/constants/colors.dart';
// import 'package:blockatie/provider/driver_location.dart';
// import 'package:blockatie/provider/order_detail.dart';
// import 'package:blockatie/views/pages/home/components/header.dart';
// import 'package:flutter/material.dart';
// import 'package:google_maps_flutter/google_maps_flutter.dart';
// import 'package:provider/provider.dart';

// class DriverLocationPage extends StatefulWidget {
//   const DriverLocationPage({super.key});

//   @override
//   State<DriverLocationPage> createState() => _DriverLocationPageState();
// }

// class _DriverLocationPageState extends State<DriverLocationPage> {
//   final Completer<GoogleMapController> _controller = Completer();
//   late OrderDetailProvider provider;
//   @override
//   @override
// void initState() {
//   super.initState();
//   WidgetsBinding.instance.addPostFrameCallback((_) {
//     final locationProvider = Provider.of<DriverLocationProvider>(
//       context,
//       listen: false,
//     );
//     locationProvider.initializeData(context);
//   });
// }

//   // void initState() {
//   //   super.initState();
//   //   WidgetsBinding.instance.addPostFrameCallback((_) async {
//   //     provider = Provider.of<OrderDetailProvider>(context, listen: false);
//   //     final locationProvider = Provider.of<DriverLocationProvider>(
//   //       context,
//   //       listen: false,
//   //     );

//   //     await locationProvider.initializeData(context);
//   //     updateDriverLocation();
//   //     // Move camera to driver location after initialization
//   //     final controller = await _controller.future;
//   //     controller.animateCamera(
//   //       CameraUpdate.newLatLng(locationProvider.driverLocation),
//   //     );
//   //   });
//   // }

//   void updateDriverLocation() async {
//     await provider.startDriverLocationUpdates();
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       backgroundColor: AppColors.bgColor,
//       body: Column(
//         children: [
//           const HomeHeader(notificationCount: 1),
//           Expanded(
//             child: Consumer<DriverLocationProvider>(
//               builder: (context, provider, child) {
//                 if (provider.isLoading) {
//                   return const Center(child: CircularProgressIndicator());
//                 }

//                 return GoogleMap(
//                   mapType: MapType.normal,
//                   initialCameraPosition: CameraPosition(
//                     target: provider.driverLocation,
//                     zoom: 14.0,
//                   ),
//                   onMapCreated: (GoogleMapController controller) async {
//   _controller.complete(controller);

//   final provider = Provider.of<DriverLocationProvider>(context, listen: false);

//   // Add small delay to ensure provider has data before animating
//   await Future.delayed(const Duration(milliseconds: 300));

//   controller.animateCamera(
//     CameraUpdate.newLatLng(provider.driverLocation),
//   );
// },

//                   // onMapCreated: (GoogleMapController controller) {
//                   //   _controller.complete(controller);
//                   // },
//                   markers: provider.markers,
//                   myLocationEnabled: false,
//                   myLocationButtonEnabled: false,
//                   zoomControlsEnabled: false,
//                   mapToolbarEnabled: false,
//                   compassEnabled: false,
//                   trafficEnabled: false,
//                 );
//               },
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }

import 'dart:async';
import 'package:blockatie/constants/colors.dart';
import 'package:blockatie/constants/fonts.dart';
import 'package:blockatie/provider/operational_readiness.dart';
import 'package:blockatie/provider/order_location.dart';
import 'package:blockatie/utils/time/jordan_time.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

class DriverLocationPage extends StatefulWidget {
  const DriverLocationPage({
    super.key,
    this.refreshOverride,
    this.centerOverride,
  });

  @visibleForTesting
  final Future<void> Function()? refreshOverride;
  @visibleForTesting
  final Future<void> Function()? centerOverride;

  @override
  State<DriverLocationPage> createState() => _DriverLocationPageState();
}

class _DriverLocationPageState extends State<DriverLocationPage> {
  GoogleMapController? _controller;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    if (widget.refreshOverride != null) {
      await widget.refreshOverride!();
      if (!mounted) return;
      setState(() => _refreshing = false);
      return;
    }
    final readiness = context.read<OperationalReadinessProvider>();
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    await readiness.refresh(isArabic: ar);
    if (readiness.isReady && mounted) {
      await context.read<OrderLocationProvider>().refreshCurrentLocation();
    }
    if (!mounted) return;
    setState(() => _refreshing = false);
    await _center();
  }

  Future<void> _center() async {
    if (widget.centerOverride != null) {
      await widget.centerOverride!();
      return;
    }
    final location = context.read<OrderLocationProvider>().driverLocation;
    final controller = _controller;
    if (location == null || controller == null) return;
    await controller.animateCamera(CameraUpdate.newLatLngZoom(location, 16));
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    final location = context.watch<OrderLocationProvider>();
    final readiness = context.watch<OperationalReadinessProvider>();
    final point = location.driverLocation;

    return Scaffold(
      backgroundColor: const Color(0xffF4F7FB),
      appBar: AppBar(
        title: Text(
          ar ? 'موقعي' : 'My Location',
          style: AppFonts.currentHeading.copyWith(fontSize: 20),
        ),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SizedBox(
                height: 330,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child:
                      point == null
                          ? _EmptyLocationState(
                            readiness: readiness.state,
                            isArabic: ar,
                          )
                          : GoogleMap(
                            initialCameraPosition: CameraPosition(
                              target: point,
                              zoom: 16,
                            ),
                            markers: {
                              Marker(
                                markerId: const MarkerId('driver-current'),
                                position: point,
                                infoWindow: InfoWindow(
                                  title:
                                      ar
                                          ? 'موقعي الحالي'
                                          : 'My current location',
                                ),
                              ),
                            },
                            myLocationEnabled: readiness.isReady,
                            myLocationButtonEnabled: false,
                            zoomControlsEnabled: false,
                            onMapCreated:
                                (controller) => _controller = controller,
                          ),
                ),
              ),
              const SizedBox(height: 14),
              _ReadinessCard(
                readiness: readiness,
                location: location,
                isArabic: ar,
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: point == null ? null : _center,
                      icon: const Icon(Icons.my_location_rounded),
                      label: Text(ar ? 'توسيط موقعي' : 'Center on me'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _refreshing ? null : _refresh,
                      icon:
                          _refreshing
                              ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                              : const Icon(Icons.refresh_rounded),
                      label: Text(ar ? 'تحديث' : 'Refresh'),
                    ),
                  ),
                ],
              ),
              if (readiness.state ==
                      OperationalReadinessState.locationServiceOff ||
                  readiness.state ==
                      OperationalReadinessState.locationPermissionDenied ||
                  readiness.state ==
                      OperationalReadinessState
                          .locationPermissionPermanentlyDenied) ...[
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: () => readiness.requestPermission(isArabic: ar),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xffDC2626),
                  ),
                  icon: const Icon(Icons.settings_rounded),
                  label: Text(
                    ar ? 'فتح الإعدادات المناسبة' : 'Open required settings',
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyLocationState extends StatelessWidget {
  const _EmptyLocationState({required this.readiness, required this.isArabic});
  final OperationalReadinessState readiness;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    final (icon, message) = switch (readiness) {
      OperationalReadinessState.locationServiceOff => (
        Icons.location_off_rounded,
        isArabic ? 'خدمة الموقع متوقفة' : 'Location service is off',
      ),
      OperationalReadinessState.locationPermissionDenied ||
      OperationalReadinessState.locationPermissionPermanentlyDenied => (
        Icons.location_disabled_outlined,
        isArabic ? 'صلاحية الموقع مطلوبة' : 'Location permission required',
      ),
      OperationalReadinessState.locationUnavailable => (
        Icons.gps_off_rounded,
        isArabic ? 'تعذر تحديد الموقع' : 'Location is unavailable',
      ),
      OperationalReadinessState.vpnActive => (
        Icons.vpn_lock_rounded,
        isArabic ? 'أوقف VPN لعرض موقعك' : 'Disable VPN to view your location',
      ),
      OperationalReadinessState.ready => (
        Icons.location_searching_rounded,
        isArabic ? 'جارٍ تحديد موقعك' : 'Finding your location',
      ),
    };
    return ColoredBox(
      color: const Color(0xffEAF2FC),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 52, color: const Color(0xff64748B)),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: AppFonts.currentSubheading,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReadinessCard extends StatelessWidget {
  const _ReadinessCard({
    required this.readiness,
    required this.location,
    required this.isArabic,
  });
  final OperationalReadinessProvider readiness;
  final OrderLocationProvider location;
  final bool isArabic;

  String _time(DateTime? value) {
    if (value == null) return isArabic ? 'لم يتم بعد' : 'Not yet';
    final local = JordanTime.toJordan(value);
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}:${local.second.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final stateText = switch (readiness.state) {
      OperationalReadinessState.ready =>
        isArabic ? 'الموقع يعمل بشكل طبيعي' : 'Location is working normally',
      OperationalReadinessState.locationServiceOff =>
        isArabic ? 'خدمة الموقع متوقفة' : 'Location service is off',
      OperationalReadinessState.locationPermissionDenied ||
      OperationalReadinessState.locationPermissionPermanentlyDenied =>
        isArabic ? 'صلاحية الموقع مطلوبة' : 'Location permission required',
      OperationalReadinessState.vpnActive =>
        isArabic ? 'تم اكتشاف VPN' : 'VPN detected',
      OperationalReadinessState.locationUnavailable =>
        isArabic ? 'الموقع غير متوفر' : 'Location unavailable',
    };
    final accuracy = location.locationAccuracyMeters;
    final serverSyncText = switch (location.serverSyncStatus) {
      DriverLocationServerSyncStatus.synced => _time(
        location.lastLocationSentAt,
      ),
      DriverLocationServerSyncStatus.failed =>
        isArabic ? 'تعذر تحديث الموقع على الخادم' : 'Server sync failed',
      DriverLocationServerSyncStatus.idle =>
        isArabic ? 'غير متزامن' : 'Not synced',
    };

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xffE2E8F0)),
      ),
      child: Column(
        children: [
          _row(
            Icons.gps_fixed_rounded,
            isArabic ? 'حالة GPS' : 'GPS state',
            stateText,
          ),
          _row(
            Icons.shield_outlined,
            isArabic ? 'الصلاحية' : 'Permission',
            readiness.permission.name,
          ),
          _row(
            Icons.straighten_rounded,
            isArabic ? 'دقة الموقع' : 'Accuracy',
            accuracy == null ? '—' : '±${accuracy.toStringAsFixed(0)} m',
          ),
          _row(
            Icons.schedule_rounded,
            isArabic ? 'آخر تحديث للموقع' : 'Last GPS update',
            _time(location.lastGpsFixAt),
          ),
          _row(
            Icons.cloud_done_outlined,
            isArabic ? 'مزامنة السيرفر' : 'Server sync',
            serverSyncText,
          ),
          if (location.driverLocation case final point?)
            _row(
              Icons.pin_drop_outlined,
              isArabic ? 'الإحداثيات' : 'Coordinates',
              '${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)}',
            ),
        ],
      ),
    );
  }

  Widget _row(IconData icon, String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      children: [
        Icon(icon, size: 20, color: AppColors.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: const TextStyle(color: Color(0xff475569)),
          ),
        ),
      ],
    ),
  );
}
