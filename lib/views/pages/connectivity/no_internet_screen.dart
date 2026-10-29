import 'dart:io';

import 'package:app_settings/app_settings.dart';
import 'package:blockatie/constants/colors.dart';
import 'package:blockatie/constants/num_extensions.dart';
import 'package:blockatie/utils/localization.dart';

import 'package:flutter/material.dart';

class NoInternetScreen extends StatelessWidget {
  const NoInternetScreen({super.key});

  void _openWifiSettings() {
    if (Platform.isAndroid) {
      AppSettings.openAppSettingsPanel(AppSettingsPanelType.wifi);
    } else if (Platform.isIOS) {
      // On iOS you can only open the main Settings app,
      // direct Wi-Fi settings is restricted.
      AppSettings.openAppSettings();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset("assets/images/alert.png", height: 150),
              20.ph,
              Text(
                AppLocalizations.isArabic
                    ? 'لا يوجد اتصال بالإنترنت'
                    // Was "No internet connection !!" — the doubled
                    // exclamation and the space before it also read badly when
                    // the paragraph direction was right-to-left.
                    : 'No internet connection',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                AppLocalizations.isArabic
                    ? 'تحقق من اتصالك وحاول مرة أخرى.'
                    : 'Check your connection and try again.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: Color(0xff64748B)),
              ),
              30.ph,
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _openWifiSettings,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    // "Connect" named an action the button does not perform:
                    // it opens the Wi-Fi settings panel, it does not connect
                    // anything.
                    AppLocalizations.isArabic
                        ? 'فتح إعدادات الشبكة'
                        : 'Open network settings',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
