// import 'package:blockatie/constants/colors.dart';
// import 'package:flutter/material.dart';

// class DottedLine extends StatelessWidget {
//   final bool isCompleted;

//   const DottedLine({
//     super.key,
//     this.isCompleted = false,
//   });

//   @override
//   Widget build(BuildContext context) {
//     return Expanded(
//       child: Container(
//         height: 2,
//         margin: const EdgeInsets.only(top: 0),
//         child: CustomPaint(
//           painter: isCompleted ? StraightLinePainter() : DottedLinePainter(),
//         ),
//       ),
//     );
//   }
// }

// class DottedLinePainter extends CustomPainter {
//   @override
//   void paint(Canvas canvas, Size size) {
//     Paint paint = Paint()
//       ..color = Colors.grey[400]!
//       ..strokeWidth = 1
//       ..style = PaintingStyle.stroke;

//     double dashWidth = 4;
//     double dashSpace = 3;
//     double startX = 0;

//     while (startX < size.width) {
//       canvas.drawLine(
//         Offset(startX, size.height / 2),
//         Offset(startX + dashWidth, size.height / 2),
//         paint,
//       );
//       startX += dashWidth + dashSpace;
//     }
//   }

//   @override
//   bool shouldRepaint(CustomPainter oldDelegate) => false;
// }

// class StraightLinePainter extends CustomPainter {
//   @override
//   void paint(Canvas canvas, Size size) {
//     Paint paint = Paint()
//       ..color = AppColors.primary
//       ..strokeWidth = 2
//       ..style = PaintingStyle.stroke;

//     canvas.drawLine(
//       Offset(0, size.height / 2),
//       Offset(size.width, size.height / 2),
//       paint,
//     );
//   }

//   @override
//   bool shouldRepaint(CustomPainter oldDelegate) => false;
// }

// // import 'package:flutter/material.dart';
// // import 'package:blockatie/constants/colors.dart';

// // class DottedLine extends StatelessWidget {
// //   final bool isCompleted;

// //   const DottedLine({
// //     super.key,
// //     this.isCompleted = false,
// //   });

// //   @override
// //   Widget build(BuildContext context) {
// //     return Expanded(
// //       child: Container(
// //         height: 2,
// //         margin: const EdgeInsets.only(bottom: 30, left: 2, right: 2),
// //         child: CustomPaint(
// //           painter: isCompleted
// //               ? StraightLinePainter()
// //               : DottedLinePainter(),
// //         ),
// //       ),
// //     );
// //   }
// // }

// // class DottedLinePainter extends CustomPainter {
// //   @override
// //   void paint(Canvas canvas, Size size) {
// //     Paint paint = Paint()
// //       ..color = Colors.grey[400]!
// //       ..strokeWidth = 1
// //       ..style = PaintingStyle.stroke;

// //     double dashWidth = 4;
// //     double dashSpace = 3;
// //     double startX = 0;

// //     while (startX < size.width) {
// //       canvas.drawLine(
// //         Offset(startX, size.height / 2),
// //         Offset(startX + dashWidth, size.height / 2),
// //         paint,
// //       );
// //       startX += dashWidth + dashSpace;
// //     }
// //   }

// //   @override
// //   bool shouldRepaint(CustomPainter oldDelegate) => false;
// // }

// // class StraightLinePainter extends CustomPainter {
// //   @override
// //   void paint(Canvas canvas, Size size) {
// //     Paint paint = Paint()
// //       ..color = AppColors.primary
// //       ..strokeWidth = 2
// //       ..style = PaintingStyle.stroke;

// //     canvas.drawLine(
// //       Offset(0, size.height / 2),
// //       Offset(size.width, size.height / 2),
// //       paint,
// //     );
// //   }

// //   @override
// //   bool shouldRepaint(CustomPainter oldDelegate) => false;
// // }

import 'package:blockatie/constants/colors.dart';
import 'package:flutter/material.dart';

class DottedLine extends StatelessWidget {
  final bool isCompleted;

  const DottedLine({super.key, this.isCompleted = false});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(double.infinity, 2), // Let the line span the full width
      painter: isCompleted ? StraightLinePainter() : DottedLinePainter(),
    );
  }
}

class DottedLinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    Paint paint =
        Paint()
          ..color = Colors.grey[400]!
          ..strokeWidth = 1
          ..style = PaintingStyle.stroke;

    double dashWidth = 4;
    double dashSpace = 3;
    double startX = 0;

    // Draw dotted line at the vertical center
    while (startX < size.width) {
      canvas.drawLine(
        Offset(startX, size.height / 2),
        Offset(startX + dashWidth, size.height / 2),
        paint,
      );
      startX += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}

class StraightLinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    Paint paint =
        Paint()
          ..color = AppColors.primary
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke;

    // Draw straight line at the vertical center
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      paint,
    );
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}
