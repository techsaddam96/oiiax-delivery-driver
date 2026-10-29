import 'package:blockatie/constants/colors.dart';
import 'package:blockatie/utils/app_images.dart';
import 'package:blockatie/utils/size_config.dart';
import 'package:blockatie/utils/spacing.dart';
import 'package:blockatie/views/pages/hub/components/gradient_container.dart';
import 'package:flutter/material.dart';

class HubHeader extends StatelessWidget {
  const HubHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 20),
      decoration: const BoxDecoration(color: Colors.white),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Image.asset(AppImages.iconImage, width: 23, height: 23),
              const GradientBorderRankBox(),
              Image.asset(AppImages.scan, width: 18, height: 18),
            ],
          ),
          Spacing.y(3),
          // Search Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: SizedBox(
              height: SizeConfig.heightMultiplier * 4.5,
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Search',
                  suffixIcon: Padding(
                    padding: const EdgeInsets.all(10.0),
                    child: Image.asset(AppImages.search),
                  ),
                  filled: true,
                  fillColor: AppColors.searchBarColor,
                  hintStyle: textTheme.bodySmall!.copyWith(
                    color: Colors.black26,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: 0,
                    horizontal: 15,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
