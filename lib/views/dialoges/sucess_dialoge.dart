import 'dart:ui' as ui;
import 'package:blockatie/constants/colors.dart';
import 'package:blockatie/utils/spacing.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

void showSucessDialoge(BuildContext context, String? title, String? subtitle) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) {
      Future.delayed(const Duration(seconds: 3), () {
        if (Navigator.canPop(context)) {
          Navigator.pop(context);
        }
      });

      return Stack(
        children: [
          // Blurred background
          BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 5.0, sigmaY: 5.0),
            child: Container(color: Colors.black.withValues(alpha: 0.3)),
          ),
          // Dialog content
          Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20.0),
            ),
            child: Container(
              padding: const EdgeInsets.all(50.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(200),
                      color: Colors.green.shade50,
                    ),
                    child: Image.asset(
                      'assets/images/accept.png',
                      width: 50,
                      height: 50,
                    ),
                  ),
                  const SizedBox(height: 16.0),
                  Text(
                    title ?? tr('success'),
                    style: TextStyle(
                      fontSize: 16.0,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue[900],
                    ),
                  ),
                  Spacing.y(1),
                  Text(
                    // Generic and bilingual. The default used to be
                    // "Do you want to make the transaction?" — a question, in
                    // English only, inside a success dialog, which could
                    // surface on any screen that omitted a subtitle.
                    subtitle ?? _genericSuccessBody(context),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10.0,
                      color: AppColors.textColor,
                    ),
                  ),
                  Spacing.y(1),
                ],
              ),
            ),
          ),
        ],
      );
    },
  );
}

/// Neutral body for a success dialog whose caller supplied none.
String _genericSuccessBody(BuildContext context) {
  return Localizations.localeOf(context).languageCode == 'ar'
      ? 'تم تنفيذ العملية بنجاح.'
      : 'The operation completed successfully.';
}
