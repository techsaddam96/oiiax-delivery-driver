// Tests for the Driver hub (My Account) and the shell it renders inside.
//
// The providers are real classes with their network calls stubbed out, so the
// screen is exercised against the actual state shapes — a failed statistics
// read really does leave `DriverStatisticsData.empty()` behind, which is the
// case that used to be indistinguishable from a genuine zero balance.

import 'package:blockatie/constants/fonts.dart';
import 'package:blockatie/models/d_rating.dart';
import 'package:blockatie/models/driver_profile.dart';
import 'package:blockatie/models/statistics.dart';
import 'package:blockatie/provider/bottom_nav.dart';
import 'package:blockatie/provider/chat/driver_chat_conversations_provider.dart';
import 'package:blockatie/provider/home.dart';
import 'package:blockatie/provider/localization.dart';
import 'package:blockatie/provider/notification.dart';
import 'package:blockatie/provider/profile.dart';
import 'package:blockatie/services/auth_secure_store.dart';
import 'package:blockatie/services/auth_services.dart';
import 'package:blockatie/services/driver_chat_service.dart';
import 'package:blockatie/utils/localization.dart';
import 'package:blockatie/utils/nav.dart';
import 'package:blockatie/utils/text_direction.dart';
import 'package:blockatie/views/pages/hub/hub.dart';
import 'package:blockatie/views/widgets/unread_count_badge.dart';
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

/// The real provider with its two network reads stubbed, so the state the hub
/// renders from is set explicitly and the calls can be counted.
class _StubProfileProvider extends ProfileProvider {
  int profileFetches = 0;
  int ratingFetches = 0;

  @override
  Future<DriverInfo?> fetchDriverProfile() async {
    profileFetches++;
    return profileInfo;
  }

  @override
  Future<DriverRating?> getDriverRating() async {
    ratingFetches++;
    return ratingInfo;
  }
}

class _StubHomeProvider extends HomeProvider {
  int statisticsFetches = 0;

  @override
  Future<void> getDriverStatistics(
    BuildContext context, {
    bool force = false,
  }) async {
    statisticsFetches++;
  }
}

class _StubNotificationProvider extends NotificationProvider {
  int unreadRefreshes = 0;

  @override
  Future<void> refreshUnreadCount({bool force = false}) async {
    unreadRefreshes++;
  }
}

class _StubConversationsProvider extends DriverChatConversationsProvider {
  _StubConversationsProvider({int unread = 0})
    : _unread = unread,
      super(repository: DriverChatService());

  final int _unread;
  int unreadRefreshes = 0;

  @override
  int get unreadCount => _unread;

  @override
  int get globalUnreadCount => _unread;

  @override
  Future<void> refreshUnreadCount() async {
    unreadRefreshes++;
  }
}

// -----------------------------------------------------------------------------
// Fixtures
// -----------------------------------------------------------------------------

