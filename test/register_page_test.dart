// Tests for driver registration.
//
// What these start from: the backend stopped returning an API key, and the app
// still read `data['data']['api_key']` into a non-nullable String — so every
// successful registration threw. Behind that, registration was saving a
// session and subscribing FCM topics for an account nobody had approved, and
// the success path never navigated anywhere.

import 'dart:convert';
import 'dart:io';

import 'package:blockatie/provider/login.dart';
import 'package:blockatie/provider/register.dart';
import 'package:blockatie/services/auth_secure_store.dart';
import 'package:blockatie/services/auth_services.dart';
import 'package:blockatie/utils/localization.dart';
import 'package:blockatie/utils/nav.dart';
import 'package:blockatie/utils/register_rules.dart';
import 'package:blockatie/views/pages/auth/login/login.dart';
import 'package:blockatie/views/pages/auth/signup/register.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show Uint8List;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// -----------------------------------------------------------------------------
// Doubles
// -----------------------------------------------------------------------------

class _FakeSecureStore implements AuthSecureStore {
  final Map<String, String> values = {};
  int writes = 0;

  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    writes++;
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async => values.remove(key);
}

/// Answers the registration POST with whatever the test chooses.
///
/// The transport is replaced, not the method — so `register()` itself runs,
/// including the busy flag the duplicate-submit guard depends on and the
/// defensive parsing of the reply.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter({this.body, this.status = 200, this.delay = Duration.zero});

  /// The JSON the endpoint would return. Null means "throw", i.e. a transport
  /// failure.
  Map<String, dynamic>? body;
  int status;
  Duration delay;
  int calls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls++;
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
    final payload = body;
    if (payload == null) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'offline',
      );
    }
    return ResponseBody.fromString(
      jsonEncode(payload),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// The shipped provider, wired to a transport the test controls.
({RegisterProvider provider, _FakeAdapter adapter}) _providerWith({
  Map<String, dynamic>? body = const {
    'success': true,
    'code': 'REGISTER_SUCCESS',
    'data': {'driver_id': 7, 'status': 'pending_activation'},
  },
  int status = 200,
  Duration delay = Duration.zero,
}) {
  final adapter = _FakeAdapter(body: body, status: status, delay: delay);
  final dio = Dio(BaseOptions(validateStatus: (_) => true))
    ..httpClientAdapter = adapter;
  return (provider: RegisterProvider(httpClient: dio), adapter: adapter);
}

/// A failure reply carrying one of the endpoint's stable codes.
Map<String, dynamic> _failure(String code) => {
  'success': false,
  'code': code,
  'message': 'server prose that must never be rendered',
  'message_en': 'server prose that must never be rendered',
  'message_ar': 'نص من الخادم يجب ألا يُعرض',
};

// -----------------------------------------------------------------------------
// Harness
// -----------------------------------------------------------------------------

Widget _app(RegisterProvider provider, {Locale locale = const Locale('en')}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<RegisterProvider>.value(value: provider),
      // Registration ends on Login, so the destination has to be buildable.
      ChangeNotifierProvider<LoginProvider>(create: (_) => LoginProvider()),
    ],
    child: MaterialApp(
      navigatorKey: Nav.key,
      locale: locale,
      supportedLocales: const [Locale('en'), Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const RegisterPage(),
    ),
  );
}

