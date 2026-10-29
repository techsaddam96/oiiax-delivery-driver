// Account deactivation and the shared loader helper.
//
// What these start from: the flow raised a global loader dialog and closed it
// with an unconditional `Navigator.pop`. It closed it once after the request
// and again from `catch` — and a non-JSON reply made `response.data['status']`
// throw right between the two, so the second close popped whatever real page
// was on top. Hub, or the Login page that had just been pushed.

import 'dart:convert';
import 'dart:io';

import 'package:blockatie/provider/login.dart';
import 'package:blockatie/provider/profile.dart';
import 'package:blockatie/services/auth_secure_store.dart';
import 'package:blockatie/services/auth_services.dart';
import 'package:blockatie/utils/app_utils.dart';
import 'package:blockatie/utils/localization.dart';
import 'package:blockatie/utils/nav.dart';
import 'package:blockatie/views/pages/welcome/driver_welcome_page.dart';
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
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<void> delete(String key) async => values.remove(key);
}

/// Answers the deactivation POST with whatever the test chooses.
///
/// The transport is replaced, not the method, so the real parsing and the real
/// error paths run.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter({this.body, this.status = 200, this.contentType});

  /// The reply. A Map is encoded as JSON; a String is sent verbatim, which is
  /// how a proxy or an error page answers. Null throws a transport failure.
  Object? body;
  int status;
  String? contentType;
  int calls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls++;
    final payload = body;
    if (payload == null) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'offline',
      );
    }
    return ResponseBody.fromString(
      payload is String ? payload : jsonEncode(payload),
      status,
      headers: {
        Headers.contentTypeHeader: [
          contentType ??
              (payload is String ? 'text/html' : Headers.jsonContentType),
        ],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

({ProfileProvider provider, _FakeAdapter adapter}) _build({
  Object? body = const {'status': 'success'},
  int status = 200,
  String? contentType,
}) {
  final adapter = _FakeAdapter(
    body: body,
    status: status,
    contentType: contentType,
  );
  final dio =
      Dio(BaseOptions(validateStatus: (_) => true))
        ..httpClientAdapter = adapter
        // Dio's default transformer decodes off-isolate, which a widget test's
        // fake clock cannot flush.
        ..transformer = SyncTransformer();
  return (
    provider: ProfileProvider(httpClient: dio, loadProfile: false),
    adapter: adapter,
  );
}

/// A real navigator with an identifiable page on top, so a stray pop is
/// visible as that page disappearing.
Widget _app(ProfileProvider provider, {Locale locale = const Locale('en')}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<ProfileProvider>.value(value: provider),
      // Success ends on Login, so the destination has to be buildable.
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
      home: const Scaffold(body: Center(child: Text('HUB'))),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    AuthService.configureForTesting(secureStore: _FakeSecureStore());
    await AuthService.saveApiKey('deactivate-token', '9');
    AppLocalizations.applyLocale(const Locale('en'));
    AppUtils.resetLoaderForTesting();
  });

  tearDown(AuthService.resetForTesting);

  // ---------------------------------------------------------------------------
  group('the route stack survives every path', () {
    testWidgets('5/6. a non-JSON reply leaves the page alone', (tester) async {
      // The exact shape that used to throw: indexing a String.
      final harness = _build(body: '<html><body>502 Bad Gateway</body></html>');
      addTearDown(harness.provider.dispose);
      final shown = <String>[];
      harness.provider.alertPresenter = (_, message) => shown.add(message);

      await tester.pumpWidget(_app(harness.provider));
      await tester.runAsync(harness.provider.deleteAccount);
      await tester.pumpAndSettle();

      expect(find.text('HUB'), findsOneWidget, reason: 'the page was popped');
      expect(shown, hasLength(1));
      expect(harness.provider.isDeactivating, isFalse);
    });

    testWidgets('a reply that is a bare list does not throw either', (
      tester,
    ) async {
      final harness = _build(body: [1, 2, 3]);
      addTearDown(harness.provider.dispose);
      harness.provider.alertPresenter = (_, __) {};

      await tester.pumpWidget(_app(harness.provider));
      await tester.runAsync(harness.provider.deleteAccount);
      await tester.pumpAndSettle();

      expect(find.text('HUB'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('11. a network failure keeps the stack intact', (tester) async {
      final harness = _build(body: null);
      addTearDown(harness.provider.dispose);
      final shown = <String>[];
      harness.provider.alertPresenter = (_, message) => shown.add(message);

      await tester.pumpWidget(_app(harness.provider));
      await tester.runAsync(harness.provider.deleteAccount);
      await tester.pumpAndSettle();

      expect(find.text('HUB'), findsOneWidget);
      expect(shown, hasLength(1));
    });

    testWidgets('10. a rejected deactivation stays on the page', (
      tester,
    ) async {
      final harness = _build(
        body: const {'status': 'error', 'code': 'DELETE_FAILED'},
      );
      addTearDown(harness.provider.dispose);
      final shown = <String>[];
      harness.provider.alertPresenter = (_, message) => shown.add(message);

      await tester.pumpWidget(_app(harness.provider));
      await tester.runAsync(harness.provider.deleteAccount);
      await tester.pumpAndSettle();

      expect(find.text('HUB'), findsOneWidget);
      expect(shown, hasLength(1));
    });

    testWidgets('13. a 403 from a disabled account is handled, not crashed', (
      tester,
    ) async {
      final harness = _build(
        body: const {'status': 'error', 'code': 'DRIVER_INACTIVE'},
        status: 403,
      );
      addTearDown(harness.provider.dispose);
      harness.provider.alertPresenter = (_, __) {};

      await tester.pumpWidget(_app(harness.provider));
      await tester.runAsync(harness.provider.deleteAccount);
      await tester.pumpAndSettle();

      expect(find.text('HUB'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  // ---------------------------------------------------------------------------
  group('loading state', () {
    testWidgets('1/3/4. it starts once and always ends', (tester) async {
      final harness = _build();
      addTearDown(harness.provider.dispose);
      await tester.pumpWidget(_app(harness.provider));

      expect(harness.provider.isDeactivating, isFalse);
      late Future<void> inFlight;
      await tester.runAsync(() async {
        inFlight = harness.provider.deleteAccount();
        expect(harness.provider.isDeactivating, isTrue);
        await inFlight;
      });
      await tester.pumpAndSettle();
      expect(harness.provider.isDeactivating, isFalse);
    });

    testWidgets('failure also ends it exactly once', (tester) async {
      final harness = _build(body: null);
      addTearDown(harness.provider.dispose);
      harness.provider.alertPresenter = (_, __) {};

      await tester.pumpWidget(_app(harness.provider));
      await tester.runAsync(harness.provider.deleteAccount);
      await tester.pumpAndSettle();

      expect(harness.provider.isDeactivating, isFalse);
    });

    testWidgets('2. a duplicate call sends one request', (tester) async {
      final harness = _build();
      addTearDown(harness.provider.dispose);
      await tester.pumpWidget(_app(harness.provider));

      await tester.runAsync(() async {
        // Both taps inside one real-async window: the second lands while the
        // first is still in flight, which is what the guard has to refuse.
        final first = harness.provider.deleteAccount();
        await harness.provider.deleteAccount();
        await first;
      });
      await tester.pumpAndSettle();

      expect(harness.adapter.calls, 1);
    });
  });

  // ---------------------------------------------------------------------------
  // The transition away from the authenticated shell needs a bounded settle.
  Future<void> settle(WidgetTester tester) async {
    // Long enough for the route transition to finish removing the old page.
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  group('success', () {
    testWidgets('8/9. it lands on Welcome and cannot go back', (tester) async {
      final harness = _build();
      addTearDown(harness.provider.dispose);

      await tester.pumpWidget(_app(harness.provider));
      await tester.runAsync(harness.provider.deleteAccount);
      await settle(tester);

      expect(find.byType(DriverWelcomePage), findsOneWidget);
      expect(find.text('HUB'), findsNothing);

      // Everything below was removed, so there is nothing to pop back to.
      final navigator = Nav.key.currentState!;
      expect(navigator.canPop(), isFalse);
    });

    testWidgets('the session is cleared before it navigates', (tester) async {
      final harness = _build();
      addTearDown(harness.provider.dispose);

      await tester.pumpWidget(_app(harness.provider));
      await tester.runAsync(harness.provider.deleteAccount);
      await settle(tester);

      String? key;
      await tester.runAsync(() async => key = await AuthService.getApiKey());
      expect(key, anyOf(isNull, isEmpty));
    });
  });

  // ---------------------------------------------------------------------------
  group('the message the driver reads', () {
    testWidgets('14/16. English copy carries no exception text', (
      tester,
    ) async {
      final harness = _build(body: null);
      addTearDown(harness.provider.dispose);
      final shown = <String>[];
      harness.provider.alertPresenter = (_, message) => shown.add(message);

      await tester.pumpWidget(_app(harness.provider));
      await tester.runAsync(harness.provider.deleteAccount);

      expect(shown.single, isNotEmpty);
      for (final leak in const [
        'DioException',
        'Exception',
        'TypeError',
        'NoSuchMethod',
        'html',
        '502',
        'null',
      ]) {
        expect(shown.single, isNot(contains(leak)), reason: leak);
      }
    });

    testWidgets('15. Arabic copy is Arabic', (tester) async {
      AppLocalizations.applyLocale(const Locale('ar'));
      final harness = _build(body: null);
      addTearDown(harness.provider.dispose);
      final shown = <String>[];
      harness.provider.alertPresenter = (_, message) => shown.add(message);

      await tester.pumpWidget(
        _app(harness.provider, locale: const Locale('ar')),
      );
      await tester.runAsync(harness.provider.deleteAccount);

      expect(shown.single, 'تعذر إيقاف الحساب. يرجى المحاولة لاحقًا.');
    });
  });

  // ---------------------------------------------------------------------------
  group('the flow no longer touches the shared loader', () {
    test('deleteAccount raises no loader dialog', () {
      final source =
          File(
            'lib/provider/profile.dart',
          ).readAsStringSync().split('Future<void> deleteAccount()')[1];

      expect(source.contains('showLoaderDialog'), isFalse);
      expect(source.contains('hideLoaderDialog'), isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // The helper itself, hardened so a future caller cannot repeat the defect.
  group('AppUtils loader', () {
    Future<void> pumpNavigator(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: Nav.key,
          home: const Scaffold(body: Center(child: Text('PAGE'))),
        ),
      );
    }

    testWidgets('17. hiding without a loader does nothing', (tester) async {
      await pumpNavigator(tester);

      AppUtils.hideLoaderDialog();
      await settle(tester);

      expect(find.text('PAGE'), findsOneWidget);
    });

    testWidgets('20. it closes the loader it opened', (tester) async {
      await pumpNavigator(tester);

      AppUtils.showLoaderDialog();
      await settle(tester);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(AppUtils.isLoaderVisible, isTrue);

      AppUtils.hideLoaderDialog();
      await settle(tester);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('PAGE'), findsOneWidget);
      expect(AppUtils.isLoaderVisible, isFalse);
    });

    testWidgets('18. hiding twice is harmless', (tester) async {
      await pumpNavigator(tester);

      AppUtils.showLoaderDialog();
      await settle(tester);
      AppUtils.hideLoaderDialog();
      await settle(tester);
      // The call that used to pop the page underneath.
      AppUtils.hideLoaderDialog();
      await settle(tester);

      expect(find.text('PAGE'), findsOneWidget);
    });

    testWidgets('19. an unrelated top route is never popped', (tester) async {
      await pumpNavigator(tester);

      AppUtils.showLoaderDialog();
      await settle(tester);
      AppUtils.hideLoaderDialog();
      await settle(tester);

      // A real page pushed after the loader closed.
      Nav.key.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Center(child: Text('DETAILS'))),
        ),
      );
      await settle(tester);
      expect(find.text('DETAILS'), findsOneWidget);

      AppUtils.hideLoaderDialog();
      await settle(tester);

      expect(find.text('DETAILS'), findsOneWidget, reason: 'it popped a page');
    });

    testWidgets('a second show does not stack a second loader', (tester) async {
      await pumpNavigator(tester);

      AppUtils.showLoaderDialog();
      AppUtils.showLoaderDialog();
      await settle(tester);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      AppUtils.hideLoaderDialog();
      await settle(tester);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });
}
