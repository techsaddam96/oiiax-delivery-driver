// import 'package:blockatie/constants/colors.dart';
// import 'package:blockatie/utils/spacing.dart';
// import 'package:flutter/material.dart';

// Widget buildTransactionItem(
//   String type,
//   String amount,
//   String date,
//   String method,
//   bool isCompleted,
//   String? status,
//   // String? iconpath,
// ) {
//   // final textTheme = Theme.of(Nav.context).textTheme;
//   return Container(
//     margin: const EdgeInsets.only(bottom: 12),
//     padding: const EdgeInsets.all(10),
//     decoration: BoxDecoration(
//       color: Colors.white54,
//       borderRadius: BorderRadius.circular(12),
//       boxShadow: [
//         BoxShadow(
//           color: Colors.grey.withValues(alpha: 0.1),
//           spreadRadius: 1,
//           blurRadius: 4,
//           offset: const Offset(0, 2),
//         ),
//       ],
//     ),
//     child: Row(
//       children: [
//         Container(
//           width: 40,
//           height: 40,
//           padding: const EdgeInsets.all(12),
//           decoration: BoxDecoration(
//             color: Colors.white,
//             borderRadius: BorderRadius.circular(12),
//           ),
//           child: Image.asset(
//             'assets/images/downarrow.png',
//             width: 15,
//             height: 15,
//           ),
//         ),
//         const SizedBox(width: 16),
//         Expanded(
//           child: Column(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             children: [
//               Text(
//                 type,
//                 style: TextStyle(
//                   fontSize: 12,
//                   fontWeight: FontWeight.w500,
//                   color: AppColors.textColor,
//                 ),
//               ),
//               const SizedBox(height: 4),
//               Text(
//                 amount,
//                 style: const TextStyle(
//                   fontSize: 14,
//                   fontWeight: FontWeight.bold,
//                   color: Colors.black,
//                 ),
//               ),
//               const SizedBox(height: 4),
//               Text(
//                 date,
//                 style: TextStyle(fontSize: 10, color: AppColors.textColor),
//               ),
//             ],
//           ),
//         ),
//         Column(
//           crossAxisAlignment: CrossAxisAlignment.end,
//           children: [
//             Text(
//               method,
//               style: TextStyle(
//                 fontSize: 12,
//                 color: AppColors.textColor,
//                 fontWeight: FontWeight.w500,
//               ),
//             ),
//             Spacing.y(0.3),
//             Container(
//               padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
//               decoration: BoxDecoration(
//                 color: Colors.green.withValues(alpha: 0.1),
//                 borderRadius: BorderRadius.circular(4),
//               ),
//               child: Row(
//                 mainAxisSize: MainAxisSize.min,
//                 children: [
//                   Icon(
//                     Icons.check_circle_outline,
//                     color: Colors.green,
//                     size: 12,
//                   ),

//                   Spacing.x(1),
//                   Text(
//                     status ?? '',
//                     // tr('completed'),
//                     style: TextStyle(
//                       color: Colors.green,
//                       fontSize: 10,
//                       fontWeight: FontWeight.w500,
//                     ),
//                   ),
//                 ],
//               ),
//             ),
//           ],
//         ),
//       ],
//     ),
//   );
// }

import 'package:blockatie/constants/colors.dart';
import 'package:blockatie/utils/spacing.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

Widget buildTransactionItem(
  String type,
  String amount,
  String date,
  String method,
  bool isCompleted, {
  String? status,
  Color? statusColor,
}) {
  // Ensure all parameters are valid strings
  final safeType = type.toString();
  final safeAmount = amount.toString();
  final safeDate = date.toString();
  final safeMethod = method.toString();

  // Get localized status text
  String getLocalizedStatus() {
    if (status != null) return tr(status.toLowerCase());
    if (isCompleted) {
      return tr('completed');
    } else {
      return tr('pending');
    }
  }

  // Get localized method text
  String getLocalizedMethod() {
    if (safeMethod.toLowerCase() == 'cash') {
      return tr('cash');
    } else if (safeMethod.toLowerCase().contains('bank')) {
      return tr('bank');
    }
    return safeMethod;
  }

  // final textTheme = Theme.of(Nav.context).textTheme;
  return Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: Colors.white54,
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
    child: Row(
      children: [
        Container(
          width: 40,
          height: 40,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Image.asset('assets/images/downarrow.png', width: 15),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                safeType,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textColor,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                safeAmount,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                safeDate,
                style: TextStyle(fontSize: 10, color: AppColors.textColor),
              ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              getLocalizedMethod(),
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textColor,
                fontWeight: FontWeight.w500,
              ),
            ),
            Spacing.y(0.3),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: (statusColor ?? Colors.green).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isCompleted ? Icons.check_circle_outline : Icons.pending,
                    color: statusColor ?? Colors.green,
                    size: 12,
                  ),
                  Spacing.x(1),
                  Text(
                    getLocalizedStatus(),
                    style: TextStyle(
                      color: statusColor ?? Colors.green,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    ),
  );
}
