import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dart:async';

import 'package:blockatie/constants/notification_system.dart';
import 'package:blockatie/utils/localization.dart';

/// The app's single source of truth for language.
///
/// Three things have to agree, and this is what makes them agree:
///   * `MaterialApp.locale` (text + Directionality) reads [getCurrentLocale];
///   * `AppLocalizations` (`isArabic`, `isRTL`, and therefore the theme font)
///     is pushed from here via `applyLocale`;
///   * EasyLocalization's own locale is set through `context.setLocale`.
///
/// Only this class writes the stored preference, and it writes one canonical
/// form. Reads normalize every legacy form, so a preference saved as 'Arabic'
/// by an older build and one saved as 'ar' both resolve to Arabic.
class LocaleProvider with ChangeNotifier {
  /// Display keys, also the values the hub's language dropdown selects from.
  static const String english = 'English';
  static const String arabic = 'Arabic';

  final List<String> languages = [english, arabic];
  final Map<String, String> languageDisplayNames = {
    english: 'English',
    arabic: 'العربية',
  };

  String selectedLanguage = english;

  /// Seeded synchronously from [AppLocalizations], which main() initializes
  /// from the stored preference before runApp. Without this the first frame
  /// would always be English and an Arabic driver would watch the app flip
  /// language a moment after launch.
  LocaleProvider({bool loadSaved = true}) {
    selectedLanguage = AppLocalizations.isArabic ? arabic : english;
    if (loadSaved) {
      _loadSavedLanguage();
    }
  }

  /// Reads the saved preference, tolerating every form an earlier build may
  /// have written, and brings [AppLocalizations] in step before notifying.
  Future<void> _loadSavedLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(AppLocalizations.languageCodeKey);
    selectedLanguage = _displayNameFor(stored);
    AppLocalizations.applyLocale(getCurrentLocale());
    notifyListeners();
  }

  /// Writes the canonical code ('ar' / 'en'). Legacy values are migrated the
  /// first time a language is chosen.
  Future<void> _saveLanguage(String language) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      AppLocalizations.languageCodeKey,
      AppLocalizations.normalizeLanguageCode(language),
    );
  }

  /// Switches language everywhere in one pass: stored preference,
  /// [AppLocalizations] (font + RTL helpers), EasyLocalization, and the
  /// listeners that rebuild `MaterialApp`. No restart is needed.
  Future<void> setLanguage(String lang, BuildContext context) async {
    final language = _displayNameFor(lang);
    final locale =
        language == arabic ? AppLocalizations.arabic : AppLocalizations.english;

    // EasyLocalization first, while nothing else has moved. Its delegate binds
    // tr() to whichever translations are loaded at the moment MaterialApp's
    // locale changes and never reloads them, so notifying before the new file
    // had loaded left every tr() string in the old language until a restart.
    // Still guarded: it is a consumer of this state, not an owner of it, so a
    // context that has moved on must not turn the switch into a thrown error.
    if (context.mounted) {
      try {
        await context.setLocale(locale);
      } catch (e) {
        debugPrint('EasyLocalization locale sync skipped: ${e.runtimeType}');
      }
    }

    // Then in memory and every listener in one pass, so the rebuild already
    // sees the new font and direction.
    selectedLanguage = language;
    AppLocalizations.applyLocale(locale);
    notifyListeners();

    await _saveLanguage(selectedLanguage);

    // The driver's push language lives on the server too, so a switch here
    // reaches the next notification rather than waiting for a reinstall.
    unawaited(NotificationSystem.updateDriverNotificationLanguage());
  }

  /// Any of 'ar', 'Arabic', 'en', 'English' — or null on a fresh install,
  /// which is Arabic, matching [AppLocalizations.initialize].
  String _displayNameFor(String? value) {
    return AppLocalizations.normalizeLanguageCode(value) == 'ar'
        ? arabic
        : english;
  }

  // Get display name for a language
  String getLanguageDisplayName(String language) {
    return languageDisplayNames[language] ?? language;
  }

  // Get current locale
  Locale getCurrentLocale() {
    return selectedLanguage == arabic
        ? AppLocalizations.arabic
        : AppLocalizations.english;
  }

  // Check if current language is Arabic
  bool get isArabic => selectedLanguage == arabic;

  // Check if current language is English
  bool get isEnglish => selectedLanguage == english;
}
