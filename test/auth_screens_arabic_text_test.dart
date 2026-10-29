// Splash, Login and Register in the driver's Arabic: nothing on them may read
// English except what is meant to stay — the Blockatie mark (an image) and
// the phone number format hint.
//
// The pages are hosted under the same EasyLocalization wiring main.dart uses.
// The page tests (login_page_test, register_page_test) leave it out, which is
// how this went unseen: tr() read a second locale that could disagree with
// the app's — on a phone upgraded from a build that saved easy_localization's
// own locale, and after an in-app switch — so Login's tabs said "Hero" and
// "Support" to an Arabic driver. Splash had no Arabic wording at all, and a
// license or feature guard's English sentence reached Login unchanged.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:blockatie/provider/bottom_nav.dart';
import 'package:blockatie/provider/localization.dart';
import 'package:blockatie/provider/login.dart';
import 'package:blockatie/provider/register.dart';
import 'package:blockatie/services/auth_secure_store.dart';
import 'package:blockatie/services/auth_services.dart';
import 'package:blockatie/utils/localization.dart';
import 'package:blockatie/utils/nav.dart';
import 'package:blockatie/utils/size_config.dart';
import 'package:blockatie/views/pages/auth/login/login.dart';
import 'package:blockatie/views/pages/auth/signup/register.dart';
import 'package:blockatie/views/pages/splash/splash.dart';
import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// -----------------------------------------------------------------------------
// Helpers
// -----------------------------------------------------------------------------

/// The app's translation files, delivered the way a phone delivers them: not
/// before the next frame, which is what exposes the ordering of an in-app
/// language switch. Read from the project directly, because flutter_test's
/// asset channel answers outside the fake clock these tests run on.
class _DeviceSpeedAssetLoader extends AssetLoader {
  const _DeviceSpeedAssetLoader();

  @override
  Future<Map<String, dynamic>?> load(String path, Locale locale) async {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final file = File('$path/${locale.languageCode}.json');
    return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  }
}

/// No stored credentials, so Splash hands over to Login.
class _SignedOutStore implements AuthSecureStore {
  @override
  Future<String?> read(String key) async => null;

  @override
  Future<void> write(String key, String value) async {}

  @override
  Future<void> delete(String key) async {}
}

/// main()'s language start-up, in main()'s order (pinned by the source check
/// in the start-up group), for a signed-out driver.
///
/// Called from the test body, not setUp: setUp runs outside the fake clock,
/// and AuthService's storage queue would then wait on the real one.
Future<void> _startUp(Map<String, Object> stored) async {
  AuthService.configureForTesting(secureStore: _SignedOutStore());
  SharedPreferences.setMockInitialValues(stored);
  await AppLocalizations.initialize();
  await EasyLocalization.ensureInitialized();
}

/// The language wiring of main.dart's runApp and MyApp, without the services
/// that need a device.
Widget _app(Widget home) {
  return EasyLocalization(
    supportedLocales: const [Locale('ar'), Locale('en')],
    path: 'assets/translation',
    assetLoader: const _DeviceSpeedAssetLoader(),
    fallbackLocale: const Locale('en'),
    startLocale: AppLocalizations.currentLocale,
    saveLocale: false,
    child: MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LoginProvider()),
        ChangeNotifierProvider(create: (_) => RegisterProvider()),
        ChangeNotifierProvider(create: (_) => BottomNavProvider()),
        ChangeNotifierProvider(create: (_) => LocaleProvider()),
      ],
      child: LayoutBuilder(
        builder:
            (context, constraints) => OrientationBuilder(
              builder: (context, orientation) {
                SizeConfig().init(constraints, orientation);
                return Consumer<LocaleProvider>(
                  builder:
                      (context, language, _) => MaterialApp(
                        navigatorKey: Nav.key,
                        supportedLocales: AppLocalizations.supportedLocales,
                        locale: language.getCurrentLocale(),
                        localizationsDelegates: context.localizationDelegates,
                        home: home,
                      ),
                );
              },
            ),
      ),
    ),
  );
}

/// Fixed steps rather than pumpAndSettle: Splash's spinner never settles.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _pump(WidgetTester tester, Widget home) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(_app(home));
  await _settle(tester);
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await _settle(tester);
}

final RegExp _latinWord = RegExp(r'[A-Za-z]{2,}');

/// The phone format hint is a pattern, not a word, and reads the same in
/// both languages.
const Set<String> _meantToStayLatin = {'07xxxxxxxx'};

