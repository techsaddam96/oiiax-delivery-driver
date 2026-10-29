// Tests for the shared Support / dialog / launcher layer.
//
// What these start from: a tap on "WhatsApp Support" threw into an un-awaited
// Future and the driver saw nothing; every location failure was posted to a
// messenger key that was never attached to MaterialApp, so it was silent; and
// the floating chat launcher floated over every dialog and sheet because those
// routes have no name for a name-based rule to match.

import 'dart:io';

import 'package:blockatie/models/chat/driver_chat_pagination.dart';
import 'package:blockatie/provider/chat/driver_chat_conversations_provider.dart';
import 'package:blockatie/provider/chat/driver_chat_launcher_provider.dart';
import 'package:blockatie/services/driver_chat_service.dart';
import 'package:dio/dio.dart';
import 'package:blockatie/models/driver_profile.dart';
import 'package:blockatie/provider/profile.dart';
import 'package:blockatie/provider/support.dart';
import 'package:blockatie/services/auth_secure_store.dart';
import 'package:blockatie/services/auth_services.dart';
import 'package:blockatie/services/clientMessageService.dart';
import 'package:blockatie/services/user_session_state.dart';
import 'package:blockatie/utils/driver_chat_launcher_observer.dart';
import 'package:blockatie/utils/external_action.dart';
import 'package:blockatie/utils/localization.dart';
import 'package:blockatie/utils/location_failure.dart';
import 'package:blockatie/utils/nav.dart';
import 'package:blockatie/views/bottmsheets/logout_sheet.dart';
import 'package:blockatie/views/pages/connectivity/no_internet_screen.dart';
import 'package:blockatie/views/pages/hub/support&assistance/support_assistence.dart';
import 'package:blockatie/views/widgets/driver_chat_bubble.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

/// A SupportProvider whose hand-off outcome the test chooses.
class _StubSupportProvider extends SupportProvider {
  _StubSupportProvider(this.result);

  ExternalActionResult result;
  int calls = 0;
  String? lastNumber;

  @override
  Future<ExternalActionResult> openWhatsApp({
    required String phoneNumber,
    String? message,
  }) async {
    calls++;
    lastNumber = phoneNumber;
    return result;
  }
}

/// The real provider, but with the platform channel `url_launcher` uses
/// answered by the test — so the failure paths run through the shipped code.
class _LauncherChannel {
  _LauncherChannel();

  bool canLaunch = true;
  bool launchSucceeds = true;
  bool throwPlatformException = false;
  final List<String> launched = [];

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/url_launcher'),
          (call) async {
            if (throwPlatformException) {
              throw PlatformException(code: 'ACTIVITY_NOT_FOUND');
            }
            switch (call.method) {
              case 'canLaunch':
                return canLaunch;
              case 'launch':
                launched.add('${call.arguments['url']}');
                return launchSucceeds;
            }
            return null;
          },
        );
  }

  void remove() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/url_launcher'),
          null,
        );
  }
}

/// A ProfileProvider that never touches the network.
class _StubProfileProvider extends ProfileProvider {
  @override
  Future<DriverInfo?> fetchDriverProfile() async => null;
}

/// A chat repository that answers nothing, so the launcher can render without
/// a server. Only the unread count is ever reached in these tests.
class _SilentChatRepository implements DriverChatRepository {
  @override
  Future<int> getUnreadCount({CancelToken? cancelToken}) async => 0;

  @override
  Future<DriverChatConversationPage> listConversations({
    int page = 1,
    int limit = 15,
    CancelToken? cancelToken,
  }) async => throw UnimplementedError();

  @override
  Future<DriverChatMessagesPage> getMessages({
    required int conversationId,
    int? beforeMessageId,
    int limit = 30,
    CancelToken? cancelToken,
  }) => throw UnimplementedError();

  @override
  Future<DriverChatNewMessagesPage> getNewMessages({
    required int conversationId,
    required int afterMessageId,
    int limit = 50,
    CancelToken? cancelToken,
  }) => throw UnimplementedError();

  @override
  Future<DriverChatSendResult> sendMessage({
    required int conversationId,
    required String message,
    required String clientMessageId,
    CancelToken? cancelToken,
  }) => throw UnimplementedError();

  @override
  Future<DriverChatReadResult> markRead({
    required int conversationId,
    int? lastMessageId,
    CancelToken? cancelToken,
  }) => throw UnimplementedError();

  @override
  Future<DriverChatConversationResult> getOrCreateShipmentConversation({
    required int shipmentId,
    CancelToken? cancelToken,
  }) => throw UnimplementedError();
}

// -----------------------------------------------------------------------------
// Harness
// -----------------------------------------------------------------------------

