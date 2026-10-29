import 'dart:ui' as ui;

import 'package:blockatie/constants/colors.dart';
import 'package:blockatie/utils/spacing.dart';
import 'package:flutter/material.dart';

void showAcceptanceDilaoge(
  BuildContext context,
  String? title,
  String? subtitle,
) {
  showDialog(
    context: context,
    barrierDismissible: false, // Prevent user from dismissing manually
    builder: (BuildContext context) {
      // Auto dismiss after 3 seconds
      Future.delayed(const Duration(seconds: 3), () {
        if (Navigator.canPop(context)) {
          Navigator.pop(context);
        }
      });

      return Stack(
        children: [
          // Blurred background
          BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 5.0, sigmaY: 5.0),
            child: Container(color: Colors.black.withValues(alpha: 0.3)),
          ),
          // Dialog content
          Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20.0),
            ),
            child: Container(
              padding: const EdgeInsets.all(50.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(200),
                      color: Colors.green.shade50,
                    ),
                    child: Image.asset(
                      'assets/images/accept.png',
                      width: 50,
                      height: 50,
                    ),
                  ),
                  const SizedBox(height: 16.0),
                  Text(
                    // This dialog confirms a completed action on any screen.
                    // Its defaults were "Withdrawal Alert" and a question about
                    // a transaction, in English only — so a shipment that
                    // omitted a title announced itself as a withdrawal.
                    title ?? _genericDoneTitle(context),
                    style: TextStyle(
                      fontSize: 16.0,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue[900],
                    ),
                  ),
                  Spacing.y(1),
                  Text(
                    subtitle ?? _genericDoneBody(context),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10.0,
                      color: AppColors.textColor,
                    ),
                  ),
                  Spacing.y(1),
                ],
              ),
            ),
          ),
        ],
      );
    },
  );
}

/// Neutral title for a confirmation dialog whose caller supplied none.
String _genericDoneTitle(BuildContext context) {
  return Localizations.localeOf(context).languageCode == 'ar' ? 'تم' : 'Done';
}

/// Neutral body for a confirmation dialog whose caller supplied none.
String _genericDoneBody(BuildContext context) {
  return Localizations.localeOf(context).languageCode == 'ar'
      ? 'تم تنفيذ العملية بنجاح.'
      : 'The operation completed successfully.';
}

// void showAcceptanceDilaoge(
//   BuildContext context,
//   String? title,
//   String? subtitle,
// ) {
//   showDialog(
//     context: context,
//     barrierDismissible: true, // Prevents closing dialog by tapping outside
//     builder: (BuildContext context) {
//       return Stack(
//         children: [
//           // Blurred background
//           BackdropFilter(
//             filter: ui.ImageFilter.blur(
//               sigmaX: 5.0,
//               sigmaY: 5.0,
//             ), // Adjust blur intensity
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
//               padding: const EdgeInsets.all(50.0),
//               child: Column(
//                 mainAxisSize: MainAxisSize.min,
//                 children: [
//                   Container(
//                     padding: const EdgeInsets.all(8),
//                     decoration: BoxDecoration(
//                       borderRadius: BorderRadius.circular(200),
//                       color: Colors.green.shade50,
//                     ),
//                     child: Image.asset(
//                       'assets/images/accept.png',
//                       width: 50,
//                       height: 50,
//                     ),
//                   ),
//                   const SizedBox(height: 16.0),
//                   Text(
//                     title ?? 'Withdrawal Alert',
//                     style: TextStyle(
//                       fontSize: 16.0,
//                       fontWeight: FontWeight.bold,
//                       color: Colors.blue[900],
//                     ),
//                   ),
//                   Spacing.y(1),
//                   Text(
//                     subtitle ?? 'Do you want to make the transaction?',
//                     textAlign: TextAlign.center,
//                     style: TextStyle(
//                       fontSize: 10.0,
//                       color: AppColors.textColor,
//                     ),
//                   ),
//                   Spacing.y(1),
//                 ],
//               ),
//             ),
//           ),
//         ],
//       );
//     },
//   );
// }