/// Every on-screen string and tooltip that contains a Latin word.
List<String> _englishOnScreen() {
  final found = <String>{};
  for (final element in find.byType(RichText).evaluate()) {
    final text = (element.widget as RichText).text.toPlainText().trim();
    if (_latinWord.hasMatch(text)) found.add(text);
  }
  for (final element in find.byType(Tooltip).evaluate()) {
    final message = (element.widget as Tooltip).message ?? '';
    if (_latinWord.hasMatch(message)) found.add(message);
  }
  return found.difference(_meantToStayLatin).toList();
}

/// A login endpoint, or a guard in front of it, that answers [body] with
/// [statusCode].
class _ServerReply implements HttpClientAdapter {
  _ServerReply(this.statusCode, this.body);

  final int statusCode;
  final Map<String, Object> body;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      jsonEncode(body),
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Future<String?> _loginErrorFor(int statusCode, Map<String, Object> body) async {
  final provider = LoginProvider(
    httpClientFactory: () {
      final dio = Dio(BaseOptions(validateStatus: (_) => true));
      dio.httpClientAdapter = _ServerReply(statusCode, body);
      return dio;
    },
  );
  provider.phoneCont.text = '0791234567';
  provider.passCont.text = 'Secret12345';
  await provider.logIn();
  return provider.errorMessage;
}

const String _arabicServiceUnavailable =
    'الخدمة غير متاحة حاليًا. يرجى المحاولة لاحقًا.';
const String _arabicLoginFailed = 'فشل تسجيل الدخول';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    AuthService.resetForTesting();
    // AppLocalizations is static; the next test must not inherit Arabic.
    AppLocalizations.applyLocale(const Locale('en'));
  });

  // ---------------------------------------------------------------------------
  // Every way an Arabic driver's app can start
  // ---------------------------------------------------------------------------
  group('Arabic driver: Splash, Login and Register read Arabic only', () {
    const startStates = <String, Map<String, Object>>{
      'fresh install': {'selected_language': 'ar'},
      // Builds before saveLocale: false wrote easy_localization's own copy,
      // which then made it ignore startLocale and follow the phone's language.
      'upgraded from a build that saved locale "en"': {
        'selected_language': 'ar',
        'locale': 'en',
      },
      'upgraded from a build that saved locale "ar"': {
        'selected_language': 'ar',
        'locale': 'ar',
      },
    };

    for (final state in startStates.entries) {
      testWidgets(state.key, (tester) async {
        await _startUp(state.value);
        await _pump(tester, const SplashPage());

        expect(find.text('عمليات التوصيل'), findsOneWidget);
        expect(find.text('جارٍ التحضير...'), findsOneWidget);
        expect(_englishOnScreen(), isEmpty, reason: 'Splash');

        // Splash's minimum time, then its own hand-off to Login.
        await tester.pump(const Duration(milliseconds: 1200));
        await _settle(tester);
        expect(find.byType(LoginPage), findsOneWidget);
        expect(find.text('المندوب'), findsOneWidget);
        expect(find.text('الدعم'), findsOneWidget);
        expect(_englishOnScreen(), isEmpty, reason: 'Login');

        // An empty submit shows every Login validator.
        await _tap(tester, find.text('تسجيل الدخول'));
        expect(find.text('رقم الهاتف مطلوب'), findsOneWidget);
        expect(find.text('كلمة المرور مطلوبة'), findsOneWidget);
        expect(_englishOnScreen(), isEmpty, reason: 'Login validators');

        await _tap(tester, find.text('إنشاء حساب'));
        expect(find.byType(RegisterPage), findsOneWidget);
        expect(_englishOnScreen(), isEmpty, reason: 'Register');

        await _tap(tester, find.text('إنشاء الحساب'));
        expect(find.text('يرجى إدخال اسم السائق بشكل صحيح'), findsOneWidget);
        expect(find.text('تأكيد كلمة المرور مطلوب'), findsOneWidget);
        expect(_englishOnScreen(), isEmpty, reason: 'Register validators');

        // Every other screen's tr() strings come from the same locale.
        expect(tr('hero'), 'المندوب');
        expect(tr('supportTab'), 'الدعم');
      });
    }

    testWidgets('an English driver still reads English', (tester) async {
      await _startUp({'selected_language': 'en'});
      await _pump(tester, const SplashPage());
      expect(find.text('Delivery Operations'), findsOneWidget);
      expect(find.text('Preparing...'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 1200));
      await _settle(tester);
      expect(find.byType(LoginPage), findsOneWidget);
      expect(find.text('Hero'), findsOneWidget);
      expect(find.text('Support'), findsOneWidget);
      expect(tr('hero'), 'Hero');
    });
  });

  // ---------------------------------------------------------------------------
  // Start-up: the legacy easy_localization locale cannot outvote the driver
  // ---------------------------------------------------------------------------
  group('start-up', () {
    test('discards easy_localization\'s saved locale, keeps the driver\'s', () async {
      SharedPreferences.setMockInitialValues({
        'selected_language': 'ar',
        'locale': 'en',
      });

      await AppLocalizations.initialize();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('locale'), isFalse);
      expect(prefs.getString('selected_language'), 'ar');
      expect(AppLocalizations.isArabic, isTrue);
    });

    test('main() discards it before EasyLocalization reads it', () {
      final live = File('lib/main.dart')
          .readAsLinesSync()
          .where((line) => !line.trimLeft().startsWith('//'))
          .join('\n');
      final discard = live.indexOf('await AppLocalizations.initialize();');
      final read = live.indexOf('await EasyLocalization.ensureInitialized();');

      expect(discard, isNot(-1));
      expect(read, isNot(-1));
      expect(
        discard,
        lessThan(read),
        reason:
            'EasyLocalization.ensureInitialized() reads the saved locale once; '
            'it must already be gone.',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // In-app switch: tr() must not stay in the old language
  // ---------------------------------------------------------------------------
  group('switching language inside the app', () {
    Future<void> switchTo(WidgetTester tester, String language) async {
      final context = tester.element(find.byType(LoginPage));
      final switching = context.read<LocaleProvider>().setLanguage(
        language,
        context,
      );
      // A frame lands while the new translation file is still loading, as it
      // can on a phone.
      await tester.pump();
      await _settle(tester);
      await switching;
      await _settle(tester);
    }

    testWidgets('English to Arabic', (tester) async {
      await _startUp({'selected_language': 'en'});
      await _pump(tester, const LoginPage());
      expect(tr('hero'), 'Hero');

      await switchTo(tester, LocaleProvider.arabic);

      expect(tr('hero'), 'المندوب');
      expect(tr('supportTab'), 'الدعم');
      expect(find.text('المندوب'), findsOneWidget);
      expect(_englishOnScreen(), isEmpty);
    });

    testWidgets('Arabic to English', (tester) async {
      await _startUp({'selected_language': 'ar'});
      await _pump(tester, const LoginPage());
      expect(tr('hero'), 'المندوب');

      await switchTo(tester, LocaleProvider.english);

      expect(tr('hero'), 'Hero');
      expect(tr('supportTab'), 'Support');
      expect(find.text('Hero'), findsOneWidget);
      expect(find.text('Welcome back'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // Server wording on Login: never in the other language
  // ---------------------------------------------------------------------------
  group('Login server wording for an Arabic driver', () {
    setUp(() => AppLocalizations.applyLocale(const Locale('ar')));

    test('a license restriction is answered in Arabic', () async {
      final shown = await _loginErrorFor(423, {
        'success': false,
        'status': 'error',
        'code': 'LICENSE_RESTRICTED',
        'message': 'This installation is currently unavailable.',
      });
      expect(shown, _arabicServiceUnavailable);
    });

    test('an unavailable feature is answered in Arabic', () async {
      final shown = await _loginErrorFor(403, {
        'success': false,
        'status': 'error',
        'code': 'FEATURE_UNAVAILABLE',
        'message': 'This feature is not available for this installation.',
      });
      expect(shown, _arabicServiceUnavailable);
    });

    test('an English-only message never reaches the screen', () async {
      final shown = await _loginErrorFor(403, {
        'success': false,
        'code': 'SOMETHING_NEW',
        'message': 'Access denied.',
      });
      expect(shown, _arabicServiceUnavailable);
    });

    test('message_en is not used as a fallback', () async {
      final shown = await _loginErrorFor(200, {
        'success': false,
        'code': 'INVALID_CREDENTIALS',
        'message_en': 'Invalid phone number or password',
      });
      expect(shown, _arabicLoginFailed);
    });

    test('message_ar is shown as the server wrote it', () async {
      final shown = await _loginErrorFor(200, {
        'success': false,
        'code': 'INVALID_CREDENTIALS',
        'message': 'رقم الهاتف أو كلمة المرور غير صحيحة',
        'message_en': 'Invalid phone number or password',
        'message_ar': 'رقم الهاتف أو كلمة المرور غير صحيحة',
      });
      expect(shown, 'رقم الهاتف أو كلمة المرور غير صحيحة');
    });

    test('an English driver gets the English service wording', () async {
      AppLocalizations.applyLocale(const Locale('en'));
      final shown = await _loginErrorFor(423, {
        'success': false,
        'code': 'LICENSE_RESTRICTED',
        'message': 'This installation is currently unavailable.',
      });
      expect(shown, 'Service is unavailable. Please try again later.');
    });
  });
}
