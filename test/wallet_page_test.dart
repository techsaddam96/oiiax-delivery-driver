// Tests for the Driver wallet, its balance summary and the financial cards it
// shares wording with.
//
// Two things are being protected here. The first is meaning: every amount on
// this screen comes from a different SQL base, and one of them —
// `total_balance_of_shipments_accrued` — is money the driver owes the company,
// not money they have earned. A label that gets that backwards is a financial
// defect, not a copy defect, so the labels are asserted as strictly as the
// numbers. The second is that a failed read must never be drawn as a zero: on
// a wallet, a confident `JOD 0.00` is worse than an error.

import 'dart:async';
import 'dart:io';

import 'package:blockatie/constants/fonts.dart';
import 'package:blockatie/models/statistics.dart';
import 'package:blockatie/provider/bottom_nav.dart';
import 'package:blockatie/provider/home.dart';
import 'package:blockatie/provider/localization.dart';
import 'package:blockatie/provider/notification.dart';
import 'package:blockatie/provider/requests_provider.dart';
import 'package:blockatie/provider/shipment.dart';
import 'package:blockatie/provider/withdrawal.dart';
import 'package:blockatie/services/auth_secure_store.dart';
import 'package:blockatie/services/auth_services.dart';
import 'package:blockatie/services/requests_service.dart';
import 'package:blockatie/services/user_session_state.dart';
import 'package:blockatie/utils/localization.dart';
import 'package:blockatie/utils/money.dart';
import 'package:blockatie/views/pages/wallet/wallet.dart';
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

/// The real provider with only the statistics call replaced.
class _StubHomeProvider extends HomeProvider {
  _StubHomeProvider({this.stats, this.failure, this.holdForever = false});

  DriverStatisticsData? stats;
  String? failure;
  bool holdForever;
  int fetches = 0;

  @override
  Future<void> getDriverStatistics(
    BuildContext context, {
    bool force = false,
  }) async {
    fetches++;
    if (holdForever) {
      isLoading = driverStats == null;
      notifyListeners();
      // Never completes: stands in for a read still in flight.
      return Completer<void>().future;
    }
    await Future<void>.delayed(Duration.zero);
    if (failure != null) {
      driverStats = DriverStatisticsData.empty();
      statisticsError = failure;
    } else {
      driverStats = stats;
      statisticsError = null;
    }
    isLoading = false;
    notifyListeners();
  }

  @override
  Future<void> getOrderStatus({bool force = false}) async {}
}

/// The real provider with the read replaced. The getters are overridden rather
/// than the private fields written, so the page sees exactly the surface the
/// real provider exposes.
class _StubRequestsProvider extends RequestsProvider {
  _StubRequestsProvider({
    List<WithdrawalRequest> rows = const [],
    this.failure,
    this.holdForever = false,
  }) : _rows = rows;

  List<WithdrawalRequest> _rows;
  WalletRequestsError? failure;
  bool holdForever;
  int fetches = 0;

  bool _loading = false;
  bool _loaded = false;
  WalletRequestsError? _err;

  @override
  List<WithdrawalRequest> get requests => _err == null ? _rows : const [];
  @override
  List<WithdrawalRequest> get paginatedRequests => requests;
  @override
  int get totalPages => requests.isEmpty ? 0 : 1;
  @override
  bool get isLoading => _loading;
  @override
  bool get hasLoaded => _loaded;
  @override
  WalletRequestsError? get error => _err;
  @override
  bool get hasError => _err != null;

  @override
  Future<void> fetchRequests({bool force = false, int? page}) async {
    fetches++;
    _loading = true;
    _err = null;
    notifyListeners();
    if (holdForever) return Completer<void>().future;
    await Future<void>.delayed(Duration.zero);
    _err = failure;
    _loaded = failure == null;
    _loading = false;
    notifyListeners();
  }

  void setRows(List<WithdrawalRequest> rows) {
    _rows = rows;
    notifyListeners();
  }

  // The real provider wipes its private fields; the stub has to wipe the ones
  // standing in for them or the history would survive the account change.
  @override
  void clearUserState() {
    super.clearUserState();
    _rows = const [];
    _err = null;
    _loaded = false;
    _loading = false;
  }
}

