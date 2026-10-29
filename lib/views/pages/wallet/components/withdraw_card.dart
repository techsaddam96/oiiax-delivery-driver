import 'dart:ui' as ui;

import 'package:blockatie/constants/colors.dart';
import 'package:blockatie/provider/home.dart';
import 'package:blockatie/provider/withdrawal.dart';
import 'package:blockatie/utils/nav.dart';
import 'package:blockatie/utils/size_config.dart';
import 'package:blockatie/utils/spacing.dart';
import 'package:blockatie/views/pages/wallet/withdrawl/withdrawal_options.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class WithdrawCard extends StatelessWidget {
  const WithdrawCard({
    super.key,
    this.balance,
    this.driverName,
    this.phoneNumber,
  });

  final int? balance;
  final String? driverName;
  final String? phoneNumber;

  @override
  Widget build(BuildContext context) {
    return Consumer<WithdrawalProvider>(
      builder: (context, provider, _) {
        return SizedBox(
          child: Stack(
            children: [
              // 🎨 Custom painted background
              CustomPaint(
                size: Size(
                  SizeConfig.widthMultiplier * 100,
                  SizeConfig.heightMultiplier * 20,
                ),
                painter: RPSCustomPainter(),
              ),

              // 💼 Wallet icon and balance
              Positioned(
                top: 20,
                left: 20,
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Image.asset(
                        'assets/images/walletIcon.png',
                        width: 20,
                        height: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Consumer<HomeProvider>(
                          builder: (context, homeprovider, child) {
                            final dBalance =
                                homeprovider.driverStats?.totalDriverDue;
                            return Text(
                              provider.isBalanceHidden
                                  ? '****'
                                  : '$dBalance JOD',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            );
                          },
                        ),
                        Text(
                          tr('total_balance_shipments'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // 👁 Hide/Show Balance
              Positioned(
                top: SizeConfig.heightMultiplier * 3.5,
                right: SizeConfig.widthMultiplier * 3,
                child: GestureDetector(
                  onTap: () {
                    provider.toggleBalanceVisibility();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          provider.isBalanceHidden
                              ? Icons.visibility
                              : Icons.visibility_off_outlined,
                          size: 10,
                          color: Colors.white,
                        ),
                        Spacing.x(2),
                        Text(
                          provider.isBalanceHidden
                              ? tr('show_balance')
                              : tr('hide_balance'),
                          style: const TextStyle(
                            fontSize: 9,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // 👤 Name & Phone
              Positioned(
                bottom: 8,
                left: 15,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      driverName ?? tr('default_driver_name'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Spacing.x(7),
                    Text(
                      phoneNumber ?? tr('default_driver_phone'),
                      style: const TextStyle(color: Colors.white, fontSize: 10),
                    ),
                  ],
                ),
              ),

              // 💸 Withdraw Button
              Positioned(
                bottom: 8,
                right: 10,
                child: SizedBox(
                  height: 37,
                  child: ElevatedButton(
                    onPressed: () {
                      Nav.to(const WithdrawalOptionsPage());
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.textColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Row(
                      children: [
                        Text(
                          tr('withdraw'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                          ),
                        ),
                        Spacing.x(2),
                        const Icon(
                          Icons.arrow_forward,
                          color: Colors.white,
                          size: 15,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// class WithdrawCard extends StatelessWidget {
//   const WithdrawCard({
//     super.key,
//     this.balance,
//     this.driverName,
//     this.phoneNumber,
//   });
//   final int? balance;
//   final String? driverName;
//   final String? phoneNumber;
//   @override
//   Widget build(BuildContext context) {
//     return Consumer<WithdrawalProvider>(
//       builder: (context, provider, _) {
//         return SizedBox(
//           child: Stack(
//             children: [
//               /// Custom painted background
//               CustomPaint(
//                 size: Size(
//                   SizeConfig.widthMultiplier * 90,
//                   SizeConfig.heightMultiplier * 20,
//                 ),
//                 painter: RPSCustomPainter(),
//               ),

//               /// Wallet icon and balance
//               Positioned(
//                 top: 20,
//                 left: 20,
//                 child: Row(
//                   children: [
//                     Container(
//                       padding: const EdgeInsets.all(15),
//                       decoration: BoxDecoration(
//                         color: Colors.white,
//                         borderRadius: BorderRadius.circular(10),
//                       ),
//                       child: Image.asset(
//                         'assets/images/walletIcon.png',
//                         width: 20,
//                         height: 20,
//                       ),
//                     ),
//                     const SizedBox(width: 10),
//                     Column(
//                       crossAxisAlignment: CrossAxisAlignment.start,
//                       children: [
//                         Consumer<HomeProvider>(
//                           builder: (context, homeprovider, child) {
//                             final dBalance =
//                                 homeprovider.driverStats?.totalDriverDue;
//                             return Text(
//                               provider.isBalanceHidden
//                                   ? '****'
//                                   : '$dBalance JOD',
//                               style: const TextStyle(
//                                 color: Colors.white,
//                                 fontSize: 12,
//                                 fontWeight: FontWeight.bold,
//                               ),
//                             );
//                           },
//                         ),
//                         const Text(
//                           'Total balance of shipments\n accrued',
//                           style: TextStyle(color: Colors.white, fontSize: 9),
//                         ),
//                       ],
//                     ),
//                   ],
//                 ),
//               ),

//               /// Hide Balance button
//               Positioned(
//                 top: SizeConfig.heightMultiplier * 3.5,
//                 right: SizeConfig.widthMultiplier * 3,
//                 child: GestureDetector(
//                   onTap: () {
//                     provider.toggleBalanceVisibility();
//                   },
//                   child: Container(
//                     padding: const EdgeInsets.symmetric(
//                       horizontal: 8,
//                       vertical: 8,
//                     ),
//                     decoration: BoxDecoration(
//                       color: Colors.grey.withValues(alpha: 0.5),
//                       borderRadius: BorderRadius.circular(8),
//                     ),
//                     child: Row(
//                       children: [
//                         Icon(
//                           provider.isBalanceHidden
//                               ? Icons.visibility
//                               : Icons.visibility_off_outlined,
//                           size: 10,
//                           color: Colors.white,
//                         ),
//                         Spacing.x(2),
//                         Text(
//                           provider.isBalanceHidden
//                               ? 'Show Balance'
//                               : 'Hide Balance',
//                           style: const TextStyle(
//                             fontSize: 9,
//                             color: Colors.white,
//                           ),
//                         ),
//                       ],
//                     ),
//                   ),
//                 ),
//               ),

//               /// User name and ID
//               Positioned(
//                 bottom: 8,
//                 left: 15,
//                 child: Row(
//                   mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                   children: [
//                     Text(
//                       driverName ?? 'Zara Ahmed',
//                       style: const TextStyle(
//                         color: Colors.white,
//                         fontSize: 13,
//                         fontWeight: FontWeight.bold,
//                       ),
//                     ),
//                     Spacing.x(7),
//                     Text(
//                       phoneNumber ?? '0779735666',
//                       style: const TextStyle(color: Colors.white, fontSize: 10),
//                     ),
//                   ],
//                 ),
//               ),

//               /// Withdraw button
//               Positioned(
//                 bottom: 8,
//                 right: 10,
//                 child: SizedBox(
//                   // width: 110,
//                   height: 37,
//                   child: ElevatedButton(
//                     onPressed: () {
//                       Nav.to(const WithdrawalOptionsPage());
//                     },
//                     style: ElevatedButton.styleFrom(
//                       backgroundColor: AppColors.textColor,
//                       shape: RoundedRectangleBorder(
//                         borderRadius: BorderRadius.circular(8),
//                       ),
//                     ),
//                     child: Row(
//                       children: [
//                         const Text(
//                           'Withdraw',
//                           style: TextStyle(color: Colors.white, fontSize: 10),
//                         ),
//                         Spacing.x(2),
//                         const Icon(
//                           Icons.arrow_forward,
//                           color: Colors.white,
//                           size: 15,
//                         ),
//                       ],
//                     ),
//                   ),
//                 ),
//               ),
//             ],
//           ),
//         );
//       },
//     );
//   }
// }

class RPSCustomPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    Path path_0 = Path();
    path_0.moveTo(size.width * 0.9549419, size.height * 0.0003319033);
    path_0.cubicTo(
      size.width * 0.9790233,
      size.height * 0.0003319033,
      size.width * 0.9985465,
      size.height * 0.04422556,
      size.width * 0.9985465,
      size.height * 0.09837124,
    );
    path_0.lineTo(size.width * 0.9985465, size.height * 0.5364072);
    path_0.cubicTo(
      size.width * 0.9985465,
      size.height * 0.6013817,
      size.width * 0.9751192,
      size.height * 0.6540523,
      size.width * 0.9462209,
      size.height * 0.6540523,
    );
    path_0.lineTo(size.width * 0.6504215, size.height * 0.6540523);
    path_0.cubicTo(
      size.width * 0.6215233,
      size.height * 0.6540523,
      size.width * 0.5980959,
      size.height * 0.7067255,
      size.width * 0.5980959,
      size.height * 0.7716993,
    );
    path_0.lineTo(size.width * 0.5980959, size.height * 0.8810784);
    path_0.cubicTo(
      size.width * 0.5980959,
      size.height * 0.9460523,
      size.width * 0.5746686,
      size.height * 0.9987255,
      size.width * 0.5457703,
      size.height * 0.9987255,
    );
    path_0.lineTo(size.width * 0.04505814, size.height * 0.9987255);
    path_0.cubicTo(
      size.width * 0.02097634,
      size.height * 0.9987255,
      size.width * 0.001454087,
      size.height * 0.9548301,
      size.width * 0.001453488,
      size.height * 0.9006863,
    );
    path_0.lineTo(size.width * 0.001453488, size.height * 0.09837124);
    path_0.cubicTo(
      size.width * 0.001453503,
      size.height * 0.04422556,
      size.width * 0.02097596,
      size.height * 0.0003319033,
      size.width * 0.04505814,
      size.height * 0.0003319033,
    );
    path_0.lineTo(size.width * 0.9549419, size.height * 0.0003319033);
    path_0.close();

    Paint paint0Fill = Paint()..style = PaintingStyle.fill;
    paint0Fill.shader = ui.Gradient.linear(
      Offset(size.width * 0.5000000, size.height * 0.03319033),
      Offset(size.width * 0.5000000, size.height * 0.9987255),
      [
        AppColors.primary.withValues(alpha: 1),
        const Color(0xff3D52B6).withValues(alpha: 1),
      ],
      [0, 1],
    );
    canvas.drawPath(path_0, paint0Fill);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}
