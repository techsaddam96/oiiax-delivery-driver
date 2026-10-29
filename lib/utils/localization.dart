import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppLocalizations {
  static const Locale english = Locale('en');
  static const Locale arabic = Locale('ar');

  static const List<Locale> supportedLocales = [english, arabic];

  static const String _languageCodeKey = 'selected_language';

  static Locale _currentLocale = english;

  static Locale get currentLocale => _currentLocale;

  static bool get isRTL => _isArabicCode(_currentLocale.languageCode);

  static bool get isArabic => _isArabicCode(_currentLocale.languageCode);

  static bool get isEnglish => _isEnglishCode(_currentLocale.languageCode);

  static bool _isArabicCode(String code) {
    final normalized = code.trim().toLowerCase();
    return normalized == 'ar' || normalized == 'arabic';
  }

  static bool _isEnglishCode(String code) {
    final normalized = code.trim().toLowerCase();
    return normalized == 'en' || normalized == 'english';
  }

  /// Arabic unless English was explicitly chosen (fresh install included).
  static String _normalizeLanguageCode(String? code) {
    if (_isEnglishCode(code ?? '')) {
      return 'en';
    }
    return 'ar';
  }

  /// The stored preference, normalized. Shared with [LocaleProvider], which
  /// owns writing it — see [applyLocale].
  static const String languageCodeKey = _languageCodeKey;

  /// Normalizes any stored form: 'ar', 'Arabic', 'en', 'English'.
  static String normalizeLanguageCode(String? code) =>
      _normalizeLanguageCode(code);

  /// Where easy_localization kept its own copy of the language, in builds
  /// before it was made a consumer of [LocaleProvider] (`saveLocale: false`).
  ///
  /// While this key exists easy_localization ignores the `startLocale` main()
  /// hands it and, with saving off, falls back to the phone's language — so on
  /// an upgraded phone every tr() string followed the device, not the driver.
  static const String legacyEasyLocalizationKey = 'locale';

  // Initialize localization
  //
  // main() must call this before EasyLocalization.ensureInitialized(), which
  // reads the legacy key once and keeps it for the life of the process.
  static Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey(legacyEasyLocalizationKey)) {
      await prefs.remove(legacyEasyLocalizationKey);
    }
    // Defaults to Arabic, the same default LocaleProvider uses (both go
    // through _normalizeLanguageCode). They must never disagree, or a fresh
    // install renders one language in the other's font.
    final languageCode = prefs.getString(_languageCodeKey);

    _currentLocale = Locale(_normalizeLanguageCode(languageCode));

    // Set system UI overlay style based on language
    _updateSystemUI();
  }

  /// Applies a locale in memory without persisting it.
  ///
  /// [LocaleProvider] is the app-level source of truth and owns the stored
  /// preference; it calls this so `isArabic`, `isRTL` and the font follow the
  /// switch in the same frame. Persisting here as well is what previously let
  /// two formats be written to one key.
  static void applyLocale(Locale locale) {
    final normalizedCode = _normalizeLanguageCode(locale.languageCode);
    if (_currentLocale.languageCode == normalizedCode) {
      return;
    }
    _currentLocale = Locale(normalizedCode);
    _updateSystemUI();
    LanguageChangeNotifier().notifyLanguageChanged();
  }

  // Update system UI for RTL/LTR
  static void _updateSystemUI() {
    if (isRTL) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    }
  }

  // Get text direction
  static TextDirection get textDirection =>
      isRTL ? TextDirection.rtl : TextDirection.ltr;

  // Get alignment based on language
  static Alignment get textAlignment =>
      isRTL ? Alignment.centerRight : Alignment.centerLeft;

  // Get start alignment for RTL support
  static Alignment get startAlignment =>
      isRTL ? Alignment.centerRight : Alignment.centerLeft;

  // Get end alignment for RTL support
  static Alignment get endAlignment =>
      isRTL ? Alignment.centerLeft : Alignment.centerRight;

  // Get cross axis alignment for RTL support
  static CrossAxisAlignment get crossAxisAlignment =>
      isRTL ? CrossAxisAlignment.end : CrossAxisAlignment.start;

  // Get main axis alignment for RTL support
  static MainAxisAlignment get mainAxisAlignment =>
      isRTL ? MainAxisAlignment.end : MainAxisAlignment.start;

  // Get language change notifier for listening to language changes
  static LanguageChangeNotifier get languageNotifier =>
      LanguageChangeNotifier();
}

class LanguageChangeNotifier extends ChangeNotifier {
  static final LanguageChangeNotifier _instance =
      LanguageChangeNotifier._internal();

  factory LanguageChangeNotifier() => _instance;

  LanguageChangeNotifier._internal();

  void notifyLanguageChanged() {
    notifyListeners();
  }
}
