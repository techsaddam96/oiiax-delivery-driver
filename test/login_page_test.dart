// Focused tests for the Driver Login page and the language state it renders
// from.
//
// The seam these cover is the one that used to be broken: three places held a
// language, only one of them was persisted, and the page read a fourth. Each
// group below pins one side of that down, then the widget group checks what
// the driver actually sees.

import 'package:blockatie/constants/app_urls.dart';
import 'package:blockatie/constants/fonts.dart';
import 'package:blockatie/provider/localization.dart';
import 'package:blockatie/provider/login.dart';
import 'package:blockatie/utils/localization.dart';
import 'package:blockatie/views/pages/auth/login/login.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// -----------------------------------------------------------------------------
// Helpers
// -----------------------------------------------------------------------------

const String _languageKey = 'selected_language';

/// A transport that answers from a canned body instead of the network, and
/// records the request it was handed.
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.body);

  final Map<String, dynamic> body;
  static const int statusCode = 200;
  RequestOptions? seen;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    seen = options;
    return ResponseBody.fromString(
      _encode(body),
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

String _encode(Map<String, dynamic> map) {
  final entries = map.entries
      .map(
        (e) =>
            '"${e.key}":${e.value is String ? '"${_escape(e.value as String)}"' : e.value}',
      )
      .join(',');
  return '{$entries}';
}

String _escape(String value) =>
    value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');

LoginProvider _providerWith(_StubAdapter adapter) {
  return LoginProvider(
    httpClientFactory: () {
      final dio = Dio(BaseOptions(validateStatus: (_) => true));
      dio.httpClientAdapter = adapter;
      return dio;
    },
  );
}

/// Hosts the real LoginPage at an app locale, the way MaterialApp does.
Widget _host({required Locale locale, LoginProvider? provider}) {
  return ChangeNotifierProvider<LoginProvider>.value(
    value: provider ?? LoginProvider(),
    child: MaterialApp(
      locale: locale,
      supportedLocales: const [Locale('en'), Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const LoginPage(),
    ),
  );
}

Future<void> _setSize(WidgetTester tester, double w, double h) async {
  tester.view.physicalSize = Size(w * 3, h * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

TextField _fieldAt(WidgetTester tester, int index) {
  return tester.widgetList<TextField>(find.byType(TextField)).elementAt(index);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    // AppLocalizations is static, so a test that switched to Arabic would
    // otherwise decide the language of the next one.
    AppLocalizations.applyLocale(const Locale('en'));
  });

  // ---------------------------------------------------------------------------
  // Stored preference: every legacy form resolves, nobody gets flipped
  // ---------------------------------------------------------------------------
  group('stored language preference', () {
    test('1. fresh install defaults to Arabic in both holders', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await AppLocalizations.initialize();

      final provider = LocaleProvider();
      await Future<void>.delayed(Duration.zero);

      expect(AppLocalizations.isArabic, isTrue);
      expect(provider.isArabic, isTrue);
      expect(provider.getCurrentLocale().languageCode, 'ar');
    });

    test('2. a legacy "Arabic" preference stays Arabic', () async {
      SharedPreferences.setMockInitialValues({_languageKey: 'Arabic'});
      await AppLocalizations.initialize();

      final provider = LocaleProvider();
      await Future<void>.delayed(Duration.zero);

      expect(AppLocalizations.isArabic, isTrue);
      expect(provider.isArabic, isTrue);
    });

    test('3. a canonical "ar" preference stays Arabic', () async {
      SharedPreferences.setMockInitialValues({_languageKey: 'ar'});
      await AppLocalizations.initialize();

      final provider = LocaleProvider();
      await Future<void>.delayed(Duration.zero);

      expect(AppLocalizations.isArabic, isTrue);
      expect(provider.isArabic, isTrue);
    });

    test('4. a legacy "English" preference stays English', () async {
      SharedPreferences.setMockInitialValues({_languageKey: 'English'});
      await AppLocalizations.initialize();

      final provider = LocaleProvider();
      await Future<void>.delayed(Duration.zero);

      expect(provider.isEnglish, isTrue);
      expect(AppLocalizations.isArabic, isFalse);
    });

    test('5. a canonical "en" preference stays English', () async {
      SharedPreferences.setMockInitialValues({_languageKey: 'en'});
      await AppLocalizations.initialize();

      final provider = LocaleProvider();
      await Future<void>.delayed(Duration.zero);

      expect(provider.isEnglish, isTrue);
    });

    test('6. an unrecognised stored value falls back to Arabic', () async {
      SharedPreferences.setMockInitialValues({_languageKey: 'fr-CA'});
      await AppLocalizations.initialize();

      final provider = LocaleProvider();
      await Future<void>.delayed(Duration.zero);

      expect(provider.isArabic, isTrue);
      expect(AppLocalizations.isArabic, isTrue);
    });

    test('7. choosing Arabic writes the canonical code', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await AppLocalizations.initialize();
      final provider = LocaleProvider(loadSaved: false);

      await provider.setLanguage(LocaleProvider.arabic, _NullContext());

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(_languageKey), 'ar');
    });

    test('8. choosing English writes the canonical code', () async {
      SharedPreferences.setMockInitialValues({_languageKey: 'Arabic'});
      await AppLocalizations.initialize();
      final provider = LocaleProvider(loadSaved: false);

      await provider.setLanguage(LocaleProvider.english, _NullContext());

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(_languageKey), 'en');
    });

    test('9. a legacy value is migrated in place, not duplicated', () async {
      SharedPreferences.setMockInitialValues({_languageKey: 'Arabic'});
      await AppLocalizations.initialize();
      final provider = LocaleProvider(loadSaved: false);

      await provider.setLanguage(LocaleProvider.arabic, _NullContext());

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys().toList(), [_languageKey]);
      expect(prefs.getString(_languageKey), 'ar');
      expect(provider.isArabic, isTrue, reason: 'must not flip to English');
    });
  });

  // ---------------------------------------------------------------------------
  // One authoritative state
  // ---------------------------------------------------------------------------
  group('single source of truth', () {
    test('10. AppLocalizations has switched when listeners rebuild', () async {
      SharedPreferences.setMockInitialValues({_languageKey: 'en'});
      await AppLocalizations.initialize();
      final provider = LocaleProvider(loadSaved: false);
      expect(AppLocalizations.isArabic, isFalse);

      // At the notification itself: the font and direction helpers already
      // report Arabic, so the rebuild it triggers cannot use stale values.
      // (Not at the call: the switch first waits for EasyLocalization to load
      // the new translations — see auth_screens_arabic_text_test.)
      final seen = <Object>[];
      provider.addListener(() {
        seen.addAll([
          AppLocalizations.isArabic,
          AppLocalizations.isRTL,
          AppLocalizations.textDirection,
        ]);
      });

      await provider.setLanguage(LocaleProvider.arabic, _NullContext());

      expect(seen, [true, true, TextDirection.rtl]);
    });

    test('11. switching notifies listeners so MaterialApp rebuilds', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await AppLocalizations.initialize();
      final provider = LocaleProvider(loadSaved: false);
      var notifications = 0;
      provider.addListener(() => notifications++);

      await provider.setLanguage(LocaleProvider.arabic, _NullContext());

      expect(notifications, greaterThan(0));
      expect(provider.getCurrentLocale().languageCode, 'ar');
    });

    test('12. applyLocale does not persist, so there is one writer', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await AppLocalizations.initialize();

      AppLocalizations.applyLocale(const Locale('ar'));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(_languageKey), isNull);
      expect(AppLocalizations.isArabic, isTrue);
    });

    test('13. the provider seeds from AppLocalizations on construction', () async {
      SharedPreferences.setMockInitialValues({_languageKey: 'ar'});
      await AppLocalizations.initialize();

      // No pump, no await: the very first frame must already be Arabic.
      final provider = LocaleProvider(loadSaved: false);
      expect(provider.isArabic, isTrue);
    });

    test('14. normalizeLanguageCode collapses every stored form', () {
      expect(AppLocalizations.normalizeLanguageCode('Arabic'), 'ar');
      expect(AppLocalizations.normalizeLanguageCode('ar'), 'ar');
      expect(AppLocalizations.normalizeLanguageCode(' AR '), 'ar');
      expect(AppLocalizations.normalizeLanguageCode('English'), 'en');
      expect(AppLocalizations.normalizeLanguageCode('en'), 'en');
      expect(AppLocalizations.normalizeLanguageCode(null), 'ar');
      expect(AppLocalizations.normalizeLanguageCode('zz'), 'ar');
    });
  });

  // ---------------------------------------------------------------------------
  // Phone and password rules, shared by the field and the provider
  // ---------------------------------------------------------------------------
  group('validation rules', () {
    test('15. an empty phone is rejected in both languages', () {
      expect(
        LoginProvider.phoneValidationMessage('', isArabic: false),
        'Phone number is required',
      );
      expect(
        LoginProvider.phoneValidationMessage('', isArabic: true),
        isNot(anyOf(isNull, 'Phone number is required')),
      );
    });

    test('16. a nine-digit number is rejected', () {
      expect(
        LoginProvider.phoneValidationMessage('079123456', isArabic: false),
        contains('10-digit'),
      );
    });

    test('17. an eleven-digit number is rejected', () {
      expect(
        LoginProvider.phoneValidationMessage('07912345678', isArabic: false),
        isNotNull,
      );
    });

    test('18. an unsupported prefix is rejected', () {
      expect(
        LoginProvider.phoneValidationMessage('0761234567', isArabic: false),
        isNotNull,
      );
      expect(
        LoginProvider.phoneValidationMessage('0791234567', isArabic: false),
        isNull,
      );
    });

    test('19. all three supported prefixes pass', () {
      for (final prefix in LoginProvider.jordanPhonePrefixes) {
        expect(
          LoginProvider.phoneValidationMessage(
            '${prefix}1234567',
            isArabic: false,
          ),
          isNull,
          reason: 'prefix $prefix must be accepted',
        );
      }
    });

    test('20. formatting characters are stripped before validating', () {
      expect(
        LoginProvider.phoneValidationMessage('0791-234-567', isArabic: false),
        isNull,
      );
    });

    test('21. an empty password is rejected in both languages', () {
      expect(
        LoginProvider.passwordValidationMessage('   ', isArabic: false),
        'Password is required',
      );
      expect(
        LoginProvider.passwordValidationMessage(null, isArabic: true),
        isNotNull,
      );
      expect(
        LoginProvider.passwordValidationMessage('secret', isArabic: false),
        isNull,
      );
    });

    test('22. the Arabic and English wordings really differ', () {
      expect(
        LoginProvider.phoneValidationMessage('1', isArabic: true),
        isNot(LoginProvider.phoneValidationMessage('1', isArabic: false)),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Server responses
  // ---------------------------------------------------------------------------
  group('server error handling', () {
    test('23. DB_PREPARE_ERROR never reaches the driver', () async {
      final adapter = _StubAdapter({
        'success': false,
        'code': 'DB_PREPARE_ERROR',
        'message': 'Prepare failed: SELECT * FROM tbl_drivers WHERE dphone=?',
        'message_en': 'Prepare failed: SELECT * FROM tbl_drivers',
        'message_ar': 'Prepare failed',
      });
      final provider = _providerWith(adapter);
      provider.phoneCont.text = '0791234567';
      provider.passCont.text = 'secret';

      await provider.logIn();

      final shown = provider.errorMessage ?? '';
      expect(shown, 'Service is unavailable. Please try again later.');
      for (final leak in const [
        'SELECT',
        'tbl_drivers',
        'Prepare',
        'FROM',
        'mysqli',
      ]) {
        expect(shown, isNot(contains(leak)));
      }
    });

    test('24. DB_QUERY_ERROR never reaches the driver', () async {
      final adapter = _StubAdapter({
        'success': false,
        'code': 'DB_QUERY_ERROR',
        'message_en': r'Query failed at C:\xampp\htdocs\api_driver_login.php',
      });
      final provider = _providerWith(adapter);
      provider.phoneCont.text = '0791234567';
      provider.passCont.text = 'secret';

      await provider.logIn();

      expect(
        provider.errorMessage,
        'Service is unavailable. Please try again later.',
      );
      expect(provider.errorMessage, isNot(contains('xampp')));
    });

    test('25. an ordinary failure keeps the backend wording', () async {
      final adapter = _StubAdapter({
        'success': false,
        'code': 'INVALID_CREDENTIALS',
        'message_en': 'Invalid phone number or password',
        'message_ar': 'Invalid phone number or password',
      });
      final provider = _providerWith(adapter);
      provider.phoneCont.text = '0791234567';
      provider.passCont.text = 'wrong';

      await provider.logIn();

      expect(provider.errorMessage, 'Invalid phone number or password');
    });

    test('26. the request carries the current language', () async {
      final adapter = _StubAdapter({
        'success': false,
        'code': 'INVALID_CREDENTIALS',
        'message_en': 'Invalid phone number or password',
      });
      final provider = _providerWith(adapter);
      provider.phoneCont.text = '0791234567';
      provider.passCont.text = 'secret';

      await provider.logIn();

      expect(adapter.seen, isNotNull);
      expect(adapter.seen!.uri.queryParameters['lang'], anyOf('en', 'ar'));
      expect(adapter.seen!.uri.path, endsWith('api_driver_login.php'));
      expect(adapter.seen!.headers['Accept-Language'], anyOf('en', 'ar'));
      expect(adapter.seen!.uri.toString(), startsWith(AppUrls.driverlogin));
    });

    test('27. a malformed body is reported without leaking it', () async {
      final adapter = _StubAdapter({'unexpected': 1});
      final provider = _providerWith(adapter);
      provider.phoneCont.text = '0791234567';
      provider.passCont.text = 'secret';

      await provider.logIn();

      expect(provider.errorMessage, isNotNull);
      expect(provider.errorMessage, isNot(contains('unexpected')));
    });

    test('28. loading always clears after a failure', () async {
      final adapter = _StubAdapter({
        'success': false,
        'code': 'INVALID_CREDENTIALS',
        'message_en': 'Invalid phone number or password',
      });
      final provider = _providerWith(adapter);
      provider.phoneCont.text = '0791234567';
      provider.passCont.text = 'secret';

      await provider.logIn();

      expect(provider.isLoading, isFalse);
    });

    test('29. a local validation failure never starts a request', () async {
      final adapter = _StubAdapter({'success': true});
      final provider = _providerWith(adapter);
      provider.phoneCont.text = '0761234567'; // unsupported prefix
      provider.passCont.text = 'secret';

      final result = await provider.logIn();

      expect(result, isFalse);
      expect(adapter.seen, isNull, reason: 'no round trip for a bad number');
      expect(provider.isLoading, isFalse);
      expect(provider.errorMessage, isNotNull);
    });

    test('30. clearError only notifies when there is something to clear', () {
      final provider = LoginProvider();
      var notifications = 0;
      provider.addListener(() => notifications++);

      provider.clearError();
      expect(notifications, 0);
    });
  });

  // ---------------------------------------------------------------------------
  // What the driver sees
  // ---------------------------------------------------------------------------
  group('login page', () {
    testWidgets('31. English locale renders English copy left-to-right', (
      tester,
    ) async {
      await _setSize(tester, 390, 844);
      await tester.pumpWidget(_host(locale: const Locale('en')));
      await tester.pump();

      expect(find.text('Welcome back'), findsOneWidget);
      expect(find.text('Sign in'), findsOneWidget);
      expect(
        Directionality.of(tester.element(find.text('Welcome back'))),
        TextDirection.ltr,
      );
    });

    testWidgets('32. Arabic locale renders Arabic copy right-to-left', (
      tester,
    ) async {
      await _setSize(tester, 390, 844);
      await tester.pumpWidget(_host(locale: const Locale('ar')));
      await tester.pump();

      expect(find.text('مرحبًا بعودتك'), findsOneWidget);
      expect(find.text('تسجيل الدخول'), findsOneWidget);
      expect(
        Directionality.of(tester.element(find.text('مرحبًا بعودتك'))),
        TextDirection.rtl,
      );
    });

    testWidgets('33. the page follows the app locale, not a second source', (
      tester,
    ) async {
      // AppLocalizations deliberately disagrees here; MaterialApp wins,
      // because that is what Directionality is built from.
      SharedPreferences.setMockInitialValues({_languageKey: 'en'});
      await AppLocalizations.initialize();

      await _setSize(tester, 390, 844);
      await tester.pumpWidget(_host(locale: const Locale('ar')));
      await tester.pump();

      expect(find.text('مرحبًا بعودتك'), findsOneWidget);
      expect(find.text('Welcome back'), findsNothing);
    });

    testWidgets('34. phone content stays left-to-right inside Arabic', (
      tester,
    ) async {
      await _setSize(tester, 390, 844);
      await tester.pumpWidget(_host(locale: const Locale('ar')));
      await tester.pump();

      final phone = _fieldAt(tester, 0);
      expect(phone.textDirection, TextDirection.ltr);
      expect(phone.textAlign, TextAlign.left);
    });

    testWidgets('35. password content stays left-to-right inside Arabic', (
      tester,
    ) async {
      await _setSize(tester, 390, 844);
      await tester.pumpWidget(_host(locale: const Locale('ar')));
      await tester.pump();

      final password = _fieldAt(tester, 1);
      expect(password.textDirection, TextDirection.ltr);
      expect(password.obscureText, isTrue);
    });

    testWidgets('36. the Jordan prefix is shown and is not selectable', (
      tester,
    ) async {
      await _setSize(tester, 390, 844);
      await tester.pumpWidget(_host(locale: const Locale('en')));
      await tester.pump();

      expect(find.text('+962'), findsOneWidget);

      await tester.tap(find.text('+962'), warnIfMissed: false);
      await tester.pumpAndSettle();

      // No picker, no dialog: an unsupported country cannot be chosen.
      expect(find.byType(Dialog), findsNothing);
      expect(find.text('+962'), findsOneWidget);
    });

    testWidgets('37. the phone field accepts digits only, capped at ten', (
      tester,
    ) async {
      await _setSize(tester, 390, 844);
      final provider = LoginProvider();
      await tester.pumpWidget(
        _host(locale: const Locale('en'), provider: provider),
      );
      await tester.pump();

      await tester.enterText(
        find.byType(TextField).first,
        '+962 79-123-4567 89',
      );
      await tester.pump();

      expect(RegExp(r'^[0-9]+$').hasMatch(provider.phoneCont.text), isTrue);
      expect(provider.phoneCont.text.length, LoginProvider.jordanPhoneLength);
    });

    testWidgets('38. submitting an empty form shows localized English errors', (
      tester,
    ) async {
      await _setSize(tester, 390, 844);
      await tester.pumpWidget(_host(locale: const Locale('en')));
      await tester.pump();

      await tester.tap(find.text('Sign in'));
      await tester.pump();

      expect(find.text('Phone number is required'), findsOneWidget);
      expect(find.text('Password is required'), findsOneWidget);
    });

    testWidgets('39. submitting an empty form shows localized Arabic errors', (
      tester,
    ) async {
      await _setSize(tester, 390, 844);
      await tester.pumpWidget(_host(locale: const Locale('ar')));
      await tester.pump();

      await tester.tap(find.text('تسجيل الدخول'));
      await tester.pump();

      expect(find.text('رقم الهاتف مطلوب'), findsOneWidget);
      expect(find.text('كلمة المرور مطلوبة'), findsOneWidget);
    });

    testWidgets('40. a short number shows the backend-aligned rule', (
      tester,
    ) async {
      await _setSize(tester, 390, 844);
      await tester.pumpWidget(_host(locale: const Locale('en')));
      await tester.pump();

      await tester.enterText(find.byType(TextField).first, '079123');
      await tester.enterText(find.byType(TextField).at(1), 'secret');
      await tester.tap(find.text('Sign in'));
      await tester.pump();

      expect(
        find.text(
          'Enter a valid 10-digit phone number starting with 077, 078, or 079.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('41. a valid number clears the phone error', (tester) async {
      await _setSize(tester, 390, 844);
      await tester.pumpWidget(_host(locale: const Locale('en')));
      await tester.pump();

      await tester.tap(find.text('Sign in'));
      await tester.pump();
      expect(find.text('Phone number is required'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, '0791234567');
      await tester.enterText(find.byType(TextField).at(1), 'secret');
      await tester.pump();

      expect(find.text('Phone number is required'), findsNothing);
    });

    testWidgets('42. a duplicate tap cannot start a second login', (
      tester,
    ) async {
      await _setSize(tester, 390, 844);
      final provider = _LoadingLoginProvider();
      await tester.pumpWidget(
        _host(locale: const Locale('en'), provider: provider),
      );
      await tester.pump();

      final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      expect(button.onPressed, isNull, reason: 'disabled while loading');
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('43. fields are disabled while a login is in flight', (
      tester,
    ) async {
      await _setSize(tester, 390, 844);
      final provider = _LoadingLoginProvider();
      await tester.pumpWidget(
        _host(locale: const Locale('en'), provider: provider),
      );
      await tester.pump();

      expect(_fieldAt(tester, 0).enabled, isFalse);
      expect(_fieldAt(tester, 1).enabled, isFalse);
    });

    testWidgets('44. the layout fits 360x640 in both languages', (
      tester,
    ) async {
      for (final locale in const [Locale('en'), Locale('ar')]) {
        await _setSize(tester, 360, 640);
        await tester.pumpWidget(_host(locale: locale));
        await tester.pump();
        expect(tester.takeException(), isNull, reason: '360x640 $locale');
      }
    });

    testWidgets('45. the layout fits 390x844 and 430x932 in both languages', (
      tester,
    ) async {
      for (final size in const [Size(390, 844), Size(430, 932)]) {
        for (final locale in const [Locale('en'), Locale('ar')]) {
          await _setSize(tester, size.width, size.height);
          await tester.pumpWidget(_host(locale: locale));
          await tester.pump();
          expect(tester.takeException(), isNull, reason: '$size $locale');
        }
      }
    });

    testWidgets('47. a switch changes text, direction and font in one pass', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({_languageKey: 'en'});
      await AppLocalizations.initialize();
      await _setSize(tester, 390, 844);

      final locale = LocaleProvider(loadSaved: false);
      // The same wiring main.dart uses: the theme is rebuilt from inside the
      // Consumer, so the font follows the notification.
      await tester.pumpWidget(
        ChangeNotifierProvider<LocaleProvider>.value(
          value: locale,
          child: ChangeNotifierProvider<LoginProvider>(
            create: (_) => LoginProvider(),
            child: Consumer<LocaleProvider>(
              builder: (context, value, _) => MaterialApp(
                theme: ThemeData(fontFamily: AppFonts.currentFontFamily),
                locale: value.getCurrentLocale(),
                supportedLocales: const [Locale('en'), Locale('ar')],
                localizationsDelegates: const [
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                home: const LoginPage(),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Welcome back'), findsOneWidget);
      var context = tester.element(find.text('Welcome back'));
      expect(Directionality.of(context), TextDirection.ltr);
      expect(Theme.of(context).textTheme.bodyMedium?.fontFamily, 'Montserrat');

      await locale.setLanguage(LocaleProvider.arabic, _NullContext());
      // MaterialApp animates a theme change, so settle before reading it.
      await tester.pumpAndSettle();

      // No restart: copy, direction and font all moved together.
      expect(find.text('مرحبًا بعودتك'), findsOneWidget);
      context = tester.element(find.text('مرحبًا بعودتك'));
      expect(Directionality.of(context), TextDirection.rtl);
      expect(Theme.of(context).textTheme.bodyMedium?.fontFamily, 'Almarai');
    });

    testWidgets('46. the form still fits with the keyboard raised', (
      tester,
    ) async {
      await _setSize(tester, 360, 640);
      tester.view.viewInsets = FakeViewPadding(bottom: 336 * 3);
      addTearDown(tester.view.resetViewInsets);

      await tester.pumpWidget(_host(locale: const Locale('ar')));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(TextField), findsNWidgets(2));
    });
  });
}

/// Reports a login already in flight, so the disabled states can be checked
/// without a real request.
class _LoadingLoginProvider extends LoginProvider {
  @override
  bool get isLoading => true;
}

/// `setLanguage` only touches the context when it is mounted; these tests are
/// about the persistence and notification path, so an unmounted element is
/// exactly the case to pass in.
class _NullContext extends StatelessElement {
  _NullContext() : super(const _NullWidget());
}

class _NullWidget extends StatelessWidget {
  const _NullWidget();

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
