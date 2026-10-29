import 'package:blockatie/constants/colors.dart';
import 'package:blockatie/constants/oiiax_brand.dart';
import 'package:blockatie/utils/size_config.dart';
import 'package:flutter/material.dart';

import '../constants/fonts.dart';

// class AppTheme {
//   static ThemeData primaryTheme = ThemeData(
//     fontFamily: 'Poppins',
//     scaffoldBackgroundColor: AppColors.bg,
//     textTheme: TextTheme(
//       displaySmall: TextStyle(
//         color: Colors.black,
//         fontWeight: FontWeight.w400,
//         fontSize: SizeConfig.textMultiplier * 1.2,
//       ),
//       bodySmall: TextStyle(
//         color: Colors.black,
//         fontWeight: FontWeight.w400,
//         fontSize: SizeConfig.textMultiplier * 1.4,
//       ),
//       bodyMedium: TextStyle(
//         color: Colors.black,
//         fontWeight: FontWeight.w400,
//         fontSize: SizeConfig.textMultiplier * 1.6,
//       ),
//       bodyLarge: TextStyle(
//         color: Colors.black,
//         fontWeight: FontWeight.w400,
//         fontSize: SizeConfig.textMultiplier * 1.8,
//       ),
//       displayLarge: TextStyle(
//         color: Colors.black,
//         fontWeight: FontWeight.w400,
//         fontSize: SizeConfig.textMultiplier * 2,
//       ),
//       headlineSmall: TextStyle(
//         color: Colors.black,
//         fontWeight: FontWeight.w600,
//         fontSize: SizeConfig.textMultiplier * 2.2,
//       ),
//       headlineMedium: TextStyle(
//         color: Colors.black,
//         fontWeight: FontWeight.w600,
//         fontSize: SizeConfig.textMultiplier * 2.5,
//       ),
//       headlineLarge: TextStyle(
//         color: Colors.black,
//         fontWeight: FontWeight.w600,
//         fontSize: SizeConfig.textMultiplier * 3,
//       ),
//     ),
//     colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary),
//   );

//   static ThemeData darkTheme = ThemeData(
//     textTheme: TextTheme(
//       displaySmall: TextStyle(
//         color: Colors.white,
//         fontWeight: FontWeight.w400,
//         fontSize: SizeConfig.textMultiplier * 1.2,
//       ),
//       bodySmall: TextStyle(
//         color: Colors.white,
//         fontWeight: FontWeight.w400,
//         fontSize: SizeConfig.textMultiplier * 1.4,
//       ),
//       bodyMedium: TextStyle(
//         color: Colors.white,
//         fontWeight: FontWeight.w400,
//         fontSize: SizeConfig.textMultiplier * 1.6,
//       ),
//       bodyLarge: TextStyle(
//         color: Colors.white,
//         fontWeight: FontWeight.w400,
//         fontSize: SizeConfig.textMultiplier * 1.8,
//       ),
//       displayLarge: TextStyle(
//         color: Colors.white,
//         fontWeight: FontWeight.w400,
//         fontSize: SizeConfig.textMultiplier * 2,
//       ),
//       headlineSmall: TextStyle(
//         color: Colors.white,
//         fontWeight: FontWeight.w600,
//         fontSize: SizeConfig.textMultiplier * 2.2,
//       ),
//       headlineMedium: TextStyle(
//         color: Colors.white,
//         fontWeight: FontWeight.w600,
//         fontSize: SizeConfig.textMultiplier * 2.5,
//       ),
//       headlineLarge: TextStyle(
//         color: Colors.white,
//         fontWeight: FontWeight.w600,
//         fontSize: SizeConfig.textMultiplier * 3.2,
//       ),
//     ),
//     fontFamily: 'Poppins',

//     // fontFamily: 'Poppins',
//     scaffoldBackgroundColor: Colors.black,
//     // colorScheme: ColorScheme.dark(primary: AppColors.secondary),
//   );
// }

class AppTheme {
  static ThemeData getPrimaryTheme() {
    return ThemeData(
      fontFamily: AppFonts.currentFontFamily,
      scaffoldBackgroundColor: AppColors.bgColor,
      textTheme: TextTheme(
        displaySmall: TextStyle(
          fontFamily: AppFonts.currentFontFamily,
          color: Colors.black,
          fontWeight: FontWeight.w400,
          fontSize: SizeConfig.textMultiplier * 1.2,
        ),
        bodySmall: TextStyle(
          fontFamily: AppFonts.currentFontFamily,
          color: Colors.black,
          fontWeight: FontWeight.w400,
          fontSize: SizeConfig.textMultiplier * 1.4,
        ),
        bodyMedium: TextStyle(
          fontFamily: AppFonts.currentFontFamily,
          color: Colors.black,
          fontWeight: FontWeight.w400,
          fontSize: SizeConfig.textMultiplier * 1.6,
        ),
        bodyLarge: TextStyle(
          fontFamily: AppFonts.currentFontFamily,
          color: Colors.black,
          fontWeight: FontWeight.w400,
          fontSize: SizeConfig.textMultiplier * 1.8,
        ),
        displayLarge: TextStyle(
          fontFamily: AppFonts.currentFontFamily,
          color: Colors.black,
          fontWeight: FontWeight.w400,
          fontSize: SizeConfig.textMultiplier * 2,
        ),
        headlineSmall: TextStyle(
          fontFamily: AppFonts.currentFontFamily,
          color: Colors.black,
          fontWeight: FontWeight.w600,
          fontSize: SizeConfig.textMultiplier * 2.2,
        ),
        headlineMedium: TextStyle(
          fontFamily: AppFonts.currentFontFamily,
          color: Colors.black,
          fontWeight: FontWeight.w600,
          fontSize: SizeConfig.textMultiplier * 2.5,
        ),
        headlineLarge: TextStyle(
          fontFamily: AppFonts.currentFontFamily,
          color: Colors.black,
          fontWeight: FontWeight.w600,
          fontSize: SizeConfig.textMultiplier * 3,
        ),
      ),
      colorScheme: ColorScheme.fromSeed(
        seedColor: OIIAXBrand.primary,
        brightness: Brightness.light,
      ).copyWith(
        primary: OIIAXBrand.primary,
        onPrimary: OIIAXBrand.charcoal,
        surface: OIIAXBrand.white,
        onSurface: OIIAXBrand.charcoal,
      ),
    );
  }
}