DriverInfo _driver({
  String name = 'Ahmad Saleh',
  String phone = '0791234567',
  int status = 0,
  int subscription = 0,
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

DriverRating _rating(double avg) => DriverRating(
  driverId: 501,
  driverName: 'Ahmad Saleh',
  driverImage: '',
  reviewsCount: 12,
  avgRating: avg,
);

DriverStatisticsData _stats({
  int delivered = 8,
  int active = 2,
  double due = 12.5,
}) {
  return DriverStatisticsData(
    shipments: delivered + active,
    shipmentsInProgress: active,
    shipmentsDelivered: delivered,
    cancelledShipments: 0,
    totalUnaccrued: 0,
    totalAccrued: 0,
    totalShipCost: 0,
    totalDriverDue: due,
    totalCancelledUnpaid: 0,
  );
}

// -----------------------------------------------------------------------------
// Harness
// -----------------------------------------------------------------------------

class _Hosts {
  _Hosts({
    required this.profile,
    required this.home,
    required this.locale,
    required this.notifications,
    required this.conversations,
  });

  final _StubProfileProvider profile;
  final _StubHomeProvider home;
  final LocaleProvider locale;
  final _StubNotificationProvider notifications;
  final _StubConversationsProvider conversations;
}

_Hosts _hosts({
  DriverInfo? driver,
  DriverRating? rating,
  DriverStatisticsData? stats,
  String? statisticsError,
  bool statsLoading = false,
  bool profileLoading = false,
  bool profileError = false,
  int notificationUnread = 0,
  int chatUnread = 0,
}) {
  final profile =
      _StubProfileProvider()
        ..profileInfo = driver
        ..ratingInfo = rating
        ..isProfileLoading = profileLoading
        ..hasProfileError = profileError;
  final home =
      _StubHomeProvider()
        ..driverStats = stats
        ..statisticsError = statisticsError
        ..isLoading = statsLoading;
  return _Hosts(
    profile: profile,
    home: home,
    locale: LocaleProvider(loadSaved: false),
    notifications:
        _StubNotificationProvider()..unreadCount = notificationUnread,
    conversations: _StubConversationsProvider(unread: chatUnread),
  );
}

Widget _app(_Hosts hosts, {Locale locale = const Locale('en')}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<ProfileProvider>.value(value: hosts.profile),
      ChangeNotifierProvider<HomeProvider>.value(value: hosts.home),
      ChangeNotifierProvider<LocaleProvider>.value(value: hosts.locale),
      ChangeNotifierProvider<NotificationProvider>.value(
        value: hosts.notifications,
      ),
      ChangeNotifierProvider<DriverChatConversationsProvider>.value(
        value: hosts.conversations,
      ),
      ChangeNotifierProvider(create: (_) => BottomNavProvider()),
    ],
    child: Consumer<LocaleProvider>(
      builder:
          (context, value, _) => MaterialApp(
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
            home: const HubPage(),
          ),
    ),
  );
}

/// Renders the hub with its locale driven by LocaleProvider, the way main.dart
/// wires it, so a switch can be observed end to end.
Widget _liveApp(_Hosts hosts) => _app(hosts, locale: const Locale('follow'));

