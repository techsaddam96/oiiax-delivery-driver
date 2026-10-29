import 'package:blockatie/constants/colors.dart';
import 'package:blockatie/provider/shipment.dart';
import 'package:blockatie/utils/app_images.dart';
import 'package:blockatie/utils/nav.dart';
import 'package:blockatie/utils/size_config.dart';
import 'package:blockatie/utils/spacing.dart';
import 'package:blockatie/views/pages/home/filter/filter.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class OrdersHeader extends StatelessWidget {
  const OrdersHeader({super.key, this.hrpadding, this.totalOrders});
  final double? hrpadding;
  final int? totalOrders;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Consumer<ShipmentProvider>(
      builder: (context, provider, _) {
        return Row(
          children: [
            Text(
              "${tr("orders")}: ${provider.totalCount}",
              style: textTheme.headlineSmall,
            ),
            const Spacer(),
            // SEARCH BAR
            Container(
              height: SizeConfig.heightMultiplier * 3,
              width: SizeConfig.widthMultiplier * 50,
              decoration: BoxDecoration(
                color: AppColors.searchBarColor,
                borderRadius: BorderRadius.circular(6),
              ),
              padding: EdgeInsets.symmetric(
                horizontal: SizeConfig.widthMultiplier * 2,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      onChanged: provider.searchShipments,
                      style: textTheme.bodySmall!.copyWith(
                        fontSize: SizeConfig.textMultiplier * 1.2,
                        fontWeight: FontWeight.w400,
                      ),
                      textAlignVertical: TextAlignVertical.center,
                      decoration: InputDecoration(
                        hintText: tr("search_here"),
                        isCollapsed: true,
                        contentPadding: EdgeInsets.zero,
                        fillColor: AppColors.searchBarColor,
                        hintStyle: textTheme.bodySmall!.copyWith(
                          color: Colors.black38,
                          fontSize: SizeConfig.textMultiplier * 1.2,
                          fontWeight: FontWeight.w400,
                        ),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  Image.asset(AppImages.search, height: 12),
                ],
              ),
            ),
            Spacing.x(2),
            // FILTER
            InkWell(
              onTap: () => Nav.to(const FilterPage()),
              child: Container(
                height: SizeConfig.heightMultiplier * 2.8,
                width: SizeConfig.widthMultiplier * 6,
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(3.5),
                  child: Image.asset("assets/icons/filter.png", height: 12),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// class OrdersHeader extends StatelessWidget {
//   const OrdersHeader({super.key, this.hrpadding, this.totalOrders});
//   final double? hrpadding;
//   final int? totalOrders;
//   @override
//   Widget build(BuildContext context) {
//     final textTheme = Theme.of(context).textTheme;
//     return Row(
//       children: [
//         Text("${tr("orders")}: 43", style: textTheme.headlineSmall),
//         const Spacer(),
//         //SEARCH
//         Container(
//           height: SizeConfig.heightMultiplier * 3,
//           width: SizeConfig.widthMultiplier * 50,
//           decoration: BoxDecoration(
//             color: AppColors.searchBarColor,
//             borderRadius: BorderRadius.circular(6),
//           ),
//           padding: EdgeInsets.symmetric(
//             horizontal: SizeConfig.widthMultiplier * 2,
//           ),
//           child: Row(
//             children: [
//               Expanded(
//                 child: TextField(
//                   style: textTheme.bodySmall!.copyWith(
//                     fontSize: SizeConfig.textMultiplier * 1.2,
//                     fontWeight: FontWeight.w400,
//                   ),
//                   textAlignVertical: TextAlignVertical.center,
//                   decoration: InputDecoration(
//                     hintText: tr("search_here"),
//                     isCollapsed: true,
//                     contentPadding: EdgeInsets.zero,
//                     fillColor: AppColors.searchBarColor,
//                     hintStyle: textTheme.bodySmall!.copyWith(
//                       color: Colors.black38,
//                       fontSize: SizeConfig.textMultiplier * 1.2,
//                       fontWeight: FontWeight.w400,
//                     ),
//                     border: InputBorder.none,
//                   ),
//                 ),
//               ),
//               Image.asset(AppImages.search, height: 12),
//             ],
//           ),
//         ),
//         Spacing.x(2),
//         //FILTER
//         InkWell(
//           onTap: () {
//             print('filter button taped ===>>');
//             Nav.to(const FilterPage());
//           },
//           child: Container(
//             height: SizeConfig.heightMultiplier * 2.8,
//             width: SizeConfig.widthMultiplier * 6,
//             decoration: BoxDecoration(
//               color: Colors.black87,
//               borderRadius: BorderRadius.circular(6),
//             ),
//             child: Padding(
//               padding: const EdgeInsets.all(3.5),
//               child: Image.asset("assets/icons/filter.png", height: 12),
//             ),
//           ),
//         ),
//         // Spacing.x(3),
//       ],
//     );
//   }
// }
