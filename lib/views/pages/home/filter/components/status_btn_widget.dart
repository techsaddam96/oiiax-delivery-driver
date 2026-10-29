// import 'package:blockatie/constants/colors.dart';
// import 'package:flutter/material.dart';

// class CustomStatusButton extends StatelessWidget {
//   final String label;
//   final bool selected;
//   final VoidCallback? onTap;

//   const CustomStatusButton({
//     super.key,
//     required this.label,
//     required this.selected,
//     this.onTap,
//   });

//   @override
//   Widget build(BuildContext context) {
//     return GestureDetector(
//       onTap: onTap,
//       child: Container(
//         padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
//         decoration: BoxDecoration(
//           color: selected ? AppColors.primary : const Color(0xFFF5F6FA),
//           borderRadius: BorderRadius.circular(10),
//           border: Border.all(color: Colors.grey.shade300),
//         ),
//         child: Text(
//           label,
//           style: TextStyle(
//             color: selected ? Colors.white : Colors.black87,
//             fontWeight: FontWeight.w500,
//           ),
//         ),
//       ),
//     );
//   }
// }

import 'package:blockatie/constants/colors.dart';
import 'package:flutter/material.dart';

class CustomStatusButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  const CustomStatusButton({
    super.key,
    required this.label,
    required this.selected,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : const Color(0xFFF5F6FA),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? AppColors.primary : Colors.grey.shade300,
            width: selected ? 2 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.black87,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}
