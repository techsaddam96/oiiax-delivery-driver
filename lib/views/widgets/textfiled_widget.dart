// import 'package:blockatie/utils/size_config.dart';
// import 'package:flutter/material.dart';

// class TextFiledWidget extends StatelessWidget {
//   final String hint;
//   final IconData? icon;
//   final bool suffixIcon;
//   final bool isLocationField;
//   final VoidCallback? ontap;
//   final bool isEnabled;
//   final TextEditingController? controller;
//   final int? maxlines;
//   const TextFiledWidget({
//     super.key,
//     this.controller,
//     this.maxlines,
//     required this.hint,
//     this.isEnabled = true,
//     this.ontap,
//     this.icon,
//     this.suffixIcon = false,
//     this.isLocationField = false,
//   });

//   @override
//   Widget build(BuildContext context) {
//     return SizedBox(
//       height: SizeConfig.heightMultiplier * 5.5,
//       child: TextField(
//         maxLines: 4,
//         // readOnly: isEnabled,
//         enabled: isEnabled,
//         controller: controller,
//         onTap: ontap,
//         decoration: InputDecoration(
//           hintText: hint,
//           labelText: isEnabled ? hint : '',
//           suffixIcon: Padding(
//             padding: const EdgeInsets.all(14),
//             child: Container(
//               decoration: BoxDecoration(
//                 border: Border.all(
//                   color: isLocationField ? Colors.black : Colors.transparent,
//                 ),
//                 borderRadius: BorderRadius.circular(30),
//               ),
//               child: Icon(
//                 icon,
//                 size: 18,
//                 color: Colors.grey,
//               ),
//             ),
//           ),
//           filled: true,
//           fillColor: Colors.white,
//           hintStyle: const TextStyle(
//             fontSize: 12,
//           ),
//           contentPadding:
//               const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
//           enabledBorder: OutlineInputBorder(
//             borderSide: BorderSide(color: Colors.grey.shade500, width: 0.5),
//             borderRadius: BorderRadius.circular(4),
//           ),
//           focusedBorder: OutlineInputBorder(
//             borderSide: const BorderSide(color: Colors.black, width: 1),
//             borderRadius: BorderRadius.circular(4),
//           ),
//           errorBorder: OutlineInputBorder(
//             borderSide: const BorderSide(color: Colors.red, width: 1),
//             borderRadius: BorderRadius.circular(4),
//           ),
//           border: OutlineInputBorder(
//             borderSide: BorderSide(color: Colors.grey.shade200),
//             borderRadius: BorderRadius.circular(4),
//           ),
//         ),
//       ),
//     );
//   }
// }

import 'package:blockatie/utils/size_config.dart';
import 'package:flutter/material.dart';

class TextFiledWidget extends StatelessWidget {
  final String hint;
  final IconData? icon;
  final bool suffixIcon;
  final bool isLocationField;
  final VoidCallback? ontap;
  final bool isEnabled;
  final bool? readOnly;
  final TextEditingController? controller;
  final int? maxlines;
  final TextInputType? type;
  const TextFiledWidget({
    super.key,
    this.readOnly = false,
    this.type,
    this.controller,
    this.maxlines,
    required this.hint,
    this.isEnabled = true,
    this.ontap,
    this.icon,
    this.suffixIcon = false,
    this.isLocationField = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: SizeConfig.heightMultiplier * 5.5,
      child: TextField(
        keyboardType: type,
        maxLines: maxlines ?? 1,
        readOnly: readOnly ?? false,
        enabled: isEnabled,
        controller: controller,
        onTap: ontap,
        decoration: InputDecoration(
          hintText: hint,
          labelText: isEnabled ? hint : '',
          suffixIcon: Padding(
            padding: const EdgeInsets.all(10),
            child: Container(
              // width: 12,
              // height: 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isLocationField ? Colors.grey : Colors.transparent,
                ),
                // borderRadius: BorderRadius.circular(30),
              ),
              child: Icon(icon, size: 15, color: Colors.grey),
            ),
          ),
          filled: true,
          fillColor: Colors.white,
          hintStyle: const TextStyle(fontSize: 12),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 12,
          ),
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Colors.grey.shade500, width: 0.5),
            borderRadius: BorderRadius.circular(4),
          ),
          focusedBorder: OutlineInputBorder(
            borderSide: const BorderSide(color: Colors.black, width: 1),
            borderRadius: BorderRadius.circular(4),
          ),
          errorBorder: OutlineInputBorder(
            borderSide: const BorderSide(color: Colors.red, width: 1),
            borderRadius: BorderRadius.circular(4),
          ),
          border: OutlineInputBorder(
            borderSide: BorderSide(color: Colors.grey.shade200),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
    );
  }
}
