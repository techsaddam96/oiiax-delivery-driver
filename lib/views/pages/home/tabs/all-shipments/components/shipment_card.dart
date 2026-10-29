// import 'package:blockatie/provider/home.dart';
// import 'package:blockatie/provider/profile.dart';
// import 'package:blockatie/utils/spacing.dart';
// import 'package:flutter/material.dart';
// import 'package:provider/provider.dart';

// class ShipmentCard extends StatelessWidget {
//   final ProfileProvider profileProvider;

//   const ShipmentCard({super.key, required this.profileProvider});

//   @override
//   Widget build(BuildContext context) {
//     final profile = profileProvider.profileInfo;
//     final location = profileProvider.location ?? 'Unknown';
//     final imageWidget = profileProvider.getProfileImageWidget();

//     return Container(
//       margin: const EdgeInsets.only(top: 15),
//       padding: const EdgeInsets.all(16),
//       decoration: BoxDecoration(
//         gradient: const LinearGradient(
//           colors: [Color(0xFF2C80FC), Color(0xFF5CA8F4)],
//           begin: Alignment.topLeft,
//           end: Alignment.bottomRight,
//         ),
//         borderRadius: BorderRadius.circular(10),
//         image: const DecorationImage(
//           image: AssetImage("assets/images/balance_card_bg.png"),
//           fit: BoxFit.cover,
//         ),
//       ),
//       child: Column(
//         children: [
//           /// TOP ROW
//           Row(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             children: [
//               /// ✅ Dynamic Profile Image
//               ClipRRect(
//                 borderRadius: BorderRadius.circular(10),
//                 child: SizedBox(width: 60, height: 60, child: imageWidget),
//               ),

//               Spacing.x(2),

//               /// ✅ Driver Info
//               Expanded(
//                 child: Column(
//                   crossAxisAlignment: CrossAxisAlignment.start,
//                   children: [
//                     Text(
//                       profile?.dname ?? '---',
//                       style: const TextStyle(
//                         color: Colors.white,
//                         fontSize: 12,
//                         fontWeight: FontWeight.bold,
//                       ),
//                     ),
//                     Text(
//                       profileProvider.streetNumber ?? 'Street No 1',
//                       style: const TextStyle(color: Colors.white, fontSize: 10),
//                     ),
//                     Text(
//                       "Location: $location",
//                       style: const TextStyle(color: Colors.white, fontSize: 10),
//                     ),
//                   ],
//                 ),
//               ),

//               /// ✅ Phone + Location Icons
//               Column(
//                 crossAxisAlignment: CrossAxisAlignment.end,
//                 children: [
//                   Container(
//                     padding: const EdgeInsets.symmetric(
//                       horizontal: 10,
//                       vertical: 6,
//                     ),
//                     decoration: BoxDecoration(
//                       color: Colors.white.withValues(alpha: 0.2),
//                       borderRadius: BorderRadius.circular(10),
//                     ),
//                     child: Row(
//                       mainAxisSize: MainAxisSize.min,
//                       children: [
//                         Image.asset(
//                           'assets/images/phone.png',
//                           width: 15,
//                           height: 15,
//                         ),
//                         const SizedBox(width: 6),
//                         Text(
//                           profile?.dphone ?? '---',
//                           style: const TextStyle(
//                             color: Colors.white,
//                             fontSize: 12,
//                             overflow: TextOverflow.ellipsis,
//                           ),
//                         ),
//                       ],
//                     ),
//                   ),
//                   const SizedBox(height: 8),
//                   Container(
//                     padding: const EdgeInsets.symmetric(
//                       horizontal: 10,
//                       vertical: 6,
//                     ),
//                     decoration: BoxDecoration(
//                       color: Colors.white.withValues(alpha: 0.2),
//                       borderRadius: BorderRadius.circular(10),
//                     ),
//                     child: Row(
//                       mainAxisSize: MainAxisSize.min,
//                       children: [
//                         Image.asset(
//                           'assets/images/location.png',
//                           width: 15,
//                           height: 15,
//                         ),
//                         const SizedBox(width: 6),
//                         Text(
//                           location,
//                           style: const TextStyle(
//                             color: Colors.white,
//                             fontSize: 12,
//                           ),
//                         ),
//                       ],
//                     ),
//                   ),
//                 ],
//               ),
//             ],
//           ),

