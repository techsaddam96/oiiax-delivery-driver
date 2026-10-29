import 'package:blockatie/constants/colors.dart';
import 'package:blockatie/utils/app_images.dart';
import 'package:blockatie/utils/nav.dart';
import 'package:blockatie/utils/size_config.dart';
import 'package:blockatie/utils/spacing.dart';
import 'package:blockatie/views/dialoges/location_permission.dart';
import 'package:blockatie/views/pages/auth/login/login.dart';
import 'package:blockatie/views/widgets/custom_elevated_btn.dart';
// Add this import
import 'package:flutter/material.dart';

class GetStartedPage extends StatelessWidget {
  const GetStartedPage({super.key});

  Future<void> _handleLocationPermission(BuildContext context) async {
    final locationService = LocationService();

    // Handle initial location permission
    bool isLocationEnabled = await locationService.handleLocationPermission(
      context,
    );

    if (isLocationEnabled) {
      // Navigate to login page
      Nav.off(const LoginPage());
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          color: AppColors.primary,
          // gradient: LinearGradient(
          //   begin: Alignment.topCenter,
          //   end: Alignment.bottomCenter,
          //   colors: [AppColors.gradient1, AppColors.gradient2],
          // ),
        ),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Spacing.y(15),
                  Image.asset(
                    AppImages.logo,
                    width: SizeConfig.widthMultiplier * 70,
                  ),
                  Spacing.y(13),
                  Text(
                    "Always In Control,",
                    style: textTheme.titleLarge!.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 25,
                    ),
                  ),
                  Text(
                    "Always On Time",
                    style: textTheme.titleLarge!.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 25,
                    ),
                  ),
                  Spacing.y(1.5),
                  Text(
                    textAlign: TextAlign.center,
                    'Easily track your shipments, view delivery updates, and manage your routes — all from one place.',
                    style: textTheme.bodySmall!.copyWith(color: Colors.white),
                  ),
                  Spacing.y(4),
                  CustomElevatedBtn(
                    label: 'Get Started',
                    bgColor: Colors.white,
                    textColor: AppColors.gradient2,
                    onTap: () => _handleLocationPermission(context),
                    width: SizeConfig.widthMultiplier * 64,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
