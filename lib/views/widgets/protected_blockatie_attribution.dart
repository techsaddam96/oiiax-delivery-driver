import 'package:blockatie/constants/oiiax_brand.dart';
import 'package:flutter/material.dart';

/// Required supplier attribution. It is deliberately local application code,
/// rather than a customer, profile, or remote-branding setting.
class ProtectedBlockatieAttribution extends StatelessWidget {
  const ProtectedBlockatieAttribution({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Copyright 2026 Blockatie',
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '© 2026 Blockatie',
              style: TextStyle(
                color: Color(0xFF1E1E1E),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 7),
            Image.asset(
              OIIAXBrand.protectedBlockatieLogo,
              height: 13,
              fit: BoxFit.contain,
              excludeFromSemantics: true,
            ),
          ],
        ),
      ),
    );
  }
}
