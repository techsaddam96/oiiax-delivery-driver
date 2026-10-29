// import 'dart:ui' as ui;

// import 'package:blockatie/constants/colors.dart';
// import 'package:blockatie/utils/spacing.dart';
// import 'package:blockatie/views/widgets/custom_elevated_btn.dart';
// import 'package:flutter/material.dart';

// void showAlertDialog(BuildContext context,String? title, String? subtitle,) {
//   showDialog(
//     context: context,
//     barrierDismissible: false, // Prevents closing dialog by tapping outside
//     builder: (BuildContext context) {
//       return Stack(
//         children: [
//           // Blurred background
//           BackdropFilter(
//             filter: ui.ImageFilter.blur(
//                 sigmaX: 5.0, sigmaY: 5.0), // Adjust blur intensity
//             child: Container(
//               color: Colors.black.withValues(alpha: 0.3), // Semi-transparent overlay
//             ),
//           ),
//           // Dialog content
//           Dialog(
//             shape: RoundedRectangleBorder(
//               borderRadius: BorderRadius.circular(20.0),
//             ),
//             child: Container(
//               padding: const EdgeInsets.all(16.0),
//               child: Column(
//                 mainAxisSize: MainAxisSize.min,
//                 children: [
//                   Image.asset(
//                     'assets/images/alert.png',
//                     width: 70,
//                     height: 70,
//                   ),
//                   const SizedBox(height: 16.0),
//                   Text(
//                   title??  'Withdrawal Alert',
//                     style: TextStyle(
//                       fontSize: 20.0,
//                       fontWeight: FontWeight.bold,
//                       color: Colors.blue[900],
//                     ),
//                   ),
//                   Spacing.y(2),
//                   Text(
//                    subtitle?? 'Do you want to make the transaction?',
//                     textAlign: TextAlign.center,
//                     style: const TextStyle(fontSize: 14.0),
//                   ),
//                   Spacing.y(3),
//                   CustomElevatedBtn(
//                     label: 'Ok',
//                     bgColor: AppColors.primary,
//                     textColor: Colors.white,
//                     onTap: () {
//                       Navigator.pop(context);
//                     },
//                   ),
//                 ],
//               ),
//             ),
//           ),
//         ],
//       );
//     },
//   );
// }

import 'dart:ui' as ui;

import 'package:blockatie/constants/colors.dart';
import 'package:blockatie/utils/spacing.dart';
import 'package:blockatie/views/widgets/custom_elevated_btn.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

void showAlertDialog(
  BuildContext context,
  String? title,
  String? subtitle, {
  bool showBtn = true,
  VoidCallback? ontap,
}) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext dialogContext) {
      if (!showBtn) {
        Future.delayed(const Duration(seconds: 2), () {
          if (Navigator.canPop(dialogContext)) {
            Navigator.of(dialogContext).pop();
          }
        });
      }

      return Stack(
        children: [
          // Blurred background
          BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 5.0, sigmaY: 5.0),
            child: Container(color: Colors.black.withValues(alpha: 0.3)),
          ),
          Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 25,
            ), // 👈 full width padding
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 40),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset('assets/images/alert.png', width: 70, height: 70),
                  const SizedBox(height: 16.0),
                  Text(
                    // Keys are case-sensitive; the English literals
                    // that used to sit here reached Arabic users verbatim.
                    title ?? tr('alertTitle'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 20.0,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue[900],
                    ),
                  ),
                  Spacing.y(2),
                  Text(
                    subtitle ?? tr('alertSubtitle'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 14.0),
                  ),
                  if (showBtn) ...[
                    Spacing.y(3),
                    CustomElevatedBtn(
                      label: tr('ok'),
                      bgColor: AppColors.primary,
                      textColor: Colors.white,
                      // `() => ontap ?? Navigator.pop(...)` returned the
                      // callback instead of calling it, and skipped the pop:
                      // with barrierDismissible false, any caller passing
                      // `ontap` produced a dialog that could not be closed.
                      //
                      // The dialog closes first either way, so a callback that
                      // navigates is not fighting a dialog that is still up.
                      onTap: () {
                        Navigator.pop(dialogContext);
                        ontap?.call();
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      );
    },
  );
}
