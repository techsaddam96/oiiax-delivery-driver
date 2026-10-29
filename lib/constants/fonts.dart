import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../utils/localization.dart';

/*
 * App Fonts Configuration
 * 
 * This file manages font families for different languages:
 * - English: Montserrat (clean, modern, readable)
 * - Arabic: Almarai (beautiful Arabic script, optimized for readability)
 * 
 * Fonts automatically switch based on the app's current language.
 * All text styles use the appropriate font family for the current language.
 * 
 * IMPORTANT: Use the reactive font methods (currentFontStyle, currentHeading, etc.)
 * to ensure fonts automatically update when language changes!
 */

class AppFonts {
  static const String montserrat = 'Montserrat';

  // Arabic Font Family - For RTL text
  static const String almarai = 'Almarai';

  // Get appropriate font family based on current language
  static String get currentFontFamily {
    return AppLocalizations.isArabic ? almarai : montserrat;
  }

  // Montserrat Text Styles
  static const TextStyle montserratLight = TextStyle(
    fontFamily: montserrat,
    fontWeight: FontWeight.w300,
  );

  static const TextStyle montserratRegular = TextStyle(
    fontFamily: montserrat,
    fontWeight: FontWeight.w400,
  );

  static const TextStyle montserratMedium = TextStyle(
    fontFamily: montserrat,
    fontWeight: FontWeight.w500,
  );

  static const TextStyle montserratSemiBold = TextStyle(
    fontFamily: montserrat,
    fontWeight: FontWeight.w600,
  );

  static const TextStyle montserratBold = TextStyle(
    fontFamily: montserrat,
    fontWeight: FontWeight.w700,
  );

  static const TextStyle montserratExtraBold = TextStyle(
    fontFamily: montserrat,
    fontWeight: FontWeight.w800,
  );

  // Almarai Text Styles
  static const TextStyle almaraiRegular = TextStyle(
    fontFamily: almarai,
    fontWeight: FontWeight.w400,
  );

  static const TextStyle almaraiMedium = TextStyle(
    fontFamily: almarai,
    fontWeight: FontWeight.w500,
  );

  static const TextStyle almaraiSemiBold = TextStyle(
    fontFamily: almarai,
    fontWeight: FontWeight.w600,
  );

  static const TextStyle almaraiBold = TextStyle(
    fontFamily: almarai,
    fontWeight: FontWeight.w700,
  );

  static const TextStyle almaraiExtraBold = TextStyle(
    fontFamily: almarai,
    fontWeight: FontWeight.w800,
  );

  static const TextStyle almaraiLight = TextStyle(
    fontFamily: almarai,
    fontWeight: FontWeight.w300,
  );

  // Helper methods for current language font with custom properties
  static TextStyle currentFontStyle({
    FontWeight weight = FontWeight.w400,
    double? fontSize,
    Color? color,
    double? height,
    TextDecoration? decoration,
  }) {
    return TextStyle(
      fontFamily: currentFontFamily,
      fontWeight: weight,
      fontSize: fontSize,
      color: color,
      height: height,
      decoration: decoration,
    );
  }

  // Predefined styles for current language
  static TextStyle get currentHeading =>
      currentFontStyle(weight: FontWeight.w700, fontSize: 24);

  static TextStyle get currentSubheading =>
      currentFontStyle(weight: FontWeight.w600, fontSize: 18);

  static TextStyle get currentBody =>
      currentFontStyle(weight: FontWeight.w400, fontSize: 16);

  static TextStyle get currentCaption =>
      currentFontStyle(weight: FontWeight.w400, fontSize: 14);

  static TextStyle get currentButton =>
      currentFontStyle(weight: FontWeight.w600, fontSize: 16);

  // Helper methods for Montserrat with custom properties
  static TextStyle montserratStyle({
    FontWeight weight = FontWeight.w400,
    double? fontSize,
    Color? color,
    double? height,
    TextDecoration? decoration,
  }) {
    return TextStyle(
      fontFamily: montserrat,
      fontWeight: weight,
      fontSize: fontSize,
      color: color,
      height: height,
      decoration: decoration,
    );
  }

  // Predefined Montserrat styles for common use cases
  static TextStyle get montserratHeading =>
      montserratStyle(weight: FontWeight.w700, fontSize: 24);

  static TextStyle get montserratSubheading =>
      montserratStyle(weight: FontWeight.w600, fontSize: 18);

  static TextStyle get montserratBody =>
      montserratStyle(weight: FontWeight.w400, fontSize: 16);

  static TextStyle get montserratCaption =>
      montserratStyle(weight: FontWeight.w400, fontSize: 14);

  static TextStyle get montserratButton =>
      montserratStyle(weight: FontWeight.w600, fontSize: 16);

  // Predefined Almarai styles for common use cases
  static TextStyle almaraiStyle({
    FontWeight weight = FontWeight.w400,
    double? fontSize,
    Color? color,
    double? height,
    TextDecoration? decoration,
  }) {
    return TextStyle(
      fontFamily: almarai,
      fontWeight: weight,
      fontSize: fontSize,
      color: color,
      height: height,
      decoration: decoration,
    );
  }

