import 'package:blockatie/constants/colors.dart';
import 'package:blockatie/utils/nav.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../utils/spacing.dart' show Spacing;

class CustomAppBar extends StatelessWidget implements PreferredSizeWidget {
  final VoidCallback? onBack;
  final String? title;
  final String? subtitle;
  final VoidCallback? onHelp;
  final Color? bgColor;
  final Color? titleColor;
  final Color? subtileColor;
  final bool? showBtn;
  final bool? showBackBtn;
  const CustomAppBar({
    super.key,
    this.bgColor,
    this.showBackBtn = true,
    this.titleColor,
    this.onBack,
    this.showBtn = true,
    required this.title,
    required this.subtitle,
    this.subtileColor,
    this.onHelp,
  });

  @override
  Size get preferredSize => const Size.fromHeight(90); // AppBar height

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return SafeArea(
      child: Container(
        // height: 120,
        padding: const EdgeInsets.only(left: 10),
        decoration: BoxDecoration(
          color: bgColor ?? AppColors.primary,
          borderRadius: const BorderRadius.only(
            bottomLeft: Radius.circular(10),
            bottomRight: Radius.circular(10),
          ),
        ),
        child: Column(
          children: [
            Spacing.y(3),
            Row(
              children: [
                if (showBackBtn!)
                  IconButton(
                    icon: Icon(
                      Icons.arrow_back_ios,
                      color: titleColor ?? Colors.white,
                      size: 18,
                    ),
                    onPressed: onBack ?? () => Nav.back(),
                  ),
                Spacing.x(2),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title ?? 'Order Details',
                      style: textTheme.headlineSmall!.copyWith(
                        color: titleColor ?? Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(
                      width: MediaQuery.sizeOf(context).width * 0.6,
                      child: Text(
                        subtitle ?? 'Placed on 12th Feb 2025, 05:30PM',
                        style: textTheme.bodySmall!.copyWith(
                          color: subtileColor ?? Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                if (showBtn!)
                  InkWell(
                    onTap: onHelp,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          tr("help"),
                          style: TextStyle(
                            color: AppColors.primary,
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