Future<void> _pump(
  WidgetTester tester,
  RegisterProvider provider, {
  Locale locale = const Locale('en'),
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(_app(provider, locale: locale));
  await tester.pumpAndSettle();
}

/// Fills every field with values that satisfy the form.
Future<void> _fillValidForm(
  WidgetTester tester,
  RegisterProvider provider, {
  String name = 'Ahmad Saleh',
  String phone = '0791234567',
  String password = 'Str0ngPass99',
  String? confirm,
}) async {
  provider.nameCont.text = name;
  provider.phoneCont.text = phone;
  provider.passCont.text = password;
  provider.confirmPassCont.text = confirm ?? password;
  await tester.pump();
}

Future<void> _tapSubmit(WidgetTester tester, String label) async {
  await tester.scrollUntilVisible(
    find.text(label),
    200,
    scrollable: find.byType(Scrollable).first,
    maxScrolls: 40,
  );
  await tester.tap(find.text(label));
}

String _source(String path) => File(path).readAsStringSync();

String _code(String path) => _source(path)
    .split('\n')
    .where(
      (line) =>
          !line.trimLeft().startsWith('//') && !line.trimLeft().startsWith('*'),
    )
    .join('\n');

const _page = 'lib/views/pages/auth/signup/register.dart';
const _provider = 'lib/provider/register.dart';

const _enSubmit = 'Create account';
const _arSubmit = 'إنشاء الحساب';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeSecureStore store;

  setUp(() {
    store = _FakeSecureStore();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    AuthService.configureForTesting(secureStore: store);
    AppLocalizations.applyLocale(const Locale('en'));
  });

  tearDown(AuthService.resetForTesting);

  // ---------------------------------------------------------------------------
  group('contract', () {
    test('4/5/6/7. registration neither reads a key nor creates a session', () {
      final source = _code(_provider);

      // The line that threw on every success.
      expect(source.contains("['api_key']"), isFalse);
      expect(source.contains('saveApiKey'), isFalse);
      expect(source.contains('saveDriverSession'), isFalse);
      expect(source.contains('subscribeToUserTopics'), isFalse);
      expect(source.contains('NotificationSystem'), isFalse);
    });

    test('the provider parses driver_id defensively', () {
      final source = _code(_provider);
      expect(
        source.contains("int.tryParse('\${payload['driver_id']}')"),
        isTrue,
      );
      expect(source.contains('RegisterOutcome.invalidResponse'), isTrue);
    });

    test(
      '62/63. registration never reaches the dead OTP or password pages',
      () {
        final source = _source(_page) + _source(_provider);
        expect(source.contains('verify_otp'), isFalse);
        expect(source.contains('signup/password.dart'), isFalse);
        expect(source.contains('auth_field'), isFalse);
      },
    );
  });

  // ---------------------------------------------------------------------------
  group('stable code mapping', () {
    test('every documented backend code maps to its own outcome', () {
      const expected = <String, RegisterOutcome>{
        'REQUIRED_FIELDS': RegisterOutcome.requiredFields,
        'NAME_TOO_LONG': RegisterOutcome.nameTooLong,
        'PHONE_TOO_LONG': RegisterOutcome.phoneTooLong,
        'PHONE_TOO_SHORT': RegisterOutcome.phoneTooShort,
        'INVALID_PHONE_PREFIX': RegisterOutcome.invalidPhonePrefix,
        'WEAK_PASSWORD': RegisterOutcome.weakPassword,
        'PASSWORD_TOO_LONG': RegisterOutcome.passwordTooLong,
        'TOO_MANY_ATTEMPTS': RegisterOutcome.tooManyAttempts,
        'PHONE_EXISTS': RegisterOutcome.phoneExists,
      };

      expected.forEach((code, outcome) {
        expect(RegisterProvider.outcomeForCode(code), outcome, reason: code);
      });
    });

    test('an internal code never gets its own wording', () {
      // Every DB_* value the endpoint could still emit collapses to the one
      // safe outcome, so "Database prepare error." cannot reach a driver.
      for (final code in const [
        'DB_PREPARE_ERROR',
        'DB_INSERT_ERROR',
        'DB_UPDATE_ERROR',
        'SERVER_ERROR',
        'SOMETHING_NEW',
        '',
      ]) {
        expect(
          RegisterProvider.outcomeForCode(code),
          RegisterOutcome.serverError,
          reason: code,
        );
      }
    });

    test('success is gated on the code, not on `success` alone', () {
      expect(_code(_provider).contains("code == 'REGISTER_SUCCESS'"), isTrue);
    });

    test('41/42/43. no raw backend text can be rendered', () {
      final page = _code(_page);
      final provider = _code(_provider);

      // Backend prose, machine tokens and HTTP numbers are all gone.
      expect(provider.contains("data['message_en']"), isFalse);
      expect(provider.contains("data['message_ar']"), isFalse);
      expect(provider.contains("data['status']"), isFalse);
      expect(page.contains('Status Code'), isFalse);
      expect(provider.contains('DB_PREPARE_ERROR'), isFalse);
      expect(provider.contains('DB_INSERT_ERROR'), isFalse);
      // Every outcome is answered by app-owned copy.
      expect(
        page.contains('String _outcomeMessage(RegisterOutcome outcome)'),
        isTrue,
      );
    });
  });

  // ---------------------------------------------------------------------------
  group('validation rules match the server', () {
    test('12/13. name bounds', () {
      expect(isValidRegisterName(''), isFalse);
      expect(isValidRegisterName('   '), isFalse);
      expect(isValidRegisterName('A'), isFalse);
      expect(isValidRegisterName('Ahmad'), isTrue);
      expect(isValidRegisterName('A' * kRegisterNameMaxLength), isTrue);
      expect(isRegisterNameTooLong('A' * (kRegisterNameMaxLength + 1)), isTrue);
    });

    test('14/15/16. the three valid Jordan prefixes are accepted', () {
      for (final phone in const ['0771234567', '0781234567', '0791234567']) {
        expect(registerPhoneProblem(phone), isNull, reason: phone);
      }
    });

    test('17. +962 and 00962 canonicalize to the local form', () {
      expect(canonicalRegisterPhone('+962791234567'), '0791234567');
      expect(canonicalRegisterPhone('00962791234567'), '0791234567');
      expect(canonicalRegisterPhone('962791234567'), '0791234567');
      expect(canonicalRegisterPhone('0791234567'), '0791234567');
      // Which means both spellings are accepted and are the same account.
      expect(registerPhoneProblem('+962791234567'), isNull);
    });

    test('18/19/20. bad prefix, short and long are refused separately', () {
      expect(
        registerPhoneProblem('0761234567'),
        RegisterPhoneProblem.invalidPrefix,
      );
      expect(registerPhoneProblem('07912345'), RegisterPhoneProblem.tooShort);
      expect(
        registerPhoneProblem('079123456789'),
        RegisterPhoneProblem.tooLong,
      );
      expect(registerPhoneProblem(''), RegisterPhoneProblem.empty);
    });

    test('21/22/23. password length is bounded at both ends', () {
      expect(
        registerPasswordProblem('short1234'),
        RegisterPasswordProblem.tooShort,
      );
      expect(registerPasswordProblem('Abcdefgh12'), isNull);
      expect(
        registerPasswordProblem('a' * (kRegisterPasswordMaxBytes + 1)),
        RegisterPasswordProblem.tooLong,
      );
      expect(
        registerPasswordProblem('Aa1${'a' * (kRegisterPasswordMaxBytes - 3)}'),
        isNull,
      );
    });

    test('Password Security V2: upper, lower and digit are required', () {
      expect(registerPasswordProblem('0123456789'), RegisterPasswordProblem.weak);
      expect(registerPasswordProblem('abcdefgh12'), RegisterPasswordProblem.weak);
      expect(registerPasswordProblem('ABCDEFGH12'), RegisterPasswordProblem.weak);
      expect(registerPasswordProblem(' Abcdefg12'), RegisterPasswordProblem.weak);
    });

    test('24. the maximum counts UTF-8 bytes, not characters', () {
      // Arabic letters are two bytes each, so 40 characters is 80 bytes.
      const arabic = 'كلمةمرورطويلةجداااااكلمةمرورطويلةجداااا';
      expect(arabic.length, lessThan(kRegisterPasswordMaxBytes));
      expect(
        utf8.encode(arabic).length,
        greaterThan(kRegisterPasswordMaxBytes),
      );
      expect(
        registerPasswordProblem(arabic),
        RegisterPasswordProblem.tooLong,
        reason: 'a character-count rule would have accepted this',
      );
    });
  });

  // ---------------------------------------------------------------------------
  group('form', () {
    testWidgets('2. renders in English', (tester) async {
      final provider = RegisterProvider();
      addTearDown(provider.dispose);
      await _pump(tester, provider);

      expect(find.text('Driver name'), findsOneWidget);
      expect(find.text('Phone number'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);
      expect(find.text('Confirm password'), findsOneWidget);
    });

    testWidgets('3. renders in Arabic', (tester) async {
      final provider = RegisterProvider();
      addTearDown(provider.dispose);
      await _pump(tester, provider, locale: const Locale('ar'));

      expect(find.text('اسم السائق'), findsOneWidget);
      expect(find.text('رقم الهاتف'), findsOneWidget);
      expect(find.text('كلمة المرور'), findsOneWidget);
      expect(find.text('تأكيد كلمة المرور'), findsOneWidget);
    });

    testWidgets('25/26. a mismatched confirmation blocks submit', (
      tester,
    ) async {
      final h = _providerWith();
      final provider = h.provider;
      addTearDown(provider.dispose);
      await _pump(tester, provider);

      await _fillValidForm(tester, provider, confirm: 'DifferentPass99');
      await _tapSubmit(tester, _enSubmit);
      await tester.pumpAndSettle();

      expect(find.text('Passwords do not match.'), findsOneWidget);
      expect(h.adapter.calls, 0, reason: 'nothing should have been sent');
    });

    testWidgets('25. an empty confirmation blocks submit', (tester) async {
      final h = _providerWith();
      final provider = h.provider;
      addTearDown(provider.dispose);
      await _pump(tester, provider);

      await _fillValidForm(tester, provider, confirm: '');
      await _tapSubmit(tester, _enSubmit);
      await tester.pumpAndSettle();

      expect(find.text('Confirm password is required'), findsOneWidget);
      expect(h.adapter.calls, 0);
    });

    testWidgets('27. a matching confirmation submits', (tester) async {
      final h = _providerWith();
      final provider = h.provider;
      addTearDown(provider.dispose);
      await _pump(tester, provider);

      await _fillValidForm(tester, provider);
      await _tapSubmit(tester, _enSubmit);
      await tester.pumpAndSettle();

      expect(h.adapter.calls, 1);
    });

    testWidgets('the Arabic mismatch message is Arabic', (tester) async {
      final h = _providerWith();
      final provider = h.provider;
      addTearDown(provider.dispose);
      await _pump(tester, provider, locale: const Locale('ar'));

      await _fillValidForm(tester, provider, confirm: 'Other12345');
      await _tapSubmit(tester, _arSubmit);
      await tester.pumpAndSettle();

      expect(find.text('كلمتا المرور غير متطابقتين.'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  group('success flow', () {
    testWidgets(
      '8/10/11. success shows pending activation then goes to Login',
      (tester) async {
        final h = _providerWith();
        final provider = h.provider;
        addTearDown(provider.dispose);
        await _pump(tester, provider);

        await _fillValidForm(tester, provider);
        await _tapSubmit(tester, _enSubmit);
        await tester.pumpAndSettle();

        expect(
          find.text(
            'Registration completed. Your account is awaiting activation.',
          ),
          findsOneWidget,
        );
        // Never claims the driver is signed in or ready for work.
        expect(find.textContaining('logged in'), findsNothing);

        await tester.tap(find.text('Back to login'));
        await tester.pumpAndSettle();

        expect(find.byType(LoginPage), findsOneWidget);
        expect(find.byType(RegisterPage), findsNothing);
        expect(h.adapter.calls, 1);
      },
    );

    testWidgets('9. the pending message reads in Arabic', (tester) async {
      final h = _providerWith();
      final provider = h.provider;
      addTearDown(provider.dispose);
      await _pump(tester, provider, locale: const Locale('ar'));

      await _fillValidForm(tester, provider);
      await _tapSubmit(tester, _arSubmit);
      await tester.pumpAndSettle();

      expect(
        find.text('تم التسجيل بنجاح. حسابك بانتظار التفعيل.'),
        findsOneWidget,
      );
    });

    testWidgets('5/6. no credential is written on success', (tester) async {
      final h = _providerWith();
      final provider = h.provider;
      addTearDown(provider.dispose);
      await _pump(tester, provider);

      await _fillValidForm(tester, provider);
      await _tapSubmit(tester, _enSubmit);
      await tester.pumpAndSettle();

      expect(store.writes, 0, reason: 'registration must not create a session');
      expect(store.values, isEmpty);
    });

    testWidgets('16. a stale session is not overwritten or inherited', (
      tester,
    ) async {
      store.values['driver_api_key'] = 'previous-key';
      store.values['driver_session_id'] = '501';
      final before = Map<String, String>.from(store.values);

      final h = _providerWith();
      final provider = h.provider;
      addTearDown(provider.dispose);
      await _pump(tester, provider);

      await _fillValidForm(tester, provider);
      await _tapSubmit(tester, _enSubmit);
      await tester.pumpAndSettle();

      expect(store.values, before, reason: 'nothing may touch the old session');
    });
  });

  // ---------------------------------------------------------------------------
  group('failure handling', () {
    /// Submits against a reply the test chooses, driving the real provider.
    Future<void> submitWith(
      WidgetTester tester,
      Map<String, dynamic>? body, {
      Locale locale = const Locale('en'),
    }) async {
      final provider = _providerWith(body: body).provider;
      addTearDown(provider.dispose);
      await _pump(tester, provider, locale: locale);
      await _fillValidForm(tester, provider);
      await _tapSubmit(
        tester,
        locale.languageCode == 'ar' ? _arSubmit : _enSubmit,
      );
      await tester.pumpAndSettle();
    }

    testWidgets('35. PHONE_EXISTS in English', (tester) async {
      await submitWith(tester, _failure('PHONE_EXISTS'));
      expect(
        find.text('This phone number is already registered.'),
        findsOneWidget,
      );
    });

    testWidgets('36. PHONE_EXISTS in Arabic', (tester) async {
      await submitWith(
        tester,
        _failure('PHONE_EXISTS'),
        locale: const Locale('ar'),
      );
      expect(find.text('رقم الهاتف مسجل بالفعل.'), findsOneWidget);
    });

    testWidgets('37. TOO_MANY_ATTEMPTS in English', (tester) async {
      await submitWith(tester, _failure('TOO_MANY_ATTEMPTS'));
      expect(
        find.text('Too many registration attempts. Please try again later.'),
        findsOneWidget,
      );
    });

    testWidgets('38. TOO_MANY_ATTEMPTS in Arabic', (tester) async {
      await submitWith(
        tester,
        _failure('TOO_MANY_ATTEMPTS'),
        locale: const Locale('ar'),
      );
      expect(
        find.text('محاولات تسجيل كثيرة. يرجى المحاولة لاحقاً.'),
        findsOneWidget,
      );
    });

    testWidgets('39/40. server error and malformed success share safe copy', (
      tester,
    ) async {
      // success:true but no driver_id — the app refuses to trust it.
      await submitWith(tester, {'success': true, 'code': 'REGISTER_SUCCESS'});
      expect(
        find.text('Unable to complete registration. Please try again later.'),
        findsOneWidget,
      );
    });

    testWidgets('a transport failure says so plainly', (tester) async {
      await submitWith(tester, null);
      expect(find.text('Unable to connect. Please try again.'), findsOneWidget);
    });

    testWidgets('46/47. failure keeps the form and stays on Register', (
      tester,
    ) async {
      final h = _providerWith(body: _failure('PHONE_EXISTS'));
      final provider = h.provider;
      addTearDown(provider.dispose);
      await _pump(tester, provider);

      await _fillValidForm(tester, provider);
      await _tapSubmit(tester, _enSubmit);
      await tester.pumpAndSettle();

      expect(find.byType(RegisterPage), findsOneWidget);
      expect(provider.nameCont.text, 'Ahmad Saleh');
      expect(provider.phoneCont.text, '0791234567');
      expect(provider.passCont.text, 'Str0ngPass99');
      expect(provider.confirmPassCont.text, 'Str0ngPass99');
      // And the button is usable again.
      expect(find.text(_enSubmit), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  group('submit safety', () {
    testWidgets('44. a second tap while in flight sends nothing', (
      tester,
    ) async {
      final h = _providerWith(delay: const Duration(milliseconds: 300));
      final provider = h.provider;
      addTearDown(provider.dispose);
      await _pump(tester, provider);
      await _fillValidForm(tester, provider);

      await _tapSubmit(tester, _enSubmit);
      await tester.pump();

      // While the request is in flight the button shows a spinner instead of
      // its label, and is disabled — so a second tap has nothing to press.
      expect(find.text(_enSubmit), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      final button = tester.widget<ElevatedButton>(
        find.byType(ElevatedButton).first,
      );
      expect(button.onPressed, isNull);

      // Press it anyway.
      await tester.tap(find.byType(ElevatedButton).first, warnIfMissed: false);
      await tester.pump();
      await tester.pumpAndSettle();

      expect(h.adapter.calls, 1);
    });

    testWidgets('48. a reply after the page is gone does nothing', (
      tester,
    ) async {
      final h = _providerWith(delay: const Duration(milliseconds: 400));
      final provider = h.provider;
      addTearDown(provider.dispose);
      await _pump(tester, provider);
      await _fillValidForm(tester, provider);

      await _tapSubmit(tester, _enSubmit);
      await tester.pump();

      // The driver leaves before the answer arrives.
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('elsewhere'))),
      );
      // Long enough for the reply to land on the disposed page.
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      expect(find.text('elsewhere'), findsOneWidget);
      expect(find.byType(RegisterPage), findsNothing);
      // The request did go out, and its answer changed nothing: no dialog, no
      // navigation, no setState on a dead State.
      expect(h.adapter.calls, 1);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(LoginPage), findsNothing);
      expect(tester.takeException(), isNull);
    });

    test('49. the global loader is not used, so it cannot double-pop', () {
      final page = _code(_page);
      final provider = _code(_provider);
      expect(provider.contains('showLoaderDialog'), isFalse);
      expect(provider.contains('hideLoaderDialog'), isFalse);
      expect(page.contains('hideLoaderDialog'), isFalse);
      // Busy state is the page's own.
      expect(page.contains('provider.isLoading'), isTrue);
    });

    test('11. success navigates exactly once', () {
      final page = _code(_page);
      expect(page.contains('bool _completed = false'), isTrue);
      expect(page.contains('if (!mounted || _completed) return;'), isTrue);
      expect('Nav.offAll(const LoginPage())'.allMatches(page).length, 3);
    });
  });

  // ---------------------------------------------------------------------------
  group('input direction and locale', () {
    TextField fieldFor(WidgetTester tester, String label) {
      return tester.widget<TextField>(
        find.ancestor(of: find.text(label), matching: find.byType(TextField)),
      );
    }

    testWidgets('28/29/30. phone and both passwords stay LTR in Arabic', (
      tester,
    ) async {
      final provider = RegisterProvider();
      addTearDown(provider.dispose);
      await _pump(tester, provider, locale: const Locale('ar'));

      for (final label in const [
        'رقم الهاتف',
        'كلمة المرور',
        'تأكيد كلمة المرور',
      ]) {
        expect(
          fieldFor(tester, label).textDirection,
          TextDirection.ltr,
          reason: label,
        );
      }
      // The name is prose and follows the page.
      expect(fieldFor(tester, 'اسم السائق').textDirection, isNull);
    });

    testWidgets('31/32. passwords opt out of correction and suggestions', (
      tester,
    ) async {
      final provider = RegisterProvider();
      addTearDown(provider.dispose);
      await _pump(tester, provider);

      for (final label in const ['Password', 'Confirm password']) {
        final field = fieldFor(tester, label);
        expect(field.autocorrect, isFalse, reason: label);
        expect(field.enableSuggestions, isFalse, reason: label);
        expect(field.obscureText, isTrue, reason: label);
      }
      expect(fieldFor(tester, 'Driver name').autocorrect, isTrue);
    });

    testWidgets('33. the visibility toggles work independently', (
      tester,
    ) async {
      final provider = RegisterProvider();
      addTearDown(provider.dispose);
      await _pump(tester, provider);

      expect(fieldFor(tester, 'Password').obscureText, isTrue);
      await tester.tap(find.byTooltip('Show password').first);
      await tester.pumpAndSettle();

      expect(fieldFor(tester, 'Password').obscureText, isFalse);
      // The confirmation is still masked: the toggles are separate.
      expect(fieldFor(tester, 'Confirm password').obscureText, isTrue);
    });

    testWidgets('34. focus order runs name to confirm password', (
      tester,
    ) async {
      final provider = RegisterProvider();
      addTearDown(provider.dispose);
      await _pump(tester, provider);

      expect(
        fieldFor(tester, 'Driver name').textInputAction,
        TextInputAction.next,
      );
      expect(
        fieldFor(tester, 'Phone number').textInputAction,
        TextInputAction.next,
      );
      expect(
        fieldFor(tester, 'Password').textInputAction,
        TextInputAction.next,
      );
      expect(
        fieldFor(tester, 'Confirm password').textInputAction,
        TextInputAction.done,
      );
    });

    testWidgets('50/51. a language switch updates the page immediately', (
      tester,
    ) async {
      final provider = RegisterProvider();
      addTearDown(provider.dispose);
      await _pump(tester, provider);
      expect(find.text('Driver name'), findsOneWidget);

      await _pump(tester, provider, locale: const Locale('ar'));
      expect(find.text('اسم السائق'), findsOneWidget);
      expect(find.text('Driver name'), findsNothing);

      await _pump(tester, provider);
      expect(find.text('Driver name'), findsOneWidget);
    });

    test('52/53. the provider makes no UI-language decision', () {
      final source = _code(_provider);
      expect(source.contains('Nav.context'), isFalse);
      expect(source.contains('AppLocalizations'), isFalse);
      expect(source.contains('_getLocalizedTypeName'), isFalse);
      expect(source.contains('easy_localization'), isFalse);
      expect(source.contains('showAlertDialog'), isFalse);
      // The page owns every visible string.
      expect(_code(_page).contains('Localizations.localeOf(context)'), isTrue);
    });

    test('9. dead provider state is gone', () {
      final source = _code(_provider);
      expect(source.contains('carNoCont'), isFalse);
      expect(source.contains('phoneMaskFormatter'), isFalse);
      expect(source.contains('MaskTextInputFormatter'), isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  group('layout', () {
    for (final size in const [Size(360, 640), Size(390, 844), Size(430, 932)]) {
      for (final locale in const [Locale('en'), Locale('ar')]) {
        testWidgets('54-59. ${size.width.toInt()}x${size.height.toInt()} '
            '${locale.languageCode}', (tester) async {
          final provider = RegisterProvider();
          addTearDown(provider.dispose);
          await _pump(tester, provider, locale: locale, size: size);
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('60. confirm password and submit are reachable at 360x640', (
      tester,
    ) async {
      final h = _providerWith();
      final provider = h.provider;
      addTearDown(provider.dispose);
      await _pump(tester, provider, size: const Size(360, 640));

      await tester.scrollUntilVisible(
        find.text('Confirm password'),
        200,
        scrollable: find.byType(Scrollable).first,
        maxScrolls: 40,
      );
      expect(find.text('Confirm password'), findsOneWidget);

      await _tapSubmit(tester, _enSubmit);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('61. long Arabic validation text does not overflow', (
      tester,
    ) async {
      final h = _providerWith();
      final provider = h.provider;
      addTearDown(provider.dispose);
      await _pump(
        tester,
        provider,
        locale: const Locale('ar'),
        size: const Size(360, 640),
      );

      await _fillValidForm(tester, provider, phone: '0761234567');
      await _tapSubmit(tester, _arSubmit);
      await tester.pumpAndSettle();

      expect(find.text('البادئة المسموحة: 077 أو 078 أو 079'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
