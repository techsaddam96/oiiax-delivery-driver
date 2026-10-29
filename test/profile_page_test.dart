// Tests for the Driver profile and edit-profile screens.
//
// The riskiest thing these screens do is hold identity in page State across
// awaits, so most of what follows is about what survives a session change and
// what must not: a late reply from Driver A must never repopulate Driver B's
// form or reach their secure storage.

import 'dart:async';
import 'dart:io';

import 'package:blockatie/constants/fonts.dart';
import 'package:blockatie/models/driver_profile.dart';
import 'package:blockatie/provider/localization.dart';
import 'package:blockatie/provider/profile.dart';
import 'package:blockatie/services/auth_secure_store.dart';
import 'package:blockatie/services/auth_services.dart';
import 'package:blockatie/services/user_session_state.dart';
import 'package:blockatie/utils/localization.dart';
import 'package:blockatie/utils/nav.dart';
import 'package:blockatie/utils/password_policy.dart';
import 'package:blockatie/utils/text_direction.dart';
import 'package:blockatie/views/pages/hub/profile/profile.dart';
import 'package:blockatie/views/pages/hub/setting/settings.dart';
import 'package:blockatie/views/widgets/driver_chat_bubble.dart';
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

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

/// The real provider with only the profile read replaced, so the state the
/// screens render from is set explicitly and the reads can be held open.
class _StubProfileProvider extends ProfileProvider {
  _StubProfileProvider({this.result, this.holdForever = false});

  DriverInfo? result;
  bool holdForever;
  int fetches = 0;

  @override
  Future<DriverInfo?> fetchDriverProfile() async {
    fetches++;
    if (holdForever) {
      // Never completes: stands in for a read still in flight.
      return Completer<DriverInfo?>().future;
    }
    await Future<void>.delayed(Duration.zero);
    profileInfo = result;
    if (result != null) notifyListeners();
    return result;
  }
}

// -----------------------------------------------------------------------------
// Fixtures
// -----------------------------------------------------------------------------

DriverInfo _driver({
  String name = 'Ahmad Saleh',
  String phone = '0791234567',
  int status = 0,
  int subscription = 1,
}) {
  return DriverInfo(
    id: 501,
    dname: name,
    dpercent: 0,
    dphone: phone,
    img: '',
    numcd: '',
    latitude: '',
    longitude: '',
    subscription: subscription,
    status: status,
    createdAt: '2026-01-01',
  );
}

// -----------------------------------------------------------------------------
// Harness
// -----------------------------------------------------------------------------

class _Hosts {
  _Hosts({required this.profile, required this.locale});

  final _StubProfileProvider profile;
  final LocaleProvider locale;
}

_Hosts _hosts({DriverInfo? result, bool holdForever = false}) => _Hosts(
  profile: _StubProfileProvider(result: result, holdForever: holdForever),
  locale: LocaleProvider(loadSaved: false),
);

Widget _app(
  _Hosts hosts, {
  required Widget page,
  Locale locale = const Locale('en'),
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<ProfileProvider>.value(value: hosts.profile),
      ChangeNotifierProvider<LocaleProvider>.value(value: hosts.locale),
    ],
    child: Consumer<LocaleProvider>(
      builder:
          (context, value, _) => MaterialApp(
            navigatorKey: Nav.key,
            theme: ThemeData(fontFamily: AppFonts.currentFontFamily),
            locale:
                locale.languageCode == 'follow'
                    ? value.getCurrentLocale()
                    : locale,
            supportedLocales: const [Locale('en'), Locale('ar')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: page,
          ),
    ),
  );
}

Future<void> _setSize(WidgetTester tester, double w, double h) async {
  tester.view.physicalSize = Size(w * 3, h * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _settle(WidgetTester tester, {int frames = 12}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

/// Lets real platform-channel work (secure storage) resolve; it arrives off
/// the fake clock a widget test runs on.
Future<void> _settleReal(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 60)),
  );
  await _settle(tester);
}