class _StubNotificationProvider extends NotificationProvider {
  @override
  Future<void> refreshUnreadCount({bool force = false}) async {}
}

// -----------------------------------------------------------------------------
// Fixtures
// -----------------------------------------------------------------------------

/// The server sends the same figure for `total_balance_due_to_the_driver` and
/// `driver_available_to_withdraw`. They are given different values here only so
/// an assertion can say which surface it is looking at.
DriverStatisticsData _stats({
  double due = 12.5,
  double accrued = 840,
  double shipCost = 900,
  int delivered = 7,
  double? available = 9,
  double? reserved = 2,
  double? paid = 1.5,
}) {
  return DriverStatisticsData(
    shipments: 11,
    shipmentsInProgress: 3,
    shipmentsDelivered: delivered,
    cancelledShipments: 1,
    totalUnaccrued: 0,
    totalAccrued: accrued,
    totalShipCost: shipCost,
    totalDriverDue: due,
    totalCancelledUnpaid: 0,
    availableToWithdraw: available,
    earningsReserved: reserved,
    earningsPaid: paid,
    earningsGross: available == null ? null : available + (paid ?? 0) + (reserved ?? 0),
  );
}

WithdrawalRequest _request({
  int id = 1,
  String amount = '25.00',
  int status = 0,
}) {
  return WithdrawalRequest.fromJson({
    'id': id,
    'driver_id': 501,
    'amount': amount,
    'status': status,
    'status_name_en': status == 0 ? 'Pending' : 'Approved',
    'status_name_ar': status == 0 ? 'قيد المراجعة' : 'مقبول',
    'withdrawal_method': 'cash',
    'requested_at': '2026-01-15 10:30:00',
  });
}

// -----------------------------------------------------------------------------
// Harness
// -----------------------------------------------------------------------------

class _Hosts {
  _Hosts({required this.home, required this.requests});

  final _StubHomeProvider home;
  final _StubRequestsProvider requests;
}

_Hosts _hosts({
  DriverStatisticsData? stats,
  String? statisticsFailure,
  bool statisticsHold = false,
  List<WithdrawalRequest> rows = const [],
  WalletRequestsError? requestsFailure,
  bool requestsHold = false,
}) {
  return _Hosts(
    home: _StubHomeProvider(
      stats: stats,
      failure: statisticsFailure,
      holdForever: statisticsHold,
    ),
    requests: _StubRequestsProvider(
      rows: rows,
      failure: requestsFailure,
      holdForever: requestsHold,
    ),
  );
}

Widget _app(_Hosts hosts, {required Locale locale}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<HomeProvider>.value(value: hosts.home),
      ChangeNotifierProvider<RequestsProvider>.value(value: hosts.requests),
      ChangeNotifierProvider<WithdrawalProvider>(
        create: (_) => WithdrawalProvider(),
      ),
      ChangeNotifierProvider<NotificationProvider>(
        create: (_) => _StubNotificationProvider(),
      ),
      ChangeNotifierProvider<ShipmentProvider>(create: (_) => ShipmentProvider()),
      ChangeNotifierProvider<BottomNavProvider>(
        create: (_) => BottomNavProvider(),
      ),
      ChangeNotifierProvider<LocaleProvider>(
        create: (_) => LocaleProvider(loadSaved: false),
      ),
    ],
    child: MaterialApp(
      theme: ThemeData(fontFamily: AppFonts.currentFontFamily),
      locale: locale,
      supportedLocales: const [Locale('en'), Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const WalletPage(),
    ),
  );
}

Future<void> _setSize(WidgetTester tester, Size size) async {
  tester.view.physicalSize = Size(size.width * 3, size.height * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pump(
  WidgetTester tester,
  _Hosts hosts, {
  Locale locale = const Locale('en'),
  Size size = const Size(390, 844),
}) async {
  await _setSize(tester, size);
  // A bare frame first: pumping the same widget types again would reuse the
  // page's State, whose one-shot post-frame load would then never run.
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(_app(hosts, locale: locale));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 10));
  await tester.pump();
}