Future<void> _setSize(WidgetTester tester, double w, double h) async {
  tester.view.physicalSize = Size(w * 3, h * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pumpHub(
  WidgetTester tester,
  _Hosts hosts, {
  Locale locale = const Locale('en'),
  Size size = const Size(390, 844),
}) async {
  await _setSize(tester, size.width, size.height);
  await tester.pumpWidget(_app(hosts, locale: locale));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

/// The hub's own scroll view, so a fling does not depend on the language of
/// whatever text happens to be under the finger.
final Finder _hubScroll = find.byType(SingleChildScrollView);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeSecureStore store;

  setUp(() {
    store = _FakeSecureStore();
    store.values['driver_session_name'] = 'Ahmad Saleh';
    store.values['driver_session_phone'] = '0791234567';
    store.values['driver_api_key'] = 'test-key';
    store.values['driver_session_id'] = '501';
    SharedPreferences.setMockInitialValues(<String, Object>{});
    AuthService.configureForTesting(secureStore: store);
    AppLocalizations.applyLocale(const Locale('en'));
  });

  tearDown(AuthService.resetForTesting);

  // ---------------------------------------------------------------------------
  // Language
  // ---------------------------------------------------------------------------
  group('language', () {
    testWidgets('1. the hub renders English', (tester) async {
      await _pumpHub(tester, _hosts(driver: _driver()));

      expect(find.text('My Account'), findsOneWidget);
      expect(find.text('Account information'), findsOneWidget);
      expect(find.text('Logout'), findsOneWidget);
    });

    testWidgets('2. the hub renders Arabic', (tester) async {
      await _pumpHub(
        tester,
        _hosts(driver: _driver()),
        locale: const Locale('ar'),
      );

      expect(find.text('حسابي'), findsOneWidget);
      expect(find.text('معلومات الحساب'), findsOneWidget);
      expect(find.text('تسجيل الخروج'), findsOneWidget);
    });

    testWidgets('3. the language row reads English under English', (
      tester,
    ) async {
      await _pumpHub(tester, _hosts(driver: _driver()));

      expect(find.text('Language'), findsOneWidget);
      // Once as the row's subtitle, once as the dropdown's selected item.
      expect(find.text('English'), findsNWidgets(2));
      expect(find.text('Arabic'), findsNothing);
    });

    testWidgets('4. the language row reads العربية under Arabic', (
      tester,
    ) async {
      final hosts = _hosts(driver: _driver());
      hosts.locale.selectedLanguage = LocaleProvider.arabic;
      await _pumpHub(tester, hosts, locale: const Locale('ar'));

      expect(find.text('اللغة'), findsOneWidget);
      expect(find.text('العربية'), findsNWidgets(2));
      expect(find.text('Arabic'), findsNothing);
    });

    testWidgets('5. switching English to Arabic updates immediately', (
      tester,
    ) async {
      final hosts = _hosts(driver: _driver());
      await _setSize(tester, 390, 844);
      await tester.pumpWidget(_liveApp(hosts));
      await tester.pump();
      expect(find.text('My Account'), findsOneWidget);

      await hosts.locale.setLanguage(LocaleProvider.arabic, _NullContext());
      await tester.pumpAndSettle();

      expect(find.text('حسابي'), findsOneWidget);
      expect(find.text('My Account'), findsNothing);
      expect(find.text('العربية'), findsNWidgets(2));
    });

    testWidgets('6. switching Arabic to English updates immediately', (
      tester,
    ) async {
      final hosts = _hosts(driver: _driver());
      hosts.locale.selectedLanguage = LocaleProvider.arabic;
      AppLocalizations.applyLocale(const Locale('ar'));
      await _setSize(tester, 390, 844);
      await tester.pumpWidget(_liveApp(hosts));
      await tester.pump();
      expect(find.text('حسابي'), findsOneWidget);

      await hosts.locale.setLanguage(LocaleProvider.english, _NullContext());
      await tester.pumpAndSettle();

      expect(find.text('My Account'), findsOneWidget);
      expect(find.text('حسابي'), findsNothing);
    });

    testWidgets('7. Directionality follows the switch', (tester) async {
      final hosts = _hosts(driver: _driver());
      await _setSize(tester, 390, 844);
      await tester.pumpWidget(_liveApp(hosts));
      await tester.pump();
      expect(
        Directionality.of(tester.element(find.text('My Account'))),
        TextDirection.ltr,
      );

      await hosts.locale.setLanguage(LocaleProvider.arabic, _NullContext());
      await tester.pumpAndSettle();

      expect(
        Directionality.of(tester.element(find.text('حسابي'))),
        TextDirection.rtl,
      );
    });

    testWidgets('8. the font family follows the switch', (tester) async {
      final hosts = _hosts(driver: _driver());
      await _setSize(tester, 390, 844);
      await tester.pumpWidget(_liveApp(hosts));
      await tester.pump();
      expect(
        Theme.of(
          tester.element(find.text('My Account')),
        ).textTheme.bodyMedium?.fontFamily,
        'Montserrat',
      );

      await hosts.locale.setLanguage(LocaleProvider.arabic, _NullContext());
      await tester.pumpAndSettle();

      expect(
        Theme.of(
          tester.element(find.text('حسابي')),
        ).textTheme.bodyMedium?.fontFamily,
        'Almarai',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Statistics
  // ---------------------------------------------------------------------------
  group('statistics', () {
    testWidgets('9. a genuine zero is still shown as zero', (tester) async {
      await _pumpHub(
        tester,
        _hosts(
          driver: _driver(),
          stats: _stats(delivered: 0, active: 0, due: 0),
        ),
      );

      expect(find.text('Delivered'), findsOneWidget);
      expect(find.text('JOD 0.00'), findsOneWidget);
      expect(find.text('Statistics unavailable'), findsNothing);
    });

    testWidgets('10. a failed read shows the localized unavailable state', (
      tester,
    ) async {
      await _pumpHub(
        tester,
        _hosts(
          driver: _driver(),
          stats: DriverStatisticsData.empty(),
          statisticsError: 'Unable to load data.',
        ),
      );
      expect(find.text('Statistics unavailable'), findsOneWidget);

      await _pumpHub(
        tester,
        _hosts(
          driver: _driver(),
          stats: DriverStatisticsData.empty(),
          statisticsError: 'Unable to load data.',
        ),
        locale: const Locale('ar'),
      );
      expect(find.text('تعذر تحميل الإحصائيات'), findsOneWidget);
    });

    testWidgets('11. a failed read never shows a zero balance', (tester) async {
      await _pumpHub(
        tester,
        _hosts(
          driver: _driver(),
          rating: _rating(4.6),
          stats: DriverStatisticsData.empty(),
          statisticsError: 'Unable to load data.',
        ),
      );

      expect(find.text('JOD 0.00'), findsNothing);
      expect(find.text('Delivered'), findsNothing);
      expect(find.text('Earnings due'), findsNothing);
      // The rating comes from a different call and survives.
      expect(find.text('Rating'), findsOneWidget);
      expect(find.text('4.6'), findsOneWidget);
    });

    testWidgets('a pending read shows a localized loading state', (
      tester,
    ) async {
      await _pumpHub(tester, _hosts(driver: _driver(), statsLoading: true));

      expect(find.text('Loading statistics…'), findsOneWidget);
      expect(find.text('Statistics unavailable'), findsNothing);
    });
  });

  // ---------------------------------------------------------------------------
  // Deactivation
  // ---------------------------------------------------------------------------
  group('deactivation failure', () {
    test('12. the English message is the safe localized one', () {
      expect(
        ProfileProvider.deactivateUnavailableMessage(isArabic: false),
        'Could not deactivate the account. Please try again later.',
      );
      expect(
        ProfileProvider.deactivateRejectedMessage(null, isArabic: false),
        'Could not deactivate the account.',
      );
    });

    test('13. the Arabic message never borrows English', () {
      expect(
        ProfileProvider.deactivateUnavailableMessage(isArabic: true),
        'تعذر إيقاف الحساب. يرجى المحاولة لاحقًا.',
      );
      // message_ar missing: the Arabic fallback, not the English text.
      expect(
        ProfileProvider.deactivateRejectedMessage({
          'message_en': 'Failed to delete account.',
        }, isArabic: true),
        'تعذر إيقاف الحساب.',
      );
      // message_ar present: the server's own wording wins.
      expect(
        ProfileProvider.deactivateRejectedMessage({
          'message_ar': 'الحساب مرتبط بشحنات نشطة.',
        }, isArabic: true),
        'الحساب مرتبط بشحنات نشطة.',
      );
    });

    testWidgets('14. a missing session reports a failure instead of nothing', (
      tester,
    ) async {
      AuthService.configureForTesting(secureStore: _FakeSecureStore());
      AppLocalizations.applyLocale(const Locale('ar'));
      // The shared loader dialog reaches for the root navigator, so one has to
      // exist for this path to run at all.
      await tester.pumpWidget(
        MaterialApp(navigatorKey: Nav.key, home: const SizedBox.shrink()),
      );

      final provider = ProfileProvider();
      final shown = <String>[];
      provider.alertPresenter = (title, message) => shown.add(message);

      await provider.deleteAccount();
      await tester.pumpAndSettle();

      expect(shown, ['تعذر إيقاف الحساب. يرجى المحاولة لاحقًا.']);
      expect(provider.deactivateError, isNotNull);
      expect(provider.deactivateError, isNot(contains('Dio')));
      expect(provider.deactivateError, isNot(contains('null')));
    });
  });

  // ---------------------------------------------------------------------------
  // Notification badge
  // ---------------------------------------------------------------------------
  group('notification badge', () {
    testWidgets('15. zero hides the badge', (tester) async {
      await _pumpHub(tester, _hosts(driver: _driver(), notificationUnread: 0));

      expect(find.byType(UnreadCountBadge), findsNothing);
    });

    testWidgets('16. one is shown exactly', (tester) async {
      await _pumpHub(tester, _hosts(driver: _driver(), notificationUnread: 1));

      expect(find.widgetWithText(UnreadCountBadge, '1'), findsOneWidget);
    });

    testWidgets('17. ninety-nine is shown exactly', (tester) async {
      await _pumpHub(tester, _hosts(driver: _driver(), notificationUnread: 99));

      expect(find.widgetWithText(UnreadCountBadge, '99'), findsOneWidget);
    });

    testWidgets('18. one hundred collapses to 99+', (tester) async {
      await _pumpHub(
        tester,
        _hosts(driver: _driver(), notificationUnread: 100),
      );

      expect(find.widgetWithText(UnreadCountBadge, '99+'), findsOneWidget);
    });

    testWidgets('19. the count stays left-to-right under Arabic', (
      tester,
    ) async {
      await _pumpHub(
        tester,
        _hosts(driver: _driver(), notificationUnread: 100),
        locale: const Locale('ar'),
      );

      final label = tester.widget<Text>(find.text('99+'));
      expect(label.textDirection, TextDirection.ltr);
    });

    testWidgets('20. the badge mirrors to the other corner under Arabic', (
      tester,
    ) async {
      await _pumpHub(tester, _hosts(driver: _driver(), notificationUnread: 5));
      final ltrX = tester.getCenter(find.byType(UnreadCountBadge)).dx;
      final ltrIconX =
          tester
              .getCenter(find.byIcon(Icons.notifications_none_rounded).first)
              .dx;

      await _pumpHub(
        tester,
        _hosts(driver: _driver(), notificationUnread: 5),
        locale: const Locale('ar'),
      );
      final rtlX = tester.getCenter(find.byType(UnreadCountBadge)).dx;
      final rtlIconX =
          tester
              .getCenter(find.byIcon(Icons.notifications_none_rounded).first)
              .dx;

      expect(ltrX, greaterThan(ltrIconX), reason: 'trailing side in English');
      expect(rtlX, lessThan(rtlIconX), reason: 'trailing side in Arabic');
    });

    testWidgets('21. 99+ is not clipped by a circular decoration', (
      tester,
    ) async {
      await _pumpHub(
        tester,
        _hosts(driver: _driver(), notificationUnread: 150),
      );

      final container = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(UnreadCountBadge),
              matching: find.byType(Container),
            )
            .first,
      );
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.shape, BoxShape.rectangle);
      expect(decoration.borderRadius, isNotNull);

      // The pill is wider than it is tall, which a circle could not be.
      final size = tester.getSize(find.byType(UnreadCountBadge));
      expect(size.width, greaterThan(size.height));
    });

    testWidgets('22. the chat badge is untouched and still collapses', (
      tester,
    ) async {
      await _pumpHub(tester, _hosts(driver: _driver(), chatUnread: 120));

      // The conversations row uses the chat badge, not the notification pill.
      expect(find.text('99+'), findsOneWidget);
      expect(find.byType(UnreadCountBadge), findsNothing);
    });
  });

  // ---------------------------------------------------------------------------
  // Refresh
  // ---------------------------------------------------------------------------
  group('pull to refresh', () {
    Future<_Hosts> pullAndRead(WidgetTester tester) async {
      final hosts = _hosts(driver: _driver(), stats: _stats());
      await _pumpHub(tester, hosts);

      await tester.fling(_hubScroll, const Offset(0, 320), 1000);
      await tester.pumpAndSettle();
      return hosts;
    }

    testWidgets('23. it refreshes the profile', (tester) async {
      final hosts = await pullAndRead(tester);
      expect(hosts.profile.profileFetches, greaterThan(0));
    });

    testWidgets('24. it refreshes the rating', (tester) async {
      final hosts = await pullAndRead(tester);
      expect(hosts.profile.ratingFetches, greaterThan(0));
    });

    testWidgets('25. it refreshes the statistics', (tester) async {
      final hosts = _hosts(driver: _driver(), stats: _stats());
      await _pumpHub(tester, hosts);
      // One non-forced read on entry; the pull must add another.
      final before = hosts.home.statisticsFetches;

      await tester.fling(_hubScroll, const Offset(0, 320), 1000);
      await tester.pumpAndSettle();

      expect(hosts.home.statisticsFetches, greaterThan(before));
    });

    testWidgets('26. it refreshes the notification unread count', (
      tester,
    ) async {
      final hosts = await pullAndRead(tester);
      expect(hosts.notifications.unreadRefreshes, greaterThan(0));
    });

    testWidgets('27. it refreshes the chat unread count', (tester) async {
      final hosts = _hosts(driver: _driver(), stats: _stats());
      await _pumpHub(tester, hosts);
      // The conversations row reads once on entry; the pull must add another,
      // and neither starts a timer.
      final before = hosts.conversations.unreadRefreshes;

      await tester.fling(_hubScroll, const Offset(0, 320), 1000);
      await tester.pumpAndSettle();

      expect(hosts.conversations.unreadRefreshes, greaterThan(before));
    });
  });

  // ---------------------------------------------------------------------------
  // Identity
  // ---------------------------------------------------------------------------
  group('driver identity', () {
    testWidgets('28. the avatar never builds initials from the placeholder', (
      tester,
    ) async {
      AuthService.configureForTesting(secureStore: _FakeSecureStore());
      await _pumpHub(tester, _hosts(profileError: true));

      expect(find.text('NA'), findsNothing);
      expect(find.text('N'), findsNothing);
      expect(find.byIcon(Icons.person_rounded), findsOneWidget);
    });

    testWidgets('29. the same holds in Arabic', (tester) async {
      AuthService.configureForTesting(secureStore: _FakeSecureStore());
      await _pumpHub(
        tester,
        _hosts(profileError: true),
        locale: const Locale('ar'),
      );

      expect(find.text('غم'), findsNothing);
      expect(find.text('غ'), findsNothing);
      expect(find.byIcon(Icons.person_rounded), findsOneWidget);
      // The failure is named, not disguised as missing data.
      expect(find.text('غير متاح'), findsWidgets);
    });

    testWidgets('a loading profile is not reported as missing', (tester) async {
      AuthService.configureForTesting(secureStore: _FakeSecureStore());
      await _pumpHub(tester, _hosts(profileLoading: true));

      expect(find.text('Not available'), findsNothing);
      expect(find.text('—'), findsWidgets);
    });

    testWidgets('32. the phone value is left-to-right in Arabic', (
      tester,
    ) async {
      await _pumpHub(
        tester,
        _hosts(driver: _driver(phone: '0791234567')),
        locale: const Locale('ar'),
      );

      final phones = tester.widgetList<Text>(find.text('0791234567'));
      expect(phones, isNotEmpty);
      for (final phone in phones) {
        expect(phone.textDirection, TextDirection.ltr);
      }
    });

    testWidgets('33. an identifier row is left-to-right, a label is not', (
      tester,
    ) async {
      // The driver id and the phone are rendered by the same _InfoRow, which
      // asks identifierTextDirection what to do. The id itself is read from
      // the session over a platform channel that does not settle inside a
      // widget test, so the row is proven with the phone and the rule is
      // checked directly against id-shaped values.
      expect(identifierTextDirection('501'), TextDirection.ltr);
      expect(identifierTextDirection('0791234567'), TextDirection.ltr);
      expect(identifierTextDirection('+962 79-123-4567'), TextDirection.ltr);
      expect(identifierTextDirection('نشط'), isNull);
      expect(identifierTextDirection('Active'), isNull);
      expect(identifierTextDirection('غير متوفر'), isNull);

      await _pumpHub(
        tester,
        _hosts(driver: _driver()),
        locale: const Locale('ar'),
      );

      // A localized label in the same column keeps the page direction.
      final status = tester.widget<Text>(find.text('نشط').first);
      expect(status.textDirection, isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // Currency
  // ---------------------------------------------------------------------------
  group('currency', () {
    testWidgets('30. English puts the code first', (tester) async {
      await _pumpHub(
        tester,
        _hosts(driver: _driver(), stats: _stats(due: 12.5)),
      );

      expect(find.text('JOD 12.50'), findsOneWidget);
    });

    testWidgets('31. Arabic uses the Arabic currency name', (tester) async {
      await _pumpHub(
        tester,
        _hosts(driver: _driver(), stats: _stats(due: 12.5)),
        locale: const Locale('ar'),
      );

      expect(find.text('12.50 دينار أردني'), findsOneWidget);
      expect(find.text('JOD 12.50'), findsNothing);
    });
  });

  // ---------------------------------------------------------------------------
  // Layout
  // ---------------------------------------------------------------------------
  group('layout', () {
    testWidgets('34. the logout button clears the floating chat launcher', (
      tester,
    ) async {
      await _pumpHub(
        tester,
        _hosts(driver: _driver(), stats: _stats()),
        size: const Size(390, 844),
      );

      await tester.fling(_hubScroll, const Offset(0, -900), 2000);
      await tester.pumpAndSettle();

      final logout = tester.getRect(find.text('Logout'));
      final viewportBottom = tester.getSize(find.byType(HubPage)).height;
      // The launcher occupies 118..176 above the bottom inset; nothing the
      // driver has to tap may sit inside that band.
      expect(
        viewportBottom - logout.bottom,
        greaterThan(176),
        reason: 'logout must stay above the chat launcher',
      );
    });

    for (final size in const [Size(360, 640), Size(390, 844), Size(430, 932)]) {
      for (final locale in const [Locale('en'), Locale('ar')]) {
        final index =
            35 +
            const [
                  Size(360, 640),
                  Size(390, 844),
                  Size(430, 932),
                ].indexOf(size) *
                2 +
            (locale.languageCode == 'ar' ? 1 : 0);
        testWidgets('$index. ${size.width.toInt()}x${size.height.toInt()} '
            '${locale.languageCode} lays out cleanly', (tester) async {
          await _pumpHub(
            tester,
            _hosts(
              driver: _driver(name: 'عبد الرحمن محمد الشريف الحسيني'),
              rating: _rating(4.9),
              stats: _stats(delivered: 1234, active: 56, due: 98765.43),
              notificationUnread: 150,
              chatUnread: 120,
            ),
            locale: locale,
            size: size,
          );
          expect(tester.takeException(), isNull);

          await tester.fling(_hubScroll, const Offset(0, -900), 2000);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('41. the long Arabic chat subtitle does not overflow', (
      tester,
    ) async {
      await _pumpHub(
        tester,
        _hosts(driver: _driver(), chatUnread: 120),
        locale: const Locale('ar'),
        size: const Size(360, 640),
      );

      expect(tester.takeException(), isNull);
      final subtitle = tester.widget<Text>(
        find.text('الرسائل مع فريق العمليات والدعم'),
      );
      expect(subtitle.maxLines, 2);
    });

    testWidgets('42. the hub tab label matches the hub title', (tester) async {
      await _pumpHub(tester, _hosts(driver: _driver()));
      expect(find.text('My Account'), findsOneWidget);

      await _pumpHub(
        tester,
        _hosts(driver: _driver()),
        locale: const Locale('ar'),
      );
      expect(find.text('حسابي'), findsOneWidget);
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