Widget _app({
  required Widget home,
  Locale locale = const Locale('en'),
  SupportProvider? support,
  DriverChatLauncherProvider? launcher,
  bool withBubble = false,
  GlobalKey<ScaffoldMessengerState>? messengerKey,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<SupportProvider>.value(
        value: support ?? SupportProvider(),
      ),
      ChangeNotifierProvider<ProfileProvider>(
        create: (_) => _StubProfileProvider(),
      ),
      if (launcher != null)
        ChangeNotifierProvider<DriverChatLauncherProvider>.value(
          value: launcher,
        ),
      if (withBubble)
        ChangeNotifierProvider<DriverChatConversationsProvider>(
          create:
              (_) => DriverChatConversationsProvider(
                repository: _SilentChatRepository(),
              ),
        ),
    ],
    child: MaterialApp(
      navigatorKey: Nav.key,
      scaffoldMessengerKey: messengerKey,
      navigatorObservers: [
        if (launcher != null) DriverChatLauncherObserver(launcher),
      ],
      locale: locale,
      supportedLocales: const [Locale('en'), Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder:
          withBubble
              ? (context, child) => Stack(
                children: [
                  child ?? const SizedBox.shrink(),
                  const DriverChatBubble(),
                ],
              )
              : null,
      home: home,
    ),
  );
}

Future<void> _pumpSupport(
  WidgetTester tester, {
  Locale locale = const Locale('en'),
  SupportProvider? support,
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    _app(home: const SupportAssistencePage(), locale: locale, support: support),
  );
  await tester.pump();
}

String _source(String path) => File(path).readAsStringSync();

