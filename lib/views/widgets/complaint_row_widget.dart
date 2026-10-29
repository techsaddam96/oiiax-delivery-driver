// import 'package:flutter/material.dart';
// import 'package:provider/provider.dart';
// import 'package:url_launcher/url_launcher.dart';

// import '../../constants/colors.dart';
// import '../../provider/orders.dart';
// import '../../provider/support.dart';
// import '../../utils/nav.dart';
// import '../../utils/size_config.dart';
// import '../../utils/spacing.dart';

// class ComplaintRowWidget extends StatelessWidget {
//   ComplaintRowWidget({
//     super.key,
//     required this.textTheme,
//   });

//   final TextTheme textTheme;
//   final provider = Provider.of<SupportProvider>(Nav.context, listen: false);
//   final orderPro = Provider.of<OrderStatusProvider>(Nav.context, listen: false);
//   @override
//   Widget build(BuildContext context) {
//     return Row(
//       children: [
//         // First container
//         Expanded(
//           child: InkWell(
//             onTap: () {
//               provider.openEmail('Info@gmail.com');
//             },
//             child: Container(
//               // height: SizeConfig.heightMultiplier * 7,
//               decoration: BoxDecoration(
//                 borderRadius: BorderRadius.circular(8),
//                 color: Colors.white,
//               ),
//               padding: EdgeInsets.symmetric(
//                 vertical: 13,
//                 horizontal: SizeConfig.widthMultiplier * 4,
//               ),
//               child: Row(
//                 children: [
//                   CircleAvatar(
//                     radius: SizeConfig.imageSizeMultiplier * 4.5, // fixed size
//                     backgroundColor: AppColors.primary,
//                     child: Image.asset(
//                       'assets/images/complaint.png',
//                       width: 20,
//                       height: 20,
//                       color: Colors.white,
//                     ),
//                   ),
//                   Spacing.x(2),
//                   Column(
//                     mainAxisAlignment: MainAxisAlignment.center,
//                     crossAxisAlignment: CrossAxisAlignment.start,
//                     children: [
//                       Text(
//                         'Complaint',
//                         style: textTheme.bodyMedium!
//                             .copyWith(fontWeight: FontWeight.w600),
//                       ),
//                       Text(
//                         'Chat with us',
//                         style: textTheme.bodySmall!.copyWith(
//                           fontSize: SizeConfig.textMultiplier * 1.2,
//                         ),
//                       ),
//                     ],
//                   )
//                 ],
//               ),
//             ),
//           ),
//         ),

//         Spacing.x(4),

//         // Second container
//         Expanded(
//           child: InkWell(
//             onTap: () {
//               launchUrl(
//                 Uri.parse("tel:1234567890"),
//                 mode: LaunchMode.externalApplication,
//               );
//             },
//             child: Container(
//               // height: SizeConfig.heightMultiplier * 7,

//               decoration: BoxDecoration(
//                 borderRadius: BorderRadius.circular(8),
//                 color: Colors.white,
//               ),
//               padding: EdgeInsets.symmetric(
//                   horizontal: SizeConfig.widthMultiplier * 4, vertical: 13),
//               child: Row(
//                 children: [
//                   CircleAvatar(
//                     radius: SizeConfig.imageSizeMultiplier * 4.5, // same size
//                     backgroundColor: AppColors.primary,
//                     child: Image.asset(
//                       'assets/images/phone.png',
//                       width: 20,
//                       height: 20,
//                       color: Colors.white,
//                     ),
//                   ),
//                   Spacing.x(2),
//                   Column(
//                     mainAxisAlignment: MainAxisAlignment.center,
//                     crossAxisAlignment: CrossAxisAlignment.start,
//                     children: [
//                       Text(
//                         'Contact us',
//                         style: textTheme.bodyMedium!
//                             .copyWith(fontWeight: FontWeight.w600),
//                       ),
//                       Text(
//                         'Talk to our team',
//                         style: textTheme.bodySmall!.copyWith(
//                           fontSize: SizeConfig.textMultiplier * 1.2,
//                         ),
//                       ),
//                     ],
//                   )
//                 ],
//               ),
//             ),
//           ),
//         ),
//       ],
//     );
//   }
// }

import 'package:easy_localization/easy_localization.dart'; // import easy_localization
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../constants/colors.dart';
import '../../provider/orders.dart';
import '../../provider/support.dart';
import '../../utils/nav.dart';
import '../../utils/size_config.dart';
import '../../utils/spacing.dart';

class ComplaintRowWidget extends StatelessWidget {
  ComplaintRowWidget({super.key, required this.textTheme});

  final TextTheme textTheme;
  final provider = Provider.of<SupportProvider>(Nav.context, listen: false);
  final orderPro = Provider.of<OrderStatusProvider>(Nav.context, listen: false);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // First container
        Expanded(
          child: InkWell(
            onTap: () {
              provider.openEmail('Info@gmail.com');
            },
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: Colors.white,
              ),
              padding: EdgeInsets.symmetric(
                vertical: 13,
                horizontal: SizeConfig.widthMultiplier * 4,
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: SizeConfig.imageSizeMultiplier * 4.5,
                    backgroundColor: AppColors.primary,
                    child: Image.asset(
                      'assets/images/complaint.png',
                      width: 20,
                      height: 20,
                      color: Colors.white,
                    ),
                  ),
                  Spacing.x(2),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr('complaint'),
                        style: textTheme.bodyMedium!.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        tr('chat_with_us'),
                        style: textTheme.bodySmall!.copyWith(
                          fontSize: SizeConfig.textMultiplier * 1.2,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),

        Spacing.x(4),

        // Second container
        Expanded(
          child: InkWell(
            onTap: () {
              launchUrl(
                Uri.parse("tel:1234567890"),
                mode: LaunchMode.externalApplication,
              );
            },
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: Colors.white,
              ),
              padding: EdgeInsets.symmetric(
                vertical: 13,
                horizontal: SizeConfig.widthMultiplier * 4,
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: SizeConfig.imageSizeMultiplier * 4.5,
                    backgroundColor: AppColors.primary,
                    child: Image.asset(
                      'assets/images/phone.png',
                      width: 20,
                      height: 20,
                      color: Colors.white,
                    ),
                  ),
                  Spacing.x(2),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr('contact_us'),
                        style: textTheme.bodyMedium!.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        tr('talk_to_our_team'),
                        style: textTheme.bodySmall!.copyWith(
                          fontSize: SizeConfig.textMultiplier * 1.2,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
