// import 'package:blockatie/constants/colors.dart';
// import 'package:blockatie/provider/orders.dart';
// import 'package:blockatie/utils/nav.dart';
// import 'package:blockatie/utils/size_config.dart';
// import 'package:blockatie/utils/spacing.dart';
// import 'package:flutter/material.dart';
// import 'package:provider/provider.dart';
// import 'package:url_launcher/url_launcher.dart';

// import 'status_indicator.dart';

// class StoreDeliveryDetails extends StatelessWidget {
//   const StoreDeliveryDetails({super.key, this.deliveryAdd, this.storeAdd});
//   final String? storeAdd;
//   final String? deliveryAdd;
//   @override
//   Widget build(BuildContext context) {
//     final textTheme = Theme.of(Nav.context).textTheme;
//     final provider = Provider.of<OrderStatusProvider>(context, listen: false);
//     return Container(
//       margin: const EdgeInsets.symmetric(horizontal: 16),
//       padding: const EdgeInsets.all(16),
//       decoration: BoxDecoration(
//         color: Colors.white,
//         borderRadius: BorderRadius.circular(12),
//         boxShadow: [
//           BoxShadow(
//             color: Colors.grey.withValues(alpha: 0.1),
//             spreadRadius: 1,
//             blurRadius: 5,
//             offset: const Offset(0, 2),
//           ),
//         ],
//       ),
//       child: IntrinsicHeight(
//         child: Row(
//           crossAxisAlignment: CrossAxisAlignment.start,
//           children: [
//             Column(
//               children: [
//                 StatusIndicator(
//                   containersize: 30,
//                   radius: 8,
//                   iconColor: AppColors.primary,
//                   continercolor: AppColors.bgColor,
//                   iconsize: 15,
//                   icon: 'assets/images/store_detail.png',
//                   label: '',
//                   isActive: false,
//                   isCompleted: false,
//                   showLabel: false,
//                 ),
//                 Container(
//                   width: 1.5,
//                   height: 40,
//                   margin: const EdgeInsets.symmetric(vertical: 3),
//                   decoration: BoxDecoration(
//                     color: AppColors.primary,
//                     borderRadius: BorderRadius.circular(1),
//                   ),
//                 ),
//                 StatusIndicator(
//                   containersize: 30,
//                   radius: 8,
//                   iconColor: AppColors.primary,
//                   continercolor: AppColors.bgColor,
//                   iconsize: 15,
//                   icon: 'assets/images/deliverydetail.png',
//                   label: '',
//                   isActive: false,
//                   isCompleted: false,
//                   showLabel: false,
//                 ),
//               ],
//             ),
//             const SizedBox(width: 12),
//             Expanded(
//               child: Column(
//                 crossAxisAlignment: CrossAxisAlignment.start,
//                 children: [
//                   Row(
//                     children: [
//                       Expanded(
//                         child: Column(
//                           crossAxisAlignment: CrossAxisAlignment.start,
//                           children: [
//                             Text(
//                               'Store Details',
//                               style: textTheme.bodyLarge!.copyWith(
//                                 fontWeight: FontWeight.w600,
//                                 letterSpacing: 0.3,
//                               ),
//                             ),
//                             Spacing.y(.2),
//                             Text(
//                               storeAdd ??
//                                   'Sunny Mart is located at 1234 Maplewood Lane, Springfield, California, 90210.',
//                               style: textTheme.bodySmall!.copyWith(
//                                 letterSpacing: -0.3,
//                                 fontSize: 10,
//                                 color: AppColors.textColor,
//                               ),
//                             ),
//                           ],
//                         ),
//                       ),
//                       InkWell(
//                         onTap: () async {
//                           await launchUrl(
//                             Uri.parse("tel:1234567890"),
//                             mode: LaunchMode.externalApplication,
//                           );
//                         },
//                         child: CircleAvatar(
//                           radius: 13,
//                           backgroundColor: Colors.green,
//                           child: Image.asset(
//                             'assets/images/phone.png',
//                             width: 12,
//                             height: 12,
//                           ),
//                         ),
//                       ),
//                     ],
//                   ),
//                   const SizedBox(height: 32),
//                   Text(
//                     'Delivery Details',
//                     style: textTheme.bodyLarge!.copyWith(
//                       fontWeight: FontWeight.w600,
//                       letterSpacing: 0.3,
//                     ),
//                   ),
//                   Spacing.y(.2),
//                   SizedBox(
//                     width: SizeConfig.widthMultiplier * 60,
//                     child: Text(
//                       deliveryAdd ??
//                           '789 Oakridge Avenue, Apartment 5B, in the Maple Heights Complex, located in the northern district of Rivertown, New York, 10027, United States.',
//                       style: textTheme.bodySmall!.copyWith(
//                         letterSpacing: -0.3,
//                         fontSize: 10,
//                         color: AppColors.textColor,
//                       ),
//                     ),
//                   ),
//                 ],
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }

import 'package:blockatie/constants/colors.dart';
import 'package:blockatie/utils/nav.dart';
import 'package:blockatie/utils/size_config.dart';
import 'package:blockatie/utils/spacing.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:easy_localization/easy_localization.dart';

import 'status_indicator.dart';

class StoreDeliveryDetails extends StatelessWidget {
  const StoreDeliveryDetails({
    super.key,
    this.deliveryAdd,
    this.storeAdd,
    this.phoneStore,
  });

  final String? storeAdd;
  final String? deliveryAdd;
  final String? phoneStore;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(Nav.context).textTheme;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.1),
            spreadRadius: 1,
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              children: [
                StatusIndicator(
                  containersize: 30,
                  radius: 8,
                  iconColor: AppColors.primary,
                  continercolor: AppColors.bgColor,
                  iconsize: 15,
                  icon: 'assets/images/store_detail.png',
                  label: '',
                  isActive: false,
                  isCompleted: false,
                  showLabel: false,
                ),
                Container(
                  width: 1.5,
                  height: 40,
                  margin: const EdgeInsets.symmetric(vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
                StatusIndicator(
                  containersize: 30,
                  radius: 8,
                  iconColor: AppColors.primary,
                  continercolor: AppColors.bgColor,
                  iconsize: 15,
                  icon: 'assets/images/deliverydetail.png',
                  label: '',
                  isActive: false,
                  isCompleted: false,
                  showLabel: false,
                ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              tr('storeDetails'),
                              style: textTheme.bodyLarge!.copyWith(
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.3,
                              ),
                            ),
                            Spacing.y(.2),
                            Text(
                              storeAdd ?? tr('defaultStoreAddress'),
                              style: textTheme.bodySmall!.copyWith(
                                letterSpacing: -0.3,
                                fontSize: 10,
                                color: AppColors.textColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                      InkWell(
                        onTap: () async {
                          await launchUrl(
                            Uri.parse("tel:${phoneStore ?? ''}"),
                            mode: LaunchMode.externalApplication,
                          );
                        },
                        child: CircleAvatar(
                          radius: 13,
                          backgroundColor: Colors.green,
                          child: Image.asset(
                            'assets/images/phone.png',
                            width: 12,
                            height: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tr('deliveryDetails'),
                          style: textTheme.bodyLarge!.copyWith(
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.3,
                          ),
                        ),
                        Spacing.y(.2),
                        Expanded(
                          child: SizedBox(
                            width: SizeConfig.widthMultiplier * 60,
                            child: Text(
                              deliveryAdd ?? tr('defaultDeliveryAddress'),
                              style: textTheme.bodySmall!.copyWith(
                                letterSpacing: -0.3,
                                fontSize: 10,
                                color: AppColors.textColor,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