//           const SizedBox(height: 24),
//           Consumer<HomeProvider>(
//             builder: (context, provider, _) {
//               final stats = provider.driverStats;

//               if (stats == null) {
//                 return const Center(child: CircularProgressIndicator());
//               }

//               return Row(
//                 mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                 children: [
//                   Expanded(
//                     child: ShipmentStat(
//                       title: "Shipments\n",
//                       value: stats.shipments.toString(),
//                     ),
//                   ),
//                   Expanded(
//                     child: ShipmentStat(
//                       title: "Shipments In\nProgress",
//                       value: stats.shipmentsInProgress.toString(),
//                     ),
//                   ),
//                   Expanded(
//                     child: ShipmentStat(
//                       title: "Shipments Delivered",
//                       value: stats.shipmentsDelivered.toString(),
//                     ),
//                   ),
//                   Expanded(
//                     child: ShipmentStat(
//                       title: "Cancelled\nShipments",
//                       value: stats.cancelledShipments.toString(),
//                     ),
//                   ),
//                 ],
//               );
//             },
//           ),
//         ],
//       ),
//     );
//   }
// }
import 'package:blockatie/provider/home.dart';
import 'package:blockatie/provider/profile.dart';
import 'package:blockatie/utils/spacing.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';

class ShipmentCard extends StatelessWidget {
  final ProfileProvider profileProvider;

  const ShipmentCard({super.key, required this.profileProvider});

  @override
  Widget build(BuildContext context) {
    final profile = profileProvider.profileInfo;
    final location = profileProvider.location ?? 'Unknown';
    final imageWidget = profileProvider.getProfileImageWidget();

    return Container(
      margin: const EdgeInsets.only(top: 15),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2C80FC), Color(0xFF5CA8F4)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(10),
        image: const DecorationImage(
          image: AssetImage("assets/images/balance_card_bg.png"),
          fit: BoxFit.cover,
        ),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(width: 60, height: 60, child: imageWidget),
              ),
              Spacing.x(2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile?.dname ?? '---',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      profileProvider.streetNumber ?? 'street_no'.tr(),
                      style: const TextStyle(color: Colors.white, fontSize: 10),
                    ),
                    Text(
                      "${'location'.tr()}: ${profileProvider.location}",
                      style: const TextStyle(color: Colors.white, fontSize: 10),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Image.asset(
                          'assets/images/phone.png',
                          width: 15,
                          height: 15,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          profile?.dphone ?? '---',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Image.asset(
                          'assets/images/location.png',
                          width: 15,
                          height: 15,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          location,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),
          Consumer<HomeProvider>(
            builder: (context, provider, _) {
              final stats = provider.driverStats;

              if (stats == null) {
                return const Center(child: CircularProgressIndicator());
              }

              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: ShipmentStat(
                      title: "shipments".tr(),
                      value: stats.shipments.toString(),
                    ),
                  ),
                  Expanded(
                    child: ShipmentStat(
                      title: "shipments_in_progress".tr(),
                      value: stats.shipmentsInProgress.toString(),
                    ),
                  ),
                  Expanded(
                    child: ShipmentStat(
                      title: "shipments_delivered".tr(),
                      value: stats.shipmentsDelivered.toString(),
                    ),
                  ),
                  Expanded(
                    child: ShipmentStat(
                      title: tr('cancelled_shipments'),
                      value: stats.cancelledShipments.toString(),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class ShipmentStat extends StatelessWidget {
  final String title;
  final String value;

  const ShipmentStat({super.key, required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          title,
          style: const TextStyle(color: Colors.white, fontSize: 10),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
