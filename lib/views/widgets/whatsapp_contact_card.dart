// import 'package:blockatie/constants/colors.dart';
// import 'package:blockatie/provider/support.dart';
// import 'package:blockatie/utils/nav.dart';
// import 'package:flutter/material.dart';
// import 'package:provider/provider.dart';

// import '../../utils/spacing.dart';

// class WhatsappContactCard extends StatelessWidget {
//   WhatsappContactCard({super.key, required this.textTheme});

//   final TextTheme textTheme;
//   final provider = Provider.of<SupportProvider>(Nav.context, listen: false);
//   @override
//   Widget build(BuildContext context) {
//     return InkWell(
//       onTap: () {
//         provider.openWhatsApp(
//           phoneNumber: '962779735616',
//           message: 'How may I help you?',
//         );
//       },
//       child: Container(
//         padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 15),
//         decoration: BoxDecoration(
//           color: AppColors.primary,
//           borderRadius: BorderRadius.circular(8),
//         ),
//         child: Row(
//           children: [
//             CircleAvatar(
//               backgroundColor: Colors.white,
//               radius: 18,
//               child: Image.asset(
//                 'assets/images/logos_whatsapp-icon.png',
//                 height: 20,
//                 width: 20,
//               ),
//             ),
//             Spacing.x(3),
//             Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               children: [
//                 Text(
//                   'WhatsApp',
//                   style: textTheme.bodyLarge!.copyWith(
//                     fontWeight: FontWeight.w600,
//                     color: Colors.white,
//                   ),
//                 ),
//                 Text(
//                   'All your question will be answered here.',
//                   style: textTheme.bodyMedium!.copyWith(color: Colors.white),
//                 ),
//               ],
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }

import 'package:blockatie/constants/colors.dart';
import 'package:blockatie/provider/support.dart';
import 'package:blockatie/utils/nav.dart';
import 'package:easy_localization/easy_localization.dart'; // Add this
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../utils/spacing.dart';

class WhatsappContactCard extends StatelessWidget {
  WhatsappContactCard({super.key, required this.textTheme});

  final TextTheme textTheme;
  final provider = Provider.of<SupportProvider>(Nav.context, listen: false);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        provider.openWhatsApp(
          phoneNumber: '962779735616',
          message: tr('whatsappDescription'),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 15),
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: Colors.white,
              radius: 18,
              child: Image.asset(
                'assets/images/logos_whatsapp-icon.png',
                height: 20,
                width: 20,
              ),
            ),
            Spacing.x(3),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr('whatsapp'),
                  style: textTheme.bodyLarge!.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                Text(
                  tr('whatsappDescription'),
                  style: textTheme.bodyMedium!.copyWith(color: Colors.white),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