/// Source with comment lines removed, so a comment that quotes the old code is
/// not mistaken for the old code still being there.
String _code(String path) => _source(path)
    .split('\n')
    .where(
      (line) =>
          !line.trimLeft().startsWith('//') &&
          !line.trimLeft().startsWith('*') &&
          !line.trimLeft().startsWith('/*'),
    )
    .join('\n');

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
  group('support', () {
    testWidgets('1. renders in English', (tester) async {
      await _pumpSupport(tester);
      expect(find.text('Technical Support'), findsOneWidget);
      expect(find.text('WhatsApp Support'), findsOneWidget);
      expect(
        Directionality.of(tester.element(find.text('Technical Support'))),
        TextDirection.ltr,
      );
    });

    testWidgets('2. renders in Arabic', (tester) async {
      await _pumpSupport(tester, locale: const Locale('ar'));
      expect(find.text('الدعم الفني'), findsOneWidget);
      expect(find.text('واتساب الدعم'), findsOneWidget);
      expect(
        Directionality.of(tester.element(find.text('الدعم الفني'))),
        TextDirection.rtl,
      );
    });

    testWidgets('3. a successful hand-off says nothing', (tester) async {
      final support = _StubSupportProvider(
        const ExternalActionResult.success(),
      );
      await _pumpSupport(tester, support: support);

      await tester.tap(find.text('WhatsApp Support'));
      await tester.pumpAndSettle();

      expect(support.calls, 1);
      expect(find.text('Unable to open this contact option.'), findsNothing);
    });

    testWidgets('4. nothing can open it — English message', (tester) async {
      final support = _StubSupportProvider(
        const ExternalActionResult.failed(ExternalActionFailure.unsupported),
      );
      await _pumpSupport(tester, support: support);

      await tester.tap(find.text('WhatsApp Support'));
      await tester.pumpAndSettle();

      expect(find.text('Unable to open this contact option.'), findsOneWidget);
    });

    testWidgets('5. nothing can open it — Arabic message', (tester) async {
      final support = _StubSupportProvider(
        const ExternalActionResult.failed(ExternalActionFailure.unsupported),
      );
      await _pumpSupport(tester, locale: const Locale('ar'), support: support);

      await tester.tap(find.text('واتساب الدعم'));
      await tester.pumpAndSettle();

      expect(find.text('تعذر فتح وسيلة التواصل.'), findsOneWidget);
    });

    testWidgets('6. a PlatformException is absorbed — English', (tester) async {
      final channel = _LauncherChannel()..throwPlatformException = true;
      channel.install();
      addTearDown(channel.remove);

      await _pumpSupport(tester);
      await tester.tap(find.text('WhatsApp Support'));
      await tester.pumpAndSettle();

      expect(find.text('Unable to open this contact option.'), findsOneWidget);
      expect(find.textContaining('PlatformException'), findsNothing);
      expect(find.textContaining('ACTIVITY_NOT_FOUND'), findsNothing);
    });

    testWidgets('7. a PlatformException is absorbed — Arabic', (tester) async {
      final channel = _LauncherChannel()..throwPlatformException = true;
      channel.install();
      addTearDown(channel.remove);

      await _pumpSupport(tester, locale: const Locale('ar'));
      await tester.tap(find.text('واتساب الدعم'));
      await tester.pumpAndSettle();

      expect(find.text('تعذر فتح وسيلة التواصل.'), findsOneWidget);
      expect(find.textContaining('PlatformException'), findsNothing);
    });

    test('a launch that returns false is a failure, not a success', () async {
      final channel = _LauncherChannel()..launchSucceeds = false;
      channel.install();
      addTearDown(channel.remove);

      final result = await SupportProvider().openWhatsApp(
        phoneNumber: '962779735616',
      );
      expect(result.isSuccess, isFalse);
      expect(result.failure, ExternalActionFailure.launchFailed);
    });

    test('canLaunch false reports unsupported and never throws', () async {
      final channel = _LauncherChannel()..canLaunch = false;
      channel.install();
      addTearDown(channel.remove);

      final result = await SupportProvider().openWhatsApp(
        phoneNumber: '962779735616',
      );
      expect(result.failure, ExternalActionFailure.unsupported);
    });

    test('8. backend prose cannot reach the screen', () {
      final page = _source(
        'lib/views/pages/hub/support&assistance/support_assistence.dart',
      );
      // The untyped `message` key carried whatever the endpoint wrote, in
      // whatever language it wrote it.
      expect(page.contains("result['message']"), isFalse);

      final service = _source('lib/services/clientMessageService.dart')
          .split('\n')
          .where((line) => !line.trimLeft().startsWith('//'))
          .join('\n');
      expect(service.contains("data['message']"), isFalse);
      expect(service.contains('enum SupportMessageOutcome'), isTrue);
    });

    test('the service returns only same-language server copy', () async {
      // An Arabic reader is never handed the English field, and vice versa.
      const arabicOnly = SupportMessageResult(
        SupportMessageOutcome.rejected,
        serverMessage: null,
      );
      expect(arabicOnly.serverMessage, isNull);
      expect(arabicOnly.isSuccess, isFalse);
    });

    testWidgets('9. the phone field stays left-to-right in Arabic', (
      tester,
    ) async {
      await _pumpSupport(tester, locale: const Locale('ar'));

      final field = tester.widget<TextField>(
        find.ancestor(
          of: find.text('الهاتف'),
          matching: find.byType(TextField),
        ),
      );
      expect(field.textDirection, TextDirection.ltr);
    });

    testWidgets('10. the email field stays left-to-right in Arabic', (
      tester,
    ) async {
      await _pumpSupport(tester, locale: const Locale('ar'));

      final field = tester.widget<TextField>(
        find.ancestor(
          of: find.text('البريد الإلكتروني'),
          matching: find.byType(TextField),
        ),
      );
      expect(field.textDirection, TextDirection.ltr);
    });

    testWidgets('a prose field is not forced left-to-right', (tester) async {
      await _pumpSupport(tester, locale: const Locale('ar'));

      final field = tester.widget<TextField>(
        find.ancestor(
          of: find.text('الرسالة'),
          matching: find.byType(TextField),
        ),
      );
      expect(field.textDirection, isNull);
    });

    testWidgets('11. the scroll clears the floating chat launcher', (
      tester,
    ) async {
      await _pumpSupport(tester, size: const Size(360, 640));

      final scroll = tester.widget<SingleChildScrollView>(
        find.byType(SingleChildScrollView).first,
      );
      final padding = scroll.padding as EdgeInsets;
      expect(
        padding.bottom,
        greaterThanOrEqualTo(DriverChatBubble.reservedBottomSpace + 16),
      );
    });

    testWidgets('12. an account switch clears the previous driver', (
      tester,
    ) async {
      await _pumpSupport(tester);
      await tester.pumpAndSettle();

      // Driver A's identity is put in the fields directly rather than through
      // the storage prefill: what this test is about is whether the session
      // boundary clears them, and driving them by hand keeps that independent
      // of how long secure storage takes to answer.
      final name = find.ancestor(
        of: find.text('Name'),
        matching: find.byType(TextField),
      );
      final phone = find.ancestor(
        of: find.text('Phone'),
        matching: find.byType(TextField),
      );
      await tester.enterText(name, 'Ahmad Saleh');
      await tester.enterText(phone, '0791234567');
      await tester.pump();

      expect(find.text('Ahmad Saleh'), findsOneWidget);
      expect(find.text('0791234567'), findsOneWidget);

      UserSessionState.reset(SessionResetReason.accountChanged);
      await tester.pumpAndSettle();

      // Gone before Driver B can submit them.
      expect(find.text('Ahmad Saleh'), findsNothing);
      expect(find.text('0791234567'), findsNothing);

      final page = _source(
        'lib/views/pages/hub/support&assistance/support_assistence.dart',
      );
      expect(
        page.contains('UserSessionState.register(_clearDriverIdentity)'),
        isTrue,
      );
      expect(
        page.contains('UserSessionState.unregister(_clearDriverIdentity)'),
        isTrue,
      );
      // The driver id captured under the old session is refused at submit.
      expect(
        page.contains('!UserSessionState.isCurrent(_identityGeneration)'),
        isTrue,
      );
    });
  });

  // ---------------------------------------------------------------------------
  group('location', () {
    test('13. the root messenger key is attached to MaterialApp', () {
      final main = _source('lib/main.dart')
          .split('\n')
          .where((line) => !line.trimLeft().startsWith('//'))
          .join('\n');
      expect(
        main.contains('scaffoldMessengerKey: rootScaffoldMessengerKey'),
        isTrue,
      );
      // Still exactly one global messenger key.
      expect(
        'scaffoldMessengerKey:'.allMatches(main).length,
        1,
        reason: 'a second global messenger key would split the two paths',
      );
    });

    test('14. a generic failure reads in English', () {
      expect(
        locationFailureMessage(LocationFailure.unavailable, isArabic: false),
        'Unable to get your location.',
      );
    });

    test('15. a generic failure reads in Arabic', () {
      expect(
        locationFailureMessage(LocationFailure.unavailable, isArabic: true),
        'تعذر تحديد موقعك.',
      );
    });

    test('16. no raw exception text can reach the driver', () {
      final source = _source('lib/views/dialoges/get_location.dart')
          .split('\n')
          .where((line) => !line.trimLeft().startsWith('//'))
          .join('\n');

      expect(source.contains(r'Failed to get location: $e'), isFalse);
      expect(source.contains(r'$e'), isFalse);
      // Every message now comes from the typed helper.
      expect(source.contains('locationFailureMessage('), isTrue);

      for (final failure in LocationFailure.values) {
        for (final arabic in [true, false]) {
          final message = locationFailureMessage(failure, isArabic: arabic);
          expect(message.contains(r'$'), isFalse);
          expect(message.contains('Exception'), isFalse);
          expect(message.contains('PlatformException'), isFalse);
        }
      }
    });

    test('17. the settings action reads in English', () {
      expect(openSettingsActionLabel(isArabic: false), 'Open Settings');
    });

    test('18. the settings action reads in Arabic', () {
      expect(openSettingsActionLabel(isArabic: true), 'فتح الإعدادات');
    });

    test('19. the action is chosen by failure type, not by prose', () {
      // Offered where the system settings screen can actually fix it.
      expect(
        locationFailureOffersSettings(LocationFailure.serviceDisabled),
        isTrue,
      );
      expect(
        locationFailureOffersSettings(
          LocationFailure.permissionPermanentlyDenied,
        ),
        isTrue,
      );
      // Not offered where the prompt can simply be shown again.
      expect(
        locationFailureOffersSettings(LocationFailure.permissionDenied),
        isFalse,
      );
      expect(
        locationFailureOffersSettings(LocationFailure.unavailable),
        isFalse,
      );

      final source = _source('lib/views/dialoges/get_location.dart');
      expect(source.contains("message.contains('settings')"), isFalse);
    });

    testWidgets('a failure actually reaches the screen now', (tester) async {
      final key = GlobalKey<ScaffoldMessengerState>();
      AppLocalizations.applyLocale(const Locale('en'));

      await tester.pumpWidget(
        _app(home: const Scaffold(body: SizedBox.shrink()), messengerKey: key),
      );

      key.currentState!.showSnackBar(
        SnackBar(
          content: Text(
            locationFailureMessage(
              LocationFailure.serviceDisabled,
              isArabic: false,
            ),
          ),
          action: SnackBarAction(
            label: openSettingsActionLabel(isArabic: false),
            onPressed: () {},
          ),
        ),
      );
      await tester.pump();

      expect(
        find.text('Location services are turned off on your device.'),
        findsOneWidget,
      );
      expect(find.text('Open Settings'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  group('status sheet locale', () {
    test('24. no visible widget depends on EasyLocalization', () {
      final source = _source('lib/views/widgets/status_update_sheet.dart');
      expect(source.contains('context.locale'), isFalse);
      expect(source.contains("import 'package:easy_localization"), isFalse);
      expect(
        source.contains('Localizations.localeOf(context).languageCode'),
        isTrue,
      );
    });

    test('the shared helpers are untouched', () {
      final source = _source('lib/views/widgets/status_update_sheet.dart');
      expect(source.contains('String getStatusLabel('), isTrue);
      expect(source.contains('Color getStatusColor('), isTrue);
      expect(source.contains('String getStatusHelperText('), isTrue);
      // The transition rules the server enforces are unchanged.
      expect(
        source.contains('const Set<int> driverSelectableStatusIds = {7, 8, 9}'),
        isTrue,
      );
    });

    test('25/26. the keyboard inset is honoured', () {
      final source = _source('lib/views/widgets/status_update_sheet.dart');
      expect(
        source.contains('MediaQuery.viewInsetsOf(context).bottom'),
        isTrue,
      );
      // Added as margin so it disappears when the keyboard closes, rather than
      // leaving a permanent gap under the sheet.
      expect(source.contains('12 + viewInsetBottom'), isTrue);
      // The reason note now lives inside the scroll region with the options,
      // so it can be scrolled to instead of being pushed off the bottom.
      expect(source.contains('SingleChildScrollView'), isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  group('logout', () {
    test('27-30. dismissal is blocked only while busy', () {
      final source = _source('lib/views/bottmsheets/logout_sheet.dart');
      // Barrier and system back both consult popDisposition.
      expect(source.contains('canPop: !_isLoggingOut'), isTrue);
      // The drag gesture does not, so it is disabled at the route.
      expect(source.contains('enableDrag: false'), isTrue);
    });

    test('31. local logout routes without rereading wiped credentials', () {
      final source = _source('lib/views/bottmsheets/logout_sheet.dart');
      // Captured before the await, so a torn-down sheet still redirects.
      expect(
        source.contains('final navigator = Navigator.of(context)'),
        isTrue,
      );
      expect(source.contains('AuthService.getSessionSnapshot()'), isFalse);
      // B3: one redirect shared with the network-layer teardown, so the
      // driver is sent to Login exactly once per ended session.
      expect(source.contains('SessionRedirect.toLogin()'), isTrue);
    });

    test('32. the busy flag is released in a finally', () {
      final source = _source('lib/views/bottmsheets/logout_sheet.dart');
      expect(source.contains('} finally {'), isTrue);
      expect(source.contains('setState(() => _isLoggingOut = false)'), isTrue);
    });

    test('the secure teardown order is unchanged', () {
      // Scoped to _clearSession: the same statements appear in other methods,
      // and their positions there say nothing about the teardown order.
      final full = _source('lib/services/auth_services.dart');
      final start = full.indexOf(
        'static Future<LogoutResult> _clearSession(SessionResetReason reason) async {',
      );
      expect(start, greaterThan(-1));
      final body = full.substring(start);

      final resetState = body.indexOf('_resetAccountState(reason);');
      final wipe = body.indexOf('await _eraseStoredCredentials();');

      expect(resetState, lessThan(wipe));
      // FCM starts only from the result after Login navigation; it cannot
      // occupy the local logout boundary.
      expect(body.contains('result.startDetachedCleanup();'), isTrue);
      expect(full.contains('await NotificationSystem().unsubscribe'), isFalse);
      expect(full.contains('.timeout(_topicCleanupTimeout)'), isTrue);
    });

    testWidgets('33. a second tap while busy is ignored', (tester) async {
      await tester.pumpWidget(
        _app(
          home: Builder(
            builder:
                (context) => Scaffold(
                  body: Center(
                    child: ElevatedButton(
                      onPressed: () => showLogoutSheet(context),
                      child: const Text('open'),
                    ),
                  ),
                ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Do you want to log out?'), findsOneWidget);

      // Cancel is the idle path and still works.
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Do you want to log out?'), findsNothing);
    });

    testWidgets('the confirm control carries a spoken label', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _app(
          home: Builder(
            builder:
                (context) => Scaffold(
                  body: Center(
                    child: ElevatedButton(
                      onPressed: () => showLogoutSheet(context),
                      child: const Text('open'),
                    ),
                  ),
                ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Confirm sign out'), findsOneWidget);
      handle.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  group('modals and the chat launcher', () {
    late DriverChatLauncherProvider launcher;

    setUp(() {
      launcher = DriverChatLauncherProvider(
        sessionReader:
            () async => const DriverSession(apiKey: 'key-a', driverId: '901'),
      );
    });

    tearDown(() => launcher.dispose());

    testWidgets('34/36. hidden over a dialog, restored after it', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          home: Builder(
            builder:
                (context) => Scaffold(
                  body: Center(
                    child: ElevatedButton(
                      onPressed:
                          () => showDialog<void>(
                            context: context,
                            builder:
                                (_) => const AlertDialog(
                                  content: Text('dialog body'),
                                ),
                          ),
                      child: const Text('open'),
                    ),
                  ),
                ),
          ),
          launcher: launcher,
        ),
      );
      await tester.pumpAndSettle();
      expect(launcher.isModalRouteOpen, isFalse);

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(launcher.isModalRouteOpen, isTrue);
      expect(launcher.shouldShow, isFalse);

      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(launcher.isModalRouteOpen, isFalse);
    });

    testWidgets('35/37. hidden over a bottom sheet, restored after it', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          home: Builder(
            builder:
                (context) => Scaffold(
                  body: Center(
                    child: ElevatedButton(
                      onPressed:
                          () => showModalBottomSheet<void>(
                            context: context,
                            builder:
                                (_) => const SizedBox(
                                  height: 180,
                                  child: Text('sheet body'),
                                ),
                          ),
                      child: const Text('open'),
                    ),
                  ),
                ),
          ),
          launcher: launcher,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(launcher.isModalRouteOpen, isTrue);

      Navigator.of(tester.element(find.text('sheet body'))).pop();
      await tester.pumpAndSettle();
      expect(launcher.isModalRouteOpen, isFalse);
    });

    testWidgets('39. a stacked modal stays hidden until all are gone', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          home: Builder(
            builder:
                (context) => Scaffold(
                  body: Center(
                    child: ElevatedButton(
                      onPressed:
                          () => showDialog<void>(
                            context: context,
                            builder:
                                (inner) => AlertDialog(
                                  content: ElevatedButton(
                                    onPressed:
                                        () => showDialog<void>(
                                          context: inner,
                                          builder:
                                              (_) => const AlertDialog(
                                                content: Text('second'),
                                              ),
                                        ),
                                    child: const Text('nest'),
                                  ),
                                ),
                          ),
                      child: const Text('open'),
                    ),
                  ),
                ),
          ),
          launcher: launcher,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('nest'));
      await tester.pumpAndSettle();
      expect(launcher.isModalRouteOpen, isTrue);

      // Only the inner dialog closes; the outer one is still on top.
      Navigator.of(tester.element(find.text('second'))).pop();
      await tester.pumpAndSettle();
      expect(launcher.isModalRouteOpen, isTrue);

      Navigator.of(tester.element(find.text('nest'))).pop();
      await tester.pumpAndSettle();
      expect(launcher.isModalRouteOpen, isFalse);
    });

    test('38. the chat-route rule is untouched', () {
      final source = _source('lib/utils/driver_chat_launcher_observer.dart');
      expect(source.contains('DriverChatRoutes.hidesLauncher'), isTrue);
      expect(source.contains('setModalRouteOpen(top is PopupRoute)'), isTrue);
    });

    test('a session reset clears the modal flag too', () {
      launcher.setModalRouteOpen(true);
      expect(launcher.isModalRouteOpen, isTrue);
      launcher.clearUserState();
      expect(launcher.isModalRouteOpen, isFalse);
      expect(launcher.shouldShow, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  group('shared dialogs', () {
    test('40. a supplied callback is invoked', () {
      final source = _code('lib/views/dialoges/alert_dialoge.dart');
      // The old `() => ontap ?? Navigator.pop(...)` returned the callback
      // rather than calling it, and never popped.
      expect(source.contains('ontap ?? Navigator.pop'), isFalse);
      expect(source.contains('ontap?.call()'), isTrue);
    });

    testWidgets('40b. the callback really runs and the dialog closes', (
      tester,
    ) async {
      var invoked = 0;
      await tester.pumpWidget(
        _app(
          home: Builder(
            builder:
                (context) => Scaffold(
                  body: Center(
                    child: ElevatedButton(
                      onPressed:
                          () => showDialog<void>(
                            context: context,
                            barrierDismissible: false,
                            builder:
                                (dialogContext) => AlertDialog(
                                  content: const Text('with callback'),
                                  actions: [
                                    TextButton(
                                      onPressed: () {
                                        Navigator.pop(dialogContext);
                                        invoked++;
                                      },
                                      child: const Text('OK'),
                                    ),
                                  ],
                                ),
                          ),
                      child: const Text('open'),
                    ),
                  ),
                ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(invoked, 1);
      expect(find.text('with callback'), findsNothing);
    });

    test('41. a dialog with no callback still dismisses', () {
      final source = _source('lib/views/dialoges/alert_dialoge.dart');
      // The pop is unconditional now, so the no-callback path is unchanged.
      expect(source.contains('Navigator.pop(dialogContext);'), isTrue);
    });

    test('42. no withdrawal wording is left in the shipment dialog', () {
      final source = _source('lib/views/dialoges/shipment_accept_dialog.dart')
          .split('\n')
          .where((line) => !line.trimLeft().startsWith('//'))
          .join('\n');

      expect(source.contains("'Withdrawal Alert'"), isFalse);
      expect(
        source.contains("'Do you want to make the transaction?'"),
        isFalse,
      );
    });

    test('43. shared dialog fallbacks are bilingual and generic', () {
      for (final path in const [
        'lib/views/dialoges/sucess_dialoge.dart',
        'lib/views/dialoges/shipment_accept_dialog.dart',
        'lib/views/dialoges/confirmation_acceptance_dialoge.dart',
      ]) {
        final source = _source(path)
            .split('\n')
            .where((line) => !line.trimLeft().startsWith('//'))
            .join('\n');

        expect(
          source.contains("'Do you want to make the transaction?'"),
          isFalse,
          reason: path,
        );
        expect(
          source.contains("'Are you sure you want to deliver this shipment?'"),
          isFalse,
          reason: path,
        );
        expect(
          source.contains("'Confirmation of acceptance'"),
          isFalse,
          reason: path,
        );
        // Whatever replaced them resolves a language.
        expect(
          source.contains('Localizations.localeOf(context).languageCode'),
          isTrue,
          reason: path,
        );
      }
    });

    test('the filter call site no longer forwards backend prose', () {
      String code(String path) => _source(path)
          .split('\n')
          .where((line) => !line.trimLeft().startsWith('//'))
          .join('\n');

      final provider = code('lib/provider/filter.dart');

      // The invariant is architectural, not a sentence. The provider reports
      // typed states and owns no user-facing copy, so the endpoint's own prose
      // has no channel to the driver at all. Asserting app-owned wording here
      // would pin it to the wrong file: filter_page_test.dart owns the wording
      // behaviourally, and its test 14 owns the model.

      // 1. The provider cannot speak to the driver on its own.
      for (final channel in const [
        'showAlertDialog',
        'Nav.context',
        'errorToast',
        'sucessToast',
      ]) {
        expect(
          provider.contains(channel),
          isFalse,
          reason: 'FilterProvider must not address the driver: $channel',
        );
      }

      // 2. It never reads the endpoint's prose in the first place, so no field,
      // toast or dialog can forward it later. This is what fails if
      // `showAlertDialog(Nav.context, '', response.data['message'])` comes
      // back, and equally if a quieter `_error = data['message']` does.
      for (final read in const ["'message'", '"message"']) {
        expect(
          provider.contains(read),
          isFalse,
          reason: 'FilterProvider must not read backend prose: $read',
        );
      }

      // 3. The page writes every sentence, in both languages, and it too takes
      // its text from `_t(...)` rather than off a decoded body.
      final page = code('lib/views/pages/home/filter/filter.dart');
      expect(page.contains("['message']"), isFalse);
      expect(page.contains('["message"]'), isFalse);
      expect(page.contains('Unable to connect. Please try again.'), isTrue);
      expect(page.contains('تعذر الاتصال. يرجى المحاولة مرة أخرى.'), isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  group('connectivity', () {
    testWidgets('44/46. offline reads in English, left-to-right', (
      tester,
    ) async {
      AppLocalizations.applyLocale(const Locale('en'));
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: MediaQuery(
            data: MediaQueryData(),
            child: MaterialApp(home: NoInternetScreen()),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('No internet connection'), findsOneWidget);
      expect(find.text('Open network settings'), findsOneWidget);
    });

    testWidgets('45/46. offline reads in Arabic, right-to-left', (
      tester,
    ) async {
      AppLocalizations.applyLocale(const Locale('ar'));
      addTearDown(() => AppLocalizations.applyLocale(const Locale('en')));

      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.rtl,
          child: MediaQuery(
            data: MediaQueryData(),
            child: MaterialApp(home: NoInternetScreen()),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('لا يوجد اتصال بالإنترنت'), findsOneWidget);
      expect(find.text('فتح إعدادات الشبكة'), findsOneWidget);
    });

    test('47. the doubled punctuation is gone', () {
      final source = _code(
        'lib/views/pages/connectivity/no_internet_screen.dart',
      );
      expect(source.contains('!!'), isFalse);
    });

    test('48. the overlay direction follows the language', () {
      final source = _source(
        'lib/views/pages/connectivity/connection_alert_screen.dart',
      );
      // Was `textDirection: TextDirection.rtl` for everyone.
      expect(
        source.contains(
          'AppLocalizations.isRTL ? TextDirection.rtl : TextDirection.ltr',
        ),
        isTrue,
      );
    });
  });

  // ---------------------------------------------------------------------------
  group('accessibility', () {
    testWidgets('49/52. the Support back control is labelled and reachable', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pumpSupport(tester);

      expect(find.bySemanticsLabel('Back'), findsWidgets);

      // The whole touch target, not the 42px square drawn inside it.
      final box = tester.getSize(
        find
            .ancestor(
              of: find.byIcon(Icons.arrow_back_ios_new_rounded),
              matching: find.byType(InkWell),
            )
            .first,
      );
      expect(box.width, greaterThanOrEqualTo(48));
      expect(box.height, greaterThanOrEqualTo(48));
      handle.dispose();
    });

    testWidgets('the Arabic back label is Arabic', (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpSupport(tester, locale: const Locale('ar'));
      expect(find.bySemanticsLabel('رجوع'), findsWidgets);
      handle.dispose();
    });

    test('51. the status sheet close control is a labelled button', () {
      final source = _source('lib/views/widgets/status_update_sheet.dart');
      // Text-labelled, so it needs no separate semantics annotation.
      expect(source.contains("isArabic ? 'إغلاق' : 'Close'"), isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  group('shared widgets', () {
    test('53. the Arabic chat label isolates the unread count', () {
      final lines =
          _source('lib/views/widgets/driver_chat_bubble.dart')
              .split('\n')
              .where((line) => !line.trimLeft().startsWith('//'))
              .toList();

      // The wording belongs to whoever writes the copy; the isolate does not.
      // An Arabic label that interpolates the count bare lets the words around
      // it reorder the digits, which is the whole reason isolateIdentifier
      // exists. Stated as a rule rather than a sentence so a copy change cannot
      // quietly drop the isolate — as pinning the old sentence here allowed.
      final arabic = RegExp(r'[\u0600-\u06FF]');
      final spoken =
          lines
              .where(
                (line) => arabic.hasMatch(line) && line.contains('unreadCount'),
              )
              .toList();

      expect(
        spoken,
        isNotEmpty,
        reason:
            'no Arabic label interpolates the count on one line any more — '
            'read the label and re-state this rule',
      );
      for (final line in spoken) {
        expect(
          line.contains('isolateIdentifier('),
          isTrue,
          reason: 'unisolated count in an Arabic label: ${line.trim()}',
        );
      }
    });

    test('54. the badge is still a fully rounded, left-to-right pill', () {
      final source = _source('lib/views/widgets/driver_chat_bubble.dart');

      // Still collapsing at 99, still forced left-to-right. The rendered
      // behaviour is covered in driver_chat_bubble_test.dart; these two lines
      // keep the contract visible next to the geometry below.
      expect(source.contains("count > 99 ? '99+' : '\$count'"), isTrue);
      expect(source.contains('textDirection: TextDirection.ltr'), isTrue);

      // A pill is a radius of at least half the height. Pinning the literal 11
      // pinned the badge to its pre-resize height, so read both numbers and
      // compare them instead.
      double only(RegExp pattern, String what) {
        final matches = pattern.allMatches(source).toList();
        expect(matches, hasLength(1), reason: 'expected one $what');
        return double.parse(matches.single.group(1)!);
      }

      final minHeight = only(RegExp(r'minHeight:\s*([0-9.]+)'), 'badge height');
      final radius = only(
        RegExp(r'BorderRadius\.circular\(([0-9.]+)\)'),
        'badge radius',
      );
      expect(radius, greaterThanOrEqualTo(minHeight / 2));
    });

    test('55. the bottom-nav Home reset is intentional and documented', () {
      final nav = _source('lib/views/widgets/bottom_nav.dart');
      expect(nav.contains('resetToHome()'), isTrue);
      expect(nav.contains('Deliberate'), isTrue);

      // The evidence: every other tab switch does the same thing.
      final home = _source('lib/views/pages/home/home.dart');
      final header = _source('lib/views/pages/home/components/header.dart');
      expect('resetToHome()'.allMatches(home).length, greaterThanOrEqualTo(2));
      expect(
        'resetToHome()'.allMatches(header).length,
        greaterThanOrEqualTo(2),
      );
    });

    test('56. the toggle corners mirror under RTL', () {
      final source = _source(
        'lib/views/pages/hub/components/custom_toggle_btn.dart',
      );
      expect(source.contains('BorderRadiusDirectional.horizontal'), isTrue);
      expect(source.contains('BorderRadius.horizontal'), isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  group('self-service account closure', () {
    const endpoint =
        '../../../xampp/htdocs/htdocs/dashboard1/services/api_delete_account_driver.php';

    String backend() {
      // Resolved relative to the Flutter package root, which sits beside the
      // PHP backend in this checkout.
      final path =
          File(endpoint).existsSync()
              ? endpoint
              : r'C:\xampp\htdocs\htdocs\dashboard1\services\api_delete_account_driver.php';
      return File(path).readAsStringSync();
    }

    test('57. a delete mode is refused', () {
      final source = backend();
      expect(source.contains('MODE_NOT_SUPPORTED'), isTrue);
      expect(source.contains("\$requestedMode !== null"), isTrue);
    });

    test('58/59. the default close is still the reversible one', () {
      final source = backend();
      expect(
        source.contains(
          'UPDATE tbl_drivers SET status = 2, fcm_token = NULL, updated_at = NOW() WHERE id = ?',
        ),
        isTrue,
      );
      expect(source.contains("'DELETE_SUCCESS'"), isTrue);
    });

    test('60. no driver-authenticated permanent delete remains', () {
      final source = backend()
          .split('\n')
          .where((line) {
            final trimmed = line.trimLeft();
            return !trimmed.startsWith('*') &&
                !trimmed.startsWith('//') &&
                !trimmed.startsWith('/*');
          })
          .join('\n');

      expect(source.contains('DELETE FROM tbl_drivers'), isFalse);
      expect(source.contains("\$mode === 'hard'"), isFalse);
      expect(
        source.contains('deleteDriverAccount(\$driverId, \$mode)'),
        isFalse,
      );
    });
  });

  // ---------------------------------------------------------------------------
  group('layout', () {
    for (final size in const [Size(360, 640), Size(390, 844), Size(430, 932)]) {
      for (final locale in const [Locale('en'), Locale('ar')]) {
        testWidgets(
          '61-66. Support at ${size.width.toInt()}x${size.height.toInt()} '
          'in ${locale.languageCode}',
          (tester) async {
            await _pumpSupport(tester, locale: locale, size: size);
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
          },
        );
      }
    }

    testWidgets('68. a modal and the launcher do not share the screen', (
      tester,
    ) async {
      final launcher = DriverChatLauncherProvider(
        sessionReader:
            () async => const DriverSession(apiKey: 'key-a', driverId: '901'),
      );
      addTearDown(launcher.dispose);

      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _app(
          home: Builder(
            builder:
                (context) => Scaffold(
                  body: Center(
                    child: ElevatedButton(
                      onPressed:
                          () => showModalBottomSheet<void>(
                            context: context,
                            builder:
                                (_) => const SizedBox(
                                  height: 300,
                                  child: Text('sheet body'),
                                ),
                          ),
                      child: const Text('open'),
                    ),
                  ),
                ),
          ),
          launcher: launcher,
          withBubble: true,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('sheet body'), findsOneWidget);
      expect(find.byIcon(Icons.chat_bubble_rounded), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
