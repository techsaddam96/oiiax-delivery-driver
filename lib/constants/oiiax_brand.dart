import 'package:flutter/material.dart';

/// Local, immutable customer-facing OIIAX identity.
///
/// Product branding never comes from API or account settings. The supplier
/// attribution asset is deliberately separate from these customer tokens.
abstract final class OIIAXBrand {
  static const Color primary = Color(0xFFFF751F);
  static const Color charcoal = Color(0xFF1E1E1E);
  static const Color lightGray = Color(0xFFEAEAEA);
  static const Color white = Color(0xFFFFFFFF);

  static const String logoLight =
      'assets/brand/oiiax/logos/OIIAX_Logo_Light_Transparent.png';
  static const String logoDark =
      'assets/brand/oiiax/logos/OIIAX_Logo_Dark_Transparent.png';
  static const String iconLight =
      'assets/brand/oiiax/logos/OIIAX_Icon_Light_Transparent.png';
  static const String iconDark =
      'assets/brand/oiiax/logos/OIIAX_Icon_Dark_Transparent.png';
  static const String driverSplash = 'assets/images/oiiax_driver_splash.png';

  /// Approved supplier credit. It intentionally has no remote override.
  static const String protectedBlockatieLogo =
      'assets/brand/blockatie/blockatie-dark.png';
}