  static TextStyle get almaraiHeading =>
      almaraiStyle(weight: FontWeight.w700, fontSize: 24);

  static TextStyle get almaraiSubheading =>
      almaraiStyle(weight: FontWeight.w600, fontSize: 18);

  static TextStyle get almaraiBody =>
      almaraiStyle(weight: FontWeight.w400, fontSize: 16);

  static TextStyle get almaraiCaption =>
      almaraiStyle(weight: FontWeight.w400, fontSize: 14);

  static TextStyle get almaraiButton =>
      almaraiStyle(weight: FontWeight.w600, fontSize: 16);

  // Legacy Inter font support (if needed for existing code)
  static const String inter = 'Inter';

  static const TextStyle interRegular = TextStyle(
    fontFamily: inter,
    fontWeight: FontWeight.w400,
  );

  static const TextStyle interMedium = TextStyle(
    fontFamily: inter,
    fontWeight: FontWeight.w500,
  );

  static const TextStyle interSemiBold = TextStyle(
    fontFamily: inter,
    fontWeight: FontWeight.w600,
  );

  static const TextStyle interBold = TextStyle(
    fontFamily: inter,
    fontWeight: FontWeight.w700,
  );
}

// Helper widget to provide reactive font styles that automatically update when language changes
class ReactiveFontBuilder extends StatelessWidget {
  final Widget Function(BuildContext context, TextStyle fontStyle) builder;
  final FontWeight weight;
  final double? fontSize;
  final Color? color;
  final double? height;
  final TextDecoration? decoration;

  const ReactiveFontBuilder({
    super.key,
    required this.builder,
    this.weight = FontWeight.w400,
    this.fontSize,
    this.color,
    this.height,
    this.decoration,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<LanguageChangeNotifier>(
      builder: (context, notifier, child) {
        final fontStyle = TextStyle(
          fontFamily: AppFonts.currentFontFamily,
          fontWeight: weight,
          fontSize: fontSize,
          color: color,
          height: height,
          decoration: decoration,
        );
        return builder(context, fontStyle);
      },
    );
  }
}

// Helper widget for text with reactive fonts
class ReactiveText extends StatelessWidget {
  final String text;
  final FontWeight weight;
  final double? fontSize;
  final Color? color;
  final double? height;
  final TextDecoration? decoration;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;

  const ReactiveText(
    this.text, {
    super.key,
    this.weight = FontWeight.w400,
    this.fontSize,
    this.color,
    this.height,
    this.decoration,
    this.textAlign,
    this.maxLines,
    this.overflow,
  });

  @override
  Widget build(BuildContext context) {
    return ReactiveFontBuilder(
      weight: weight,
      fontSize: fontSize,
      color: color,
      height: height,
      decoration: decoration,
      builder: (context, fontStyle) {
        return Text(
          text,
          style: fontStyle,
          textAlign: textAlign,
          maxLines: maxLines,
          overflow: overflow,
        );
      },
    );
  }
}

/*
 * Usage Examples:
 *
 * 1. Automatic font switching based on language:
 *    Text(
 *      'Hello World',
 *      style: AppFonts.currentFontStyle(fontSize: 16),
 *    )
 *    // Will use Montserrat for English, Almarai for Arabic
 *
 * 2. Language-specific styles:
 *    Text(
 *      'Heading',
 *      style: AppFonts.montserratHeading, // Always Montserrat
 *    )
 *
 *    Text(
 *      'عنوان',
 *      style: AppFonts.almaraiHeading, // Always Almarai
 *    )
 *
 * 3. Dynamic font with custom properties:
 *    Text(
 *      'Custom Text',
 *      style: AppFonts.currentFontStyle(
 *        weight: FontWeight.w600,
 *        fontSize: 18,
 *        color: Colors.blue,
 *      ),
 *    )
 *
 * 4. Predefined styles for current language:
 *    Text('Title', style: AppFonts.currentHeading)
 *    Text('Subtitle', style: AppFonts.currentSubheading)
 *    Text('Body text', style: AppFonts.currentBody)
 *    Text('Caption', style: AppFonts.currentCaption)
 *    Text('Button', style: AppFonts.currentButton)
 *
 * 5. REACTIVE FONTS - Automatically update when language changes:
 *    ReactiveText(
 *      'Hello World',
 *      fontSize: 16,
 *      weight: FontWeight.w600,
 *    )
 *
 *    ReactiveFontBuilder(
 *      fontSize: 18,
 *      weight: FontWeight.w700,
 *      builder: (context, fontStyle) {
 *        return Text('Custom Text', style: fontStyle);
 *      },
 *    )
 *
 * 6. For existing Text widgets, wrap with LanguageAwareWidget:
 *    LanguageAwareWidget(
 *      builder: (context) {
 *        return Text(
 *          'Hello World',
 *          style: AppFonts.currentFontStyle(fontSize: 16),
 *        );
 *      },
 *    )
 */
