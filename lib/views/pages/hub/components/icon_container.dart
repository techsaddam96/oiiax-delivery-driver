// import 'package:blockatie/constants/colors.dart';
// import 'package:flutter/material.dart';

// class IconContainerWidget extends StatelessWidget {
//   const IconContainerWidget(
//       {super.key, required this.icon, this.color, this.label, this.ontap});
//   final String icon;
//   final Color? color;
//   final String? label;
//   final VoidCallback? ontap;
//   @override
//   Widget build(BuildContext context) {
//     final textTheme = Theme.of(context).textTheme;
//     return InkWell(
//       onTap: ontap,
//       child: Column(
//         children: [
//           Container(
//             padding: const EdgeInsets.all(12),
//             decoration: BoxDecoration(
//                 color: color ?? AppColors.blue,
//                 borderRadius: BorderRadius.circular(10)),
//             child: Image.asset(
//               icon,
//               width: 20,
//               height: 20,
//             ),
//           ),
//           Text(
//               textAlign: TextAlign.center,
//               label ?? '',
//               style: textTheme.bodyMedium!
//                   .copyWith(color: Colors.black, fontWeight: FontWeight.w500))
//         ],
//       ),
//     );
//   }
// }

import 'package:blockatie/constants/colors.dart';
import 'package:blockatie/utils/size_config.dart';
import 'package:flutter/material.dart';

class IconContainerWidget extends StatelessWidget {
  const IconContainerWidget({
    super.key,
    required this.icon,
    this.color,
    this.label,
    this.ontap,
  });

  final String icon;
  final Color? color;
  final String? label;
  final VoidCallback? ontap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return InkWell(
      onTap: ontap,
      borderRadius: BorderRadius.circular(10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: SizeConfig.widthMultiplier * 13,
            height: SizeConfig.heightMultiplier * 6,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color ?? AppColors.primary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Image.asset(
              icon,
              width: 28,
              height: 28,
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(height: 8),
          if (label != null)
            SizedBox(
              width: 80,
              child: Text(
                label!,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodySmall!.copyWith(
                  color: Colors.black87,
                  fontWeight: FontWeight.w500,
                  fontSize: 11,
                  height: 1.2,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