/// Brings the lower half of the page into the viewport.
///
/// The wallet is one long `ListView`, so anything past the balance card and
/// the withdrawal form is never built until it is scrolled towards.
Future<void> _scrollDown(WidgetTester tester, [double dy = -700]) async {
  await tester.drag(find.byType(ListView), Offset(0, dy));
  await tester.pump();
}

/// The bottom padding the page reserves for its scrolling content.
double _listBottomPadding(WidgetTester tester) {
  final list = tester.widget<ListView>(find.byType(ListView));
  return (list.padding as EdgeInsets).bottom;
}

Widget _moneyProbe(double value, Locale locale) {
  return MaterialApp(
    locale: locale,
    supportedLocales: const [Locale('en'), Locale('ar')],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Builder(builder: (context) => Text(formatMoney(context, value))),
  );
}

/// U+2066 and U+2069, built rather than written: a direction-changing code
/// point in a source literal is exactly what the analyzer warns about, and the
/// warning is worth keeping for real strings.
final String _lri = String.fromCharCode(0x2066);
final String _pdi = String.fromCharCode(0x2069);

String _homeSource() =>
    File('lib/views/pages/home/home.dart').readAsStringSync();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    AuthService.configureForTesting(secureStore: _FakeSecureStore());
    AppLocalizations.applyLocale(const Locale('en'));
  });

  // ---------------------------------------------------------------------------
  // What each number actually means
  // ---------------------------------------------------------------------------
  group('financial semantics', () {
    testWidgets('the driver commission is labelled Earnings due in English', (
      tester,
    ) async {
      await _pump(tester, _hosts(stats: _stats(due: 12.5)));

      expect(find.text('Earnings due'), findsOneWidget);
      expect(find.text('JOD 12.50'), findsOneWidget);
      expect(find.text('Current Balance'), findsNothing);
    });

    testWidgets('the driver commission is labelled الأرباح المستحقة in Arabic', (
      tester,
    ) async {
      await _pump(
        tester,
        _hosts(stats: _stats(due: 12.5)),
        locale: const Locale('ar'),
      );

      expect(find.text('الأرباح المستحقة'), findsOneWidget);
      expect(find.text('12.50 دينار أردني'), findsOneWidget);
      expect(find.text('الرصيد الحالي'), findsNothing);
    });

    testWidgets('the settlement figure is never called earnings', (
      tester,
    ) async {
      await _pump(tester, _hosts(stats: _stats(accrued: 840)));

      // `total_balance_of_shipments_accrued` is COD less the driver's
      // commission: money owed to the company. Calling it earnings inverted
      // its meaning next to the real balance.
      expect(find.text('Total earnings'), findsNothing);

      await _pump(
        tester,
        _hosts(stats: _stats(accrued: 840)),
        locale: const Locale('ar'),
      );
      expect(find.text('إجمالي الأرباح'), findsNothing);
    });

    testWidgets('the settlement figure is labelled Cash to settle in English', (
      tester,
    ) async {
      await _pump(tester, _hosts(stats: _stats(accrued: 840)));

      expect(find.text('Cash to settle'), findsOneWidget);
      expect(find.text('JOD 840.00'), findsOneWidget);
    });

    testWidgets(
      'the settlement figure is labelled مبالغ مستحقة للشركة in Arabic',
      (tester) async {
        await _pump(
          tester,
          _hosts(stats: _stats(accrued: 840)),
          locale: const Locale('ar'),
        );

        expect(find.text('مبالغ مستحقة للشركة'), findsOneWidget);
        expect(find.text('840.00 دينار أردني'), findsOneWidget);
      },
    );

    testWidgets('the gross shipment total is described as COD', (tester) async {
      await _pump(tester, _hosts(stats: _stats(shipCost: 900)));

      expect(find.text('COD value'), findsOneWidget);
      expect(find.text('JOD 900.00'), findsOneWidget);
      expect(find.text('Shipments value'), findsNothing);
      expect(
        find.textContaining('total COD value for unsettled shipments'),
        findsOneWidget,
      );
    });

    testWidgets('the card explains why the totals do not reconcile', (
      tester,
    ) async {
      await _pump(tester, _hosts(stats: _stats()));

      expect(
        find.textContaining('Pending commission becomes withdrawable once'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Delivered counts delivered and completed'),
        findsOneWidget,
      );
    });

    testWidgets('the delivered count keeps its count meaning', (tester) async {
      await _pump(tester, _hosts(stats: _stats(delivered: 7)));

      expect(find.text('Delivered'), findsOneWidget);
      expect(find.text('7'), findsOneWidget);
    });

    test('Home labels the same field with the same words as the Wallet', () {
      final source = _homeSource();

      // Both screens render `total_balance_due_to_the_driver`; they used to
      // call it "Due", "Earnings due", "Current Balance" and "Balance".
      expect(source.contains("'Earnings due', 'الأرباح المستحقة'"), isTrue);
      expect(source.contains("'Due', 'مستحق'"), isFalse);
      expect(source.contains("'Shipment value', 'قيمة الشحنات'"), isFalse);
      expect(source.contains("'COD value', 'قيمة التحصيل'"), isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // Money formatting
  // ---------------------------------------------------------------------------
  group('money formatting', () {
    testWidgets('English puts the currency first', (tester) async {
      await tester.pumpWidget(_moneyProbe(12.5, const Locale('en')));
      expect(find.text('JOD 12.50'), findsOneWidget);
    });

    testWidgets('Arabic puts the amount first with the Arabic unit', (
      tester,
    ) async {
      await tester.pumpWidget(_moneyProbe(12.5, const Locale('ar')));
      expect(find.text('12.50 دينار أردني'), findsOneWidget);
      expect(find.textContaining('JOD'), findsNothing);
    });

    testWidgets('zero is a real amount in English', (tester) async {
      await tester.pumpWidget(_moneyProbe(0, const Locale('en')));
      expect(find.text('JOD 0.00'), findsOneWidget);
    });

    testWidgets('zero is a real amount in Arabic', (tester) async {
      await tester.pumpWidget(_moneyProbe(0, const Locale('ar')));
      expect(find.text('0.00 دينار أردني'), findsOneWidget);
    });

    test('trailing zeros are kept', () {
      // Home used to strip `.00`, so the same balance read `JOD 12` there and
      // `12.00 JOD` on the Wallet.
      expect(formatAmount(12), '12.00');
      expect(formatAmount(12.5), '12.50');
      expect(formatAmount(0), '0.00');
    });

    test('a negative zero is not rendered as a debit', () {
      expect(formatAmount(-0.0), '0.00');
    });

    test('a non-finite value cannot reach the screen as text', () {
      expect(formatAmount(double.nan), '0.00');
      expect(formatAmount(double.infinity), '0.00');
    });

    testWidgets('a negative amount keeps its sign in English', (tester) async {
      await tester.pumpWidget(_moneyProbe(-12.5, const Locale('en')));
      expect(find.textContaining('-12.50'), findsOneWidget);
    });

    testWidgets('a negative amount keeps its sign beside the digits in Arabic', (
      tester,
    ) async {
      await tester.pumpWidget(_moneyProbe(-12.5, const Locale('ar')));

      // The isolate is what stops the Arabic paragraph from moving the minus
      // to the far end of the number.
      expect(find.text('$_lri-12.50$_pdi دينار أردني'), findsOneWidget);
    });

    testWidgets('a large amount is not truncated at 360px', (tester) async {
      await _pump(
        tester,
        _hosts(stats: _stats(due: 123456.78)),
        size: const Size(360, 640),
      );

      expect(find.text('JOD 123456.78'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a large Arabic amount is not truncated at 360px', (
      tester,
    ) async {
      await _pump(
        tester,
        _hosts(stats: _stats(due: 123456.78)),
        locale: const Locale('ar'),
        size: const Size(360, 640),
      );

      expect(find.text('123456.78 دينار أردني'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the amount field carries a localized unit', (tester) async {
      await _pump(tester, _hosts(stats: _stats()));
      expect(find.text('JOD'), findsOneWidget);

      await _pump(
        tester,
        _hosts(stats: _stats()),
        locale: const Locale('ar'),
      );
      expect(find.text('دينار أردني'), findsOneWidget);
    });

    testWidgets('the amount field types left to right in Arabic', (
      tester,
    ) async {
      await _pump(
        tester,
        _hosts(stats: _stats()),
        locale: const Locale('ar'),
      );

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.textDirection, TextDirection.ltr);
    });
  });

  // ---------------------------------------------------------------------------
  // Pending withdrawals
  // ---------------------------------------------------------------------------
  group('pending withdrawals', () {
    testWidgets('a successful empty list is a real zero', (tester) async {
      await _pump(tester, _hosts(stats: _stats(), rows: const []));

      expect(find.text('Pending withdrawals'), findsOneWidget);
      expect(find.text('JOD 0.00'), findsOneWidget);
    });

    testWidgets('only requests awaiting a decision are counted', (tester) async {
      await _pump(
        tester,
        _hosts(
          stats: _stats(),
          rows: [
            _request(id: 1, amount: '25.00'),
            _request(id: 2, amount: '10.00'),
            _request(id: 3, amount: '99.00', status: 1),
          ],
        ),
      );

      expect(find.text('JOD 35.00'), findsOneWidget);
    });

    testWidgets('a failed read is unavailable, not zero', (tester) async {
      await _pump(
        tester,
        _hosts(stats: _stats(), requestsFailure: WalletRequestsError.network),
      );

      // The sum over an emptied list is zero, which on a wallet reads as an
      // authoritative "nothing pending".
      expect(find.text('Pending withdrawals'), findsOneWidget);
      expect(find.text('JOD 0.00'), findsNothing);
      expect(find.text('Unavailable'), findsOneWidget);
    });

    testWidgets('a failed read is unavailable in Arabic too', (tester) async {
      await _pump(
        tester,
        _hosts(stats: _stats(), requestsFailure: WalletRequestsError.server),
        locale: const Locale('ar'),
      );

      expect(find.text('طلبات سحب قيد الانتظار'), findsOneWidget);
      expect(find.text('0.00 دينار أردني'), findsNothing);
    });

    testWidgets('a read still in flight says so rather than showing zero', (
      tester,
    ) async {
      await _pump(tester, _hosts(stats: _stats(), requestsHold: true));

      expect(find.text('JOD 0.00'), findsNothing);
      expect(find.text('Loading...'), findsWidgets);
    });
  });

  // ---------------------------------------------------------------------------
  // Failure presentation
  // ---------------------------------------------------------------------------
  group('failure presentation', () {
    testWidgets('the failure is stated in English', (tester) async {
      await _pump(
        tester,
        _hosts(stats: _stats(), requestsFailure: WalletRequestsError.unknown),
      );
      await _scrollDown(tester);

      expect(
        find.text('Unable to load wallet data. Please try again.'),
        findsOneWidget,
      );
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('the failure is stated in Arabic', (tester) async {
      await _pump(
        tester,
        _hosts(stats: _stats(), requestsFailure: WalletRequestsError.unknown),
        locale: const Locale('ar'),
      );
      await _scrollDown(tester);

      expect(
        find.text('تعذر تحميل بيانات المحفظة. يرجى المحاولة مرة أخرى.'),
        findsOneWidget,
      );
      expect(find.text('حاول مرة أخرى'), findsOneWidget);
    });

    testWidgets('each failure kind has its own wording', (tester) async {
      await _pump(
        tester,
        _hosts(stats: _stats(), requestsFailure: WalletRequestsError.network),
      );
      await _scrollDown(tester);
      expect(
        find.text(
          'Unable to connect. Please check your connection and try again.',
        ),
        findsOneWidget,
      );

      await _pump(
        tester,
        _hosts(stats: _stats(), requestsFailure: WalletRequestsError.session),
      );
      await _scrollDown(tester);
      expect(find.text('Session expired. Please login again.'), findsOneWidget);

      await _pump(
        tester,
        _hosts(stats: _stats(), requestsFailure: WalletRequestsError.server),
      );
      await _scrollDown(tester);
      expect(
        find.text('Service is unavailable. Please try again later.'),
        findsOneWidget,
      );
    });

    testWidgets('no English sentence appears inside the Arabic failure card', (
      tester,
    ) async {
      await _pump(
        tester,
        _hosts(stats: _stats(), requestsFailure: WalletRequestsError.server),
        locale: const Locale('ar'),
      );
      await _scrollDown(tester);

      expect(
        find.text('الخدمة غير متاحة حاليًا. يرجى المحاولة لاحقًا.'),
        findsOneWidget,
      );
      expect(find.textContaining('Unable'), findsNothing);
      expect(find.textContaining('unavailable'), findsNothing);
      expect(find.textContaining('Database'), findsNothing);
      expect(find.textContaining('DB_'), findsNothing);
    });

    test('database and transport wording never leaves the provider', () {
      final provider = RequestsProvider();
      addTearDown(provider.dispose);

      // The service hands over a code; the sentence is written by the app. A
      // DB_ERROR must land on neutral service wording, never on the backend's
      // own "Database error." text.
      expect(provider.errorForCode('DB_ERROR'), WalletRequestsError.server);
      expect(provider.errorForCode('NETWORK_ERROR'), WalletRequestsError.network);
      expect(provider.errorForCode('AUTH_FAILED'), WalletRequestsError.session);
      expect(
        provider.errorForCode('API_KEY_REQUIRED'),
        WalletRequestsError.session,
      );
      expect(provider.errorForCode('SOMETHING_NEW'), WalletRequestsError.unknown);
      expect(provider.errorForCode(null), WalletRequestsError.unknown);
    });

    test('a missing session is classified without touching the network', () async {
      final provider = RequestsProvider();
      addTearDown(provider.dispose);

      await provider.fetchRequests();

      expect(provider.error, WalletRequestsError.session);
      expect(provider.requests, isEmpty);
      // An empty list after a failure is not a loaded empty list.
      expect(provider.hasLoaded, isFalse);
    });

    testWidgets('a statistics failure shows no fake zero', (tester) async {
      await _pump(
        tester,
        _hosts(statisticsFailure: 'Unable to load data.', rows: const []),
      );

      expect(find.text('Not available'), findsOneWidget);
      expect(find.text('Unavailable'), findsWidgets);
      expect(find.text('JOD 900.00'), findsNothing);
    });
  });

  // ---------------------------------------------------------------------------
  // Language and direction
  // ---------------------------------------------------------------------------
  group('language and direction', () {
    testWidgets('English lays the page out left to right', (tester) async {
      await _pump(tester, _hosts(stats: _stats()));

      expect(find.text('Wallet'), findsOneWidget);
      expect(
        Directionality.of(tester.element(find.byType(ListView))),
        TextDirection.ltr,
      );
    });

    testWidgets('Arabic lays the page out right to left', (tester) async {
      await _pump(
        tester,
        _hosts(stats: _stats()),
        locale: const Locale('ar'),
      );

      expect(find.text('المحفظة'), findsOneWidget);
      expect(
        Directionality.of(tester.element(find.byType(ListView))),
        TextDirection.rtl,
      );
    });

    testWidgets('no single-language literal survives the Arabic page', (
      tester,
    ) async {
      await _pump(
        tester,
        _hosts(stats: _stats(), rows: [_request()]),
        locale: const Locale('ar'),
      );

      for (final english in const [
        'Earnings due',
        'Cash to settle',
        'COD value',
        'Pending withdrawals',
        'Delivered',
        'Request Withdrawal',
        'Withdrawal Requests',
      ]) {
        expect(find.text(english), findsNothing, reason: english);
      }
    });

    testWidgets('an amount follows the locale it is rendered under', (
      tester,
    ) async {
      // The formatter reads `Localizations.localeOf`, which follows the widget
      // tree: it cannot disagree with the direction the page is laid out in
      // the way EasyLocalization's separate `context.locale` could.
      await tester.pumpWidget(_moneyProbe(12.5, const Locale('en')));
      expect(find.text('JOD 12.50'), findsOneWidget);

      await tester.pumpWidget(_moneyProbe(12.5, const Locale('ar')));
      await tester.pump();
      expect(find.text('12.50 دينار أردني'), findsOneWidget);
      expect(find.text('JOD 12.50'), findsNothing);
    });

    test('the Home financial cards read one locale source', () {
      final source = _homeSource();

      // The comment above `_copy` still names the source it moved away from,
      // so the call shape is what is asserted, not the words.
      expect(source.contains('context.locale.languageCode'), isFalse);
      expect(source.contains('isArabicLocale(context)'), isTrue);
      expect(source.contains("import 'package:easy_localization"), isFalse);
    });

    test('the Home financial cards use the shared formatter', () {
      final source = _homeSource();

      expect(source.contains('formatMoney(context, stats.totalDriverDue)'), isTrue);
      expect(source.contains('formatMoney(context, stats.totalShipCost)'), isTrue);
      // The local formatter that stripped `.00` is gone.
      expect(source.contains("endsWith('.00')"), isFalse);
      expect(source.contains(r"} JOD'"), isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // Refresh
  // ---------------------------------------------------------------------------
  group('refresh', () {
    testWidgets('a pull refreshes the statistics', (tester) async {
      final hosts = _hosts(stats: _stats());
      await _pump(tester, hosts);
      final before = hosts.home.fetches;

      await tester.fling(find.byType(ListView), const Offset(0, 320), 1000);
      await tester.pumpAndSettle();

      expect(hosts.home.fetches, greaterThan(before));
    });

    testWidgets('a pull refreshes the withdrawal requests', (tester) async {
      final hosts = _hosts(stats: _stats());
      await _pump(tester, hosts);
      final before = hosts.requests.fetches;

      await tester.fling(find.byType(ListView), const Offset(0, 320), 1000);
      await tester.pumpAndSettle();

      expect(hosts.requests.fetches, greaterThan(before));
    });

    testWidgets('a second pull is refused while one is running', (
      tester,
    ) async {
      final hosts = _hosts(stats: _stats(), statisticsHold: true);
      await _pump(tester, hosts);

      final indicator = tester.widget<RefreshIndicator>(
        find.byType(RefreshIndicator),
      );

      // The statistics read never completes, so the first refresh is still in
      // flight when the second arrives.
      unawaited(indicator.onRefresh());
      await tester.pump();
      final afterFirst = hosts.requests.fetches;

      await indicator.onRefresh();
      await tester.pump();

      expect(hosts.requests.fetches, afterFirst);

      // The first refresh's own read still has to drain before the tree goes.
      await tester.pump(const Duration(milliseconds: 10));
    });

    testWidgets('a statistics failure does not clear the request list', (
      tester,
    ) async {
      await _pump(
        tester,
        _hosts(
          statisticsFailure: 'Unable to load data.',
          rows: [_request(amount: '25.00')],
        ),
      );

      expect(find.text('Not available'), findsOneWidget);
      expect(find.text('JOD 25.00'), findsWidgets);
    });

    testWidgets('a requests failure does not clear the statistics', (
      tester,
    ) async {
      await _pump(
        tester,
        _hosts(
          stats: _stats(due: 12.5),
          requestsFailure: WalletRequestsError.network,
        ),
      );

      expect(find.text('JOD 12.50'), findsOneWidget);
      expect(find.text('Earnings due'), findsOneWidget);

      await _scrollDown(tester);
      expect(
        find.text(
          'Unable to connect. Please check your connection and try again.',
        ),
        findsOneWidget,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Session boundaries
  // ---------------------------------------------------------------------------
  group('session boundaries', () {
    testWidgets('the typed amount is cleared on an account switch', (
      tester,
    ) async {
      await _pump(tester, _hosts(stats: _stats()));

      await tester.enterText(find.byType(TextField), '75.00');
      await tester.pump();
      expect(find.text('75.00'), findsOneWidget);

      UserSessionState.reset(SessionResetReason.accountChanged);
      await tester.pump();

      // The page is kept alive by the bottom navigation, so nothing here is
      // disposed: Driver B would otherwise open the form on A's amount.
      expect(find.text('75.00'), findsNothing);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller?.text,
        isEmpty,
      );
    });

    testWidgets('the previous driver figures leave the screen', (tester) async {
      final hosts = _hosts(stats: _stats(due: 12.5), rows: [_request()]);
      await _pump(tester, hosts);
      expect(find.text('JOD 12.50'), findsOneWidget);

      UserSessionState.reset(SessionResetReason.accountChanged);
      await tester.pump();

      expect(find.text('JOD 12.50'), findsNothing);
      expect(find.text('JOD 25.00'), findsNothing);
    });

    test('withdrawal history is cleared and not replaced by an error', () {
      final provider = RequestsProvider();
      addTearDown(provider.dispose);

      UserSessionState.reset(SessionResetReason.logout);

      expect(provider.requests, isEmpty);
      expect(provider.error, isNull);
      expect(provider.hasLoaded, isFalse);
      expect(provider.currentPage, 1);
    });

    test('a reply that outlives its session is dropped', () async {
      final provider = RequestsProvider();
      addTearDown(provider.dispose);

      // Started under Driver A, lands after the switch.
      final inFlight = provider.fetchRequests();
      UserSessionState.reset(SessionResetReason.accountChanged);
      await inFlight;

      // Without the generation check this read's failure state would be
      // written into Driver B's freshly cleared provider.
      expect(provider.error, isNull);
      expect(provider.requests, isEmpty);
      expect(provider.isLoading, isFalse);
    });

    test('statistics that outlive their session are dropped', () async {
      final provider = HomeProvider();
      addTearDown(provider.dispose);

      final inFlight = provider.getDriverStatistics(_NullContext());
      UserSessionState.reset(SessionResetReason.accountChanged);
      await inFlight;

      expect(provider.driverStats, isNull);
      expect(provider.statisticsError, isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // Layout
  // ---------------------------------------------------------------------------
  group('layout', () {
    for (final size in const [
      Size(360, 640),
      Size(390, 844),
      Size(430, 932),
    ]) {
      for (final locale in const [Locale('en'), Locale('ar')]) {
        testWidgets(
          'renders at ${size.width.toInt()}x${size.height.toInt()} in '
          '${locale.languageCode}',
          (tester) async {
            await _pump(
              tester,
              _hosts(
                stats: _stats(due: 12345.67, accrued: 98765.43),
                rows: [_request(), _request(id: 2, amount: '10.00')],
              ),
              locale: locale,
              size: size,
            );

            expect(tester.takeException(), isNull);
            expect(
              find.text(
                locale.languageCode == 'ar'
                    ? 'الأرباح المستحقة'
                    : 'Earnings due',
              ),
              findsOneWidget,
            );
          },
        );
      }
    }

    testWidgets('the content clears the floating chat launcher', (tester) async {
      await _pump(tester, _hosts(stats: _stats(), rows: [_request()]));

      // 110 left the last request card and the pagination bar underneath it.
      expect(
        _listBottomPadding(tester),
        DriverChatBubble.reservedBottomSpace + 16,
      );
      expect(
        _listBottomPadding(tester),
        greaterThan(DriverChatBubble.reservedBottomSpace),
      );
    });

    testWidgets('a long Arabic label is not cut to one line', (tester) async {
      await _pump(
        tester,
        _hosts(stats: _stats()),
        locale: const Locale('ar'),
        size: const Size(360, 640),
      );

      final label = tester.widget<Text>(
        find.text('طلبات سحب قيد الانتظار'),
      );
      expect(label.maxLines, greaterThan(1));
      expect(tester.takeException(), isNull);
    });
  });
}

/// A context that is never used: `getDriverStatistics` takes one for historical
/// reasons and abandons the read before touching it.
class _NullContext extends StatelessElement {
  _NullContext() : super(const _NullWidget());
}

class _NullWidget extends StatelessWidget {
  const _NullWidget();

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