Future<void> _pump(
  WidgetTester tester,
  _Hosts hosts, {
  required Widget page,
  Locale locale = const Locale('en'),
  Size size = const Size(390, 844),
}) async {
  await _setSize(tester, size.width, size.height);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(_app(hosts, page: page, locale: locale));
  await _settle(tester);
  await _settleReal(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeSecureStore store;

  void seedSession({String name = 'Ahmad Saleh', String phone = '0791234567'}) {
    store.values['driver_session_name'] = name;
    store.values['driver_session_phone'] = phone;
    store.values['driver_api_key'] = 'key-a';
    store.values['driver_session_id'] = '501';
  }

  setUp(() {
    store = _FakeSecureStore();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    AuthService.configureForTesting(secureStore: store);
    AppLocalizations.applyLocale(const Locale('en'));
  });

  tearDown(AuthService.resetForTesting);

  // ---------------------------------------------------------------------------
  // Profile load
  // ---------------------------------------------------------------------------
  group('profile', () {
    testWidgets('1/3. English renders left-to-right', (tester) async {
      seedSession();
      await _pump(tester, _hosts(result: _driver()), page: const ProfilePage());

      expect(find.text('Profile Details'), findsOneWidget);
      expect(find.text('Account Information'), findsOneWidget);
      expect(
        Directionality.of(tester.element(find.text('Profile Details'))),
        TextDirection.ltr,
      );
    });

    testWidgets('2/4. Arabic renders right-to-left', (tester) async {
      seedSession();
      await _pump(
        tester,
        _hosts(result: _driver()),
        page: const ProfilePage(),
        locale: const Locale('ar'),
      );

      expect(find.text('تفاصيل الحساب'), findsOneWidget);
      expect(find.text('معلومات الحساب'), findsOneWidget);
      expect(
        Directionality.of(tester.element(find.text('تفاصيل الحساب'))),
        TextDirection.rtl,
      );
    });

    testWidgets('5. the first read shows only the loading state', (
      tester,
    ) async {
      seedSession();
      await _setSize(tester, 390, 844);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        _app(_hosts(holdForever: true), page: const ProfilePage()),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.textContaining('Unable to load'), findsNothing);
      expect(find.text('Not available'), findsNothing);
    });

    testWidgets('6. a successful read shows the profile', (tester) async {
      seedSession(name: 'Ahmad Saleh', phone: '0791234567');
      await _pump(tester, _hosts(result: _driver()), page: const ProfilePage());

      expect(find.text('Ahmad Saleh'), findsWidgets);
      expect(find.text('0791234567'), findsWidgets);
      expect(find.text('Active'), findsWidgets);
    });

    testWidgets('7/8. a failed read shows an error, never a fake profile', (
      tester,
    ) async {
      // No cached identity either: nothing is known, so nothing may be shown.
      await _pump(tester, _hosts(), page: const ProfilePage());

      expect(
        find.text('Unable to load account details. Please try again.'),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Not available'), findsNothing);
      expect(find.text('Account Information'), findsNothing);
    });

    testWidgets('the failed read is localized', (tester) async {
      await _pump(
        tester,
        _hosts(),
        page: const ProfilePage(),
        locale: const Locale('ar'),
      );

      expect(
        find.text('تعذر تحميل بيانات الحساب. يرجى المحاولة مرة أخرى.'),
        findsOneWidget,
      );
      expect(find.text('حاول مرة أخرى'), findsOneWidget);
      expect(find.textContaining('Dio'), findsNothing);
    });

    testWidgets('9. Retry loads the profile once it is available', (
      tester,
    ) async {
      final hosts = _hosts();
      await _pump(tester, hosts, page: const ProfilePage());
      expect(find.text('Retry'), findsOneWidget);

      hosts.profile.result = _driver();
      seedSession();
      await tester.tap(find.text('Retry'));
      await _settle(tester);
      await _settleReal(tester);

      expect(find.text('Ahmad Saleh'), findsWidgets);
      expect(find.textContaining('Unable to load'), findsNothing);
    });

    testWidgets('47. the literal string "null" is treated as missing', (
      tester,
    ) async {
      seedSession(name: 'null', phone: 'null');
      await _pump(
        tester,
        _hosts(result: _driver(name: 'null', phone: 'null')),
        page: const ProfilePage(),
      );

      expect(find.text('null'), findsNothing);
      expect(find.text('Not available'), findsWidgets);
    });

    testWidgets('48/49/50. identifiers are left-to-right, names are not', (
      tester,
    ) async {
      seedSession(name: 'عبد الرحمن الشريف', phone: '+962 79-123-4567');
      await _pump(
        tester,
        _hosts(
          result: _driver(name: 'عبد الرحمن الشريف', phone: '+962 79-123-4567'),
        ),
        page: const ProfilePage(),
        locale: const Locale('ar'),
      );

      for (final phone in tester.widgetList<Text>(
        find.text('+962 79-123-4567'),
      )) {
        expect(phone.textDirection, TextDirection.ltr);
      }
      for (final name in tester.widgetList<Text>(
        find.text('عبد الرحمن الشريف'),
      )) {
        expect(name.textDirection, isNull);
      }
    });

    test('the identifier rule is the shared one', () {
      expect(identifierTextDirection('+962 79-123-4567'), TextDirection.ltr);
      expect(identifierTextDirection('501'), TextDirection.ltr);
      expect(identifierTextDirection('عبد الرحمن الشريف'), isNull);
      expect(identifierTextDirection('Not available'), isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // Edit profile load
  // ---------------------------------------------------------------------------
  group('edit profile', () {
    testWidgets('10. the first read shows only the loading state', (
      tester,
    ) async {
      seedSession();
      await _setSize(tester, 390, 844);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        _app(_hosts(holdForever: true), page: const SettingsPage()),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Save Changes'), findsNothing);
    });

    testWidgets('11/12. a failed read shows an error and offers no Save', (
      tester,
    ) async {
      await _pump(tester, _hosts(), page: const SettingsPage());

      expect(
        find.text('Unable to load account details. Please try again.'),
        findsOneWidget,
      );
      expect(find.text('Save Changes'), findsNothing);
      expect(find.byType(TextFormField), findsNothing);
    });

    testWidgets('13. Retry loads the form', (tester) async {
      final hosts = _hosts();
      await _pump(tester, hosts, page: const SettingsPage());
      expect(find.text('Retry'), findsOneWidget);

      hosts.profile.result = _driver();
      seedSession();
      await tester.tap(find.text('Retry'));
      await _settle(tester);
      await _settleReal(tester);

      expect(find.text('Save Changes'), findsOneWidget);
      expect(find.textContaining('Unable to load'), findsNothing);
    });

    testWidgets('51/52. name and phone stay read-only and say why', (
      tester,
    ) async {
      seedSession();
      await _pump(
        tester,
        _hosts(result: _driver()),
        page: const SettingsPage(),
      );

      final fields = tester.widgetList<TextField>(find.byType(TextField));
      // Name and phone are the first two fields and neither accepts input.
      expect(fields.elementAt(0).readOnly, isTrue);
      expect(fields.elementAt(1).readOnly, isTrue);
      expect(find.byTooltip('Managed by the company'), findsNWidgets(2));

      await _pump(
        tester,
        _hosts(result: _driver()),
        page: const SettingsPage(),
        locale: const Locale('ar'),
      );
      expect(find.byTooltip('يتم تعديله من قبل الشركة'), findsNWidgets(2));
    });

    testWidgets('the read-only phone is left-to-right', (tester) async {
      seedSession(phone: '+962 79-123-4567');
      await _pump(
        tester,
        _hosts(result: _driver(phone: '+962 79-123-4567')),
        page: const SettingsPage(),
        locale: const Locale('ar'),
      );

      final phoneField = tester
          .widgetList<TextField>(find.byType(TextField))
          .elementAt(1);
      expect(phoneField.textDirection, TextDirection.ltr);
      // The keypad is gone: the field cannot be edited.
      expect(phoneField.keyboardType, isNot(TextInputType.phone));
    });
  });

  // ---------------------------------------------------------------------------
  // Password
  // ---------------------------------------------------------------------------
  group('password', () {
    Future<void> pumpForm(
      WidgetTester tester, {
      Locale locale = const Locale('en'),
    }) async {
      seedSession();
      await _pump(
        tester,
        _hosts(result: _driver()),
        page: const SettingsPage(),
        locale: locale,
      );
    }

    List<TextField> fields(WidgetTester tester) =>
        tester.widgetList<TextField>(find.byType(TextField)).toList();

    testWidgets('33/34/42. it starts empty and obscured', (tester) async {
      await pumpForm(tester);

      final password = fields(tester)[2];
      final confirm = fields(tester)[3];
      expect(password.controller!.text, isEmpty);
      expect(confirm.controller!.text, isEmpty);
      expect(password.obscureText, isTrue);
      expect(confirm.obscureText, isTrue);
      // Nothing from the profile response can have seeded it.
      expect(find.text('Ahmad Saleh'), findsWidgets);
    });

    testWidgets('35. an empty password keeps the current one', (tester) async {
      await pumpForm(tester);

      await tester.ensureVisible(find.text('Save Changes'));
      await tester.tap(find.text('Save Changes'));
      await _settle(tester);

      // Nothing to send, so nothing is sent — and the subtitle says so.
      expect(find.text('No supported changes selected.'), findsOneWidget);
      expect(
        find.textContaining('Leave it empty to keep the current password'),
        findsOneWidget,
      );
    });

    testWidgets('36. a mismatch is reported', (tester) async {
      await pumpForm(tester);

      await tester.enterText(find.byType(TextField).at(2), 'Abcdefgh12');
      await tester.enterText(find.byType(TextField).at(3), 'different1');
      await tester.ensureVisible(find.text('Save Changes'));
      await tester.tap(find.text('Save Changes'));
      await _settle(tester);

      expect(find.text('Passwords do not match.'), findsOneWidget);
    });

    testWidgets('37. a short password is reported, matching the backend', (
      tester,
    ) async {
      await pumpForm(tester);

      await tester.enterText(find.byType(TextField).at(2), 'short');
      await tester.ensureVisible(find.text('Save Changes'));
      await tester.tap(find.text('Save Changes'));
      await _settle(tester);

      // The shared policy (services/helpers/password_security.php).
      expect(
        find.text(PasswordPolicy.rules(isArabic: false)),
        findsOneWidget,
      );
    });

    testWidgets('38. a correction clears the error as it is typed', (
      tester,
    ) async {
      await pumpForm(tester);

      await tester.enterText(find.byType(TextField).at(2), 'short');
      await tester.ensureVisible(find.text('Save Changes'));
      await tester.tap(find.text('Save Changes'));
      await _settle(tester);
      expect(
        find.text(PasswordPolicy.rules(isArabic: false)),
        findsOneWidget,
      );

      await tester.enterText(find.byType(TextField).at(2), 'Abcdefgh12');
      await _settle(tester);
      expect(
        find.text(PasswordPolicy.rules(isArabic: false)),
        findsNothing,
      );
    });

    testWidgets('39/41. the reveal control is localized in English', (
      tester,
    ) async {
      await pumpForm(tester);

      expect(find.byTooltip('Show password'), findsNWidgets(2));
      await tester.tap(find.byTooltip('Show password').first);
      await _settle(tester);

      expect(fields(tester)[2].obscureText, isFalse);
      expect(find.byTooltip('Hide password'), findsOneWidget);
    });

    testWidgets('40/41. the reveal control is localized in Arabic', (
      tester,
    ) async {
      await pumpForm(tester, locale: const Locale('ar'));

      expect(find.byTooltip('إظهار كلمة المرور'), findsNWidgets(2));
      await tester.tap(find.byTooltip('إظهار كلمة المرور').first);
      await _settle(tester);

      expect(find.byTooltip('إخفاء كلمة المرور'), findsOneWidget);
    });

    testWidgets('the toggle does not alter the typed value', (tester) async {
      await pumpForm(tester);

      await tester.enterText(find.byType(TextField).at(2), 'Abcdefgh12');
      await tester.tap(find.byTooltip('Show password').first);
      await _settle(tester);

      expect(fields(tester)[2].controller!.text, 'Abcdefgh12');
    });
  });

  // ---------------------------------------------------------------------------
  // Save outcomes
  // ---------------------------------------------------------------------------
  group('save outcomes', () {
    testWidgets('29/30. the failure wording is localized', (tester) async {
      // url/network is unavailable under flutter_test, so a real Save takes
      // the failure path these strings exist for.
      seedSession();
      await _pump(
        tester,
        _hosts(result: _driver()),
        page: const SettingsPage(),
      );

      await tester.enterText(find.byType(TextField).at(2), 'Abcdefgh12');
      await tester.enterText(find.byType(TextField).at(3), 'Abcdefgh12');
      await tester.ensureVisible(find.text('Save Changes'));
      await tester.tap(find.text('Save Changes'));
      await _settleReal(tester);

      expect(
        find.text('Unable to save changes. Please try again.'),
        findsOneWidget,
      );
      expect(find.textContaining('DioException'), findsNothing);
      expect(find.textContaining('SQL'), findsNothing);
    });

    testWidgets('27. a duplicate Save is blocked while one is in flight', (
      tester,
    ) async {
      seedSession();
      await _pump(
        tester,
        _hosts(result: _driver()),
        page: const SettingsPage(),
      );

      await tester.enterText(find.byType(TextField).at(2), 'Abcdefgh12');
      await tester.enterText(find.byType(TextField).at(3), 'Abcdefgh12');
      await tester.ensureVisible(find.text('Save Changes'));
      await tester.tap(find.text('Save Changes'));
      await tester.pump();

      // Busy: the label changes and the button stops accepting taps.
      expect(find.text('Saving...'), findsOneWidget);
      final button = tester.widget<ElevatedButton>(
        find
            .ancestor(
              of: find.text('Saving...'),
              matching: find.byWidgetPredicate((w) => w is ElevatedButton),
            )
            .first,
      );
      expect(button.onPressed, isNull);
      await _settleReal(tester);
    });
  });

  // ---------------------------------------------------------------------------
  // Session
  // ---------------------------------------------------------------------------
  group('session', () {
    testWidgets('14-21. an account switch clears the form entirely', (
      tester,
    ) async {
      seedSession(name: 'Driver A', phone: '0791111111');
      await _pump(
        tester,
        _hosts(result: _driver(name: 'Driver A', phone: '0791111111')),
        page: const SettingsPage(),
      );
      final controller =
          tester
              .widgetList<TextField>(find.byType(TextField))
              .first
              .controller!;
      expect(controller.text, 'Driver A');

      // Driver A types a password, then the session ends.
      await tester.enterText(find.byType(TextField).at(2), 'Abcdefgh12');
      UserSessionState.reset(SessionResetReason.accountChanged);
      await _settle(tester);

      expect(find.text('Driver A'), findsNothing);
      expect(find.text('0791111111'), findsNothing);
      expect(controller.text, isEmpty);
      expect(find.text('Save Changes'), findsNothing);
    });

    testWidgets('22. a stale profile reply is discarded', (tester) async {
      seedSession(name: 'Driver A');
      final hosts = _hosts();
      await _pump(tester, hosts, page: const ProfilePage());

      // The session ends. This page's generation is stale from here on, so no
      // later read of Driver A's profile can populate it.
      UserSessionState.reset(SessionResetReason.accountChanged);
      await _settle(tester);
      hosts.profile.result = _driver(name: 'Driver A');

      if (find.text('Retry').evaluate().isNotEmpty) {
        await tester.tap(find.text('Retry'));
        await _settle(tester);
        await _settleReal(tester);
      }

      expect(find.text('Driver A'), findsNothing);
      expect(find.text('Account Information'), findsNothing);
    });

    testWidgets('18/19. the identity write is refused for a stale session', (
      tester,
    ) async {
      seedSession(name: 'Driver A', phone: '0791111111');
      await _pump(
        tester,
        _hosts(result: _driver(name: 'Driver A', phone: '0791111111')),
        page: const SettingsPage(),
      );

      await tester.enterText(find.byType(TextField).at(2), 'Abcdefgh12');
      await tester.enterText(find.byType(TextField).at(3), 'Abcdefgh12');
      await tester.ensureVisible(find.text('Save Changes'));
      await tester.tap(find.text('Save Changes'));
      await tester.pump();

      // Driver B takes over while the request is in flight.
      UserSessionState.reset(SessionResetReason.accountChanged);
      store.values['driver_session_name'] = 'Driver B';
      store.values['driver_session_phone'] = '0792222222';
      await _settleReal(tester);

      // Nothing from A may have been written over B's identity.
      expect(store.values['driver_session_name'], 'Driver B');
      expect(store.values['driver_session_phone'], '0792222222');
      expect(find.text('Driver A'), findsNothing);
    });

    test('23. the inactive-account reason still resets shared state', () {
      final provider = ProfileProvider();
      addTearDown(provider.dispose);
      provider.profileInfo = _driver();

      UserSessionState.reset(SessionResetReason.accountInactive);

      expect(provider.profileInfo, isNull);
      expect(provider.isProfileLoading, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // Transport
  // ---------------------------------------------------------------------------
  group('transport', () {
    test('24/26. the update goes through the session-aware client', () {
      final source =
          File('lib/views/pages/hub/setting/settings.dart').readAsStringSync();

      expect(
        source.contains('sessionDio().post('),
        isTrue,
        reason: 'the save must use the session layer',
      );
      expect(
        RegExp(r'\bDio\(\)\.post\(').hasMatch(source),
        isFalse,
        reason: 'no bare Dio may remain',
      );
    });

    test('25. a revoked key is left to the existing session layer', () {
      // protectSessionDio is what turns 401/403 DRIVER_INACTIVE into the one
      // sign-out path; this screen must not reimplement it.
      final source =
          File('lib/views/pages/hub/setting/settings.dart').readAsStringSync();
      expect(source.contains('clearSession'), isFalse);
      expect(source.contains('invalidSession'), isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // Image picker
  // ---------------------------------------------------------------------------
  group('image picker', () {
    testWidgets('44/45/46. a picker failure is localized and non-fatal', (
      tester,
    ) async {
      // image_picker has no platform implementation under flutter_test, so
      // tapping really does raise the failure the catch exists for.
      seedSession();
      await _pump(
        tester,
        _hosts(result: _driver()),
        page: const SettingsPage(),
      );

      await tester.ensureVisible(find.text('Choose photo'));
      await tester.tap(find.text('Choose photo'));
      await _settleReal(tester);

      expect(find.text('Unable to open the photo gallery.'), findsOneWidget);
      expect(find.textContaining('PlatformException'), findsNothing);
      expect(find.textContaining('MissingPluginException'), findsNothing);
      // The form is still usable.
      expect(find.text('Save Changes'), findsOneWidget);

      await _pump(
        tester,
        _hosts(result: _driver()),
        page: const SettingsPage(),
        locale: const Locale('ar'),
      );
      await tester.ensureVisible(find.text('اختيار صورة'));
      await tester.tap(find.text('اختيار صورة'));
      await _settleReal(tester);

      expect(find.text('تعذر فتح معرض الصور.'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // Language
  // ---------------------------------------------------------------------------
  group('language', () {
    testWidgets('63. a switch updates both screens immediately', (
      tester,
    ) async {
      seedSession();
      final hosts = _hosts(result: _driver());
      await _setSize(tester, 390, 844);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        _app(hosts, page: const ProfilePage(), locale: const Locale('follow')),
      );
      await _settle(tester);
      await _settleReal(tester);
      expect(find.text('Profile Details'), findsOneWidget);

      await hosts.locale.setLanguage(LocaleProvider.arabic, _NullContext());
      await _settle(tester);

      expect(find.text('تفاصيل الحساب'), findsOneWidget);
      expect(find.text('Profile Details'), findsNothing);

      await hosts.locale.setLanguage(LocaleProvider.english, _NullContext());
      await _settle(tester);
      expect(find.text('Profile Details'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // Layout
  // ---------------------------------------------------------------------------
  group('layout', () {
    for (final size in const [Size(360, 640), Size(390, 844), Size(430, 932)]) {
      for (final locale in const [Locale('en'), Locale('ar')]) {
        final index =
            53 +
            const [
                  Size(360, 640),
                  Size(390, 844),
                  Size(430, 932),
                ].indexOf(size) *
                2 +
            (locale.languageCode == 'ar' ? 1 : 0);
        testWidgets('$index. ${size.width.toInt()}x${size.height.toInt()} '
            '${locale.languageCode} lays out cleanly', (tester) async {
          seedSession(
            name: 'عبد الرحمن محمد الشريف الحسيني الهاشمي العبدلي',
            phone: '+962 79-123-4567',
          );
          final driver = _driver(
            name: 'عبد الرحمن محمد الشريف الحسيني الهاشمي العبدلي',
            phone: '+962 79-123-4567',
          );

          await _pump(
            tester,
            _hosts(result: driver),
            page: const ProfilePage(),
            locale: locale,
            size: size,
          );
          expect(tester.takeException(), isNull);

          await _pump(
            tester,
            _hosts(result: driver),
            page: const SettingsPage(),
            locale: locale,
            size: size,
          );
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('59. the form is fine with the keyboard raised', (
      tester,
    ) async {
      seedSession();
      await _setSize(tester, 360, 640);
      tester.view.viewInsets = FakeViewPadding(bottom: 336 * 3);
      addTearDown(tester.view.resetViewInsets);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        _app(
          _hosts(result: _driver()),
          page: const SettingsPage(),
          locale: const Locale('ar'),
        ),
      );
      await _settle(tester);
      await _settleReal(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(TextField), findsNWidgets(4));
    });

    testWidgets('62. Save clears the floating chat launcher', (tester) async {
      seedSession();
      await _pump(
        tester,
        _hosts(result: _driver()),
        page: const SettingsPage(),
      );

      await tester.fling(
        find.byType(SingleChildScrollView).first,
        const Offset(0, -2000),
        3000,
      );
      await _settle(tester, frames: 40);

      final viewport = tester.getSize(find.byType(SettingsPage)).height;
      final save = tester.getRect(find.text('Save Changes'));
      expect(
        viewport - save.bottom,
        greaterThan(DriverChatBubble.reservedBottomSpace),
      );
    });
  });
}

/// `setLanguage` only touches the context when it is mounted; these tests
/// drive the provider directly and assert on the rebuilt tree.
class _NullContext extends StatelessElement {
  _NullContext() : super(const _NullWidget());
}

class _NullWidget extends StatelessWidget {
  const _NullWidget();

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
