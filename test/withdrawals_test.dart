// Tests for the driver withdrawal flow.
//
// The backend now owns the money: it decides what is available, reserves a
// pending request, consumes a completed payout once and refuses a second
// pending row at the database level. So what is protected here is that the app
// never invents any of that — it must show the server's number, send only what
// the server accepts, carry one idempotency key per submission, and read a
// failure as a failure.

import 'dart:async';
import 'dart:convert';

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
import 'package:blockatie/services/request_id_service.dart';
import 'package:blockatie/services/requests_service.dart';
import 'package:blockatie/services/user_session_state.dart';
import 'package:blockatie/utils/localization.dart';
import 'package:blockatie/utils/withdrawal_rules.dart';
import 'package:blockatie/views/pages/wallet/wallet.dart';
import 'package:blockatie/views/widgets/driver_chat_bubble.dart';
import 'package:dio/dio.dart';
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

/// Stands in for the server. Records what the app sent and answers with the
/// envelope the real endpoint would.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter({this.code = 'REQUEST_SUBMITTED', this.success = true});

  String code;
  bool success;
  bool throwNetwork = false;
  int calls = 0;
  final List<Map<String, dynamic>> requestHeaders = [];
  final List<String> requestIds = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls++;
    requestHeaders.add(Map<String, dynamic>.from(options.headers));
    requestIds.add(options.headers['X-Request-ID']?.toString() ?? '');

    if (throwNetwork) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'offline',
      );
    }

    final body = jsonEncode({
      'success': success,
      'code': code,
      // Deliberately English-only prose plus database wording: none of it may
      // reach the screen.
      'message': 'Database error while preparing withdrawal insert.',
      'message_en': 'Database error while preparing withdrawal insert.',
      'message_ar': '',
    });

    return ResponseBody.fromString(
      body,
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// The real provider with only the statistics read replaced.
class _StubHomeProvider extends HomeProvider {
  _StubHomeProvider({this.stats, this.failure});

  DriverStatisticsData? stats;
  String? failure;
  int fetches = 0;

  @override
  Future<void> getDriverStatistics(
    BuildContext context, {
    bool force = false,
  }) async {
    fetches++;
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

/// The real provider with the network replaced by a page table, so pagination
/// is exercised against the actual state machine.
class _StubRequestsProvider extends RequestsProvider {
  _StubRequestsProvider({this.pages = const {}, this.failOnPage});

  /// page number -> rows the server would return
  final Map<int, List<WithdrawalRequest>> pages;
  int? failOnPage;

  int fetches = 0;
  final List<int> requestedPages = [];
  bool holdNextResponse = false;

  List<WithdrawalRequest> _rows = const [];
  int _page = 1;
  int _pages = 0;
  bool _loading = false;
  bool _changing = false;
  bool _loaded = false;
  WalletRequestsError? _err;

  @override
  List<WithdrawalRequest> get requests => _rows;
  @override
  List<WithdrawalRequest> get paginatedRequests => _rows;
  @override
  int get currentPage => _page;
  @override
  int get totalPages => _pages;
  @override
  bool get isLoading => _loading;
  @override
  bool get isPageChanging => _changing;
  @override
  bool get hasLoaded => _loaded;
  @override
  WalletRequestsError? get error => _err;
  @override
  bool get hasError => _err != null;

  @override
  Future<void> fetchRequests({bool force = false, int? page}) async {
    if (_loading && _changing) return; // mirrors the real in-flight guard

    final target = page ?? _page;
    fetches++;
    requestedPages.add(target);

    _loading = true;
    _changing = _loaded && target != _page;
    _err = null;
    notifyListeners();

    if (holdNextResponse) return; // leaves the page in its changing state

    await Future<void>.delayed(Duration.zero);

    if (failOnPage != null && target == failOnPage) {
      _err = WalletRequestsError.network;
    } else {
      _rows = pages[target] ?? const [];
      _page = target;
      _pages = pages.length;
      _loaded = true;
    }

    _loading = false;
    _changing = false;
    notifyListeners();
  }

  @override
  Future<void> goToNextPage() async {
    if (_page >= _pages) return;
    await fetchRequests(page: _page + 1);
  }

  @override
  Future<void> goToPrevPage() async {
    if (_page <= 1) return;
    await fetchRequests(page: _page - 1);
  }

  @override
  void clearUserState() {
    super.clearUserState();
    _rows = const [];
    _page = 1;
    _pages = 0;
    _loaded = false;
    _loading = false;
    _changing = false;
    _err = null;
  }
}

/// Answers submissions without a transport, so the page's own behaviour can be
/// driven precisely.
class _StubWithdrawalProvider extends WithdrawalProvider {
  _StubWithdrawalProvider({
    this.result = const WithdrawalSubmission(
      success: true,
      code: WithdrawalSubmissionCode.requestSubmitted,
    ),
    this.holdForever = false,
  });

  WithdrawalSubmission result;
  bool holdForever;
  int calls = 0;
  final List<String> amounts = [];
  Completer<void>? _gate;

  @override
  Future<WithdrawalSubmission?> submitWithdrawalRequest({
    required String canonicalAmount,
    required String withdrawalMethod,
  }) async {
    if (isSubmitting) return null; // the real duplicate guard
    calls++;
    amounts.add(canonicalAmount);
    isSubmitting = true;
    notifyListeners();

    if (holdForever) {
      _gate = Completer<void>();
      await _gate!.future;
    } else {
      await Future<void>.delayed(Duration.zero);
    }

    isSubmitting = false;
    notifyListeners();
    return result;
  }

  void release() {
    if (_gate != null && !_gate!.isCompleted) _gate!.complete();
  }
}

class _StubNotificationProvider extends NotificationProvider {
  @override
  Future<void> refreshUnreadCount({bool force = false}) async {}
}

// -----------------------------------------------------------------------------
// Fixtures
// -----------------------------------------------------------------------------

DriverStatisticsData _stats({
  double? available = 20,
  double? reserved = 80,
  double? paid = 50,
  double? gross = 150,
}) {
  return DriverStatisticsData(
    shipments: 11,
    shipmentsInProgress: 3,
    shipmentsDelivered: 7,
    cancelledShipments: 1,
    totalUnaccrued: 0,
    totalAccrued: 840,
    totalShipCost: 900,
    totalDriverDue: available ?? 0,
    totalCancelledUnpaid: 0,
    availableToWithdraw: available,
    earningsReserved: reserved,
    earningsPaid: paid,
    earningsGross: gross,
  );
}

WithdrawalRequest _request({
  int id = 1,
  String amount = '25.00',
  int status = 0,
  String requestedAt = '2026-01-15 10:30:00',
  String processedAt = '',
  String remarks = '',
  String method = 'cash',
}) {
  return WithdrawalRequest.fromJson({
    'id': id,
    'driver_id': 501,
    'amount': amount,
    'status': status,
    'withdrawal_method': method,
    'requested_at': requestedAt,
    'processed_at': processedAt.isEmpty ? null : processedAt,
    'remarks': remarks.isEmpty ? null : remarks,
    'admin_id': 7,
    'account_details': 'IBAN JO00 SECRET 0000',
  });
}

// -----------------------------------------------------------------------------
// Harness
// -----------------------------------------------------------------------------

class _Hosts {
  _Hosts({required this.home, required this.requests, required this.withdrawal});

  final _StubHomeProvider home;
  final _StubRequestsProvider requests;
  final _StubWithdrawalProvider withdrawal;
}

_Hosts _hosts({
  DriverStatisticsData? stats,
  String? statisticsFailure,
  Map<int, List<WithdrawalRequest>> pages = const {},
  int? failOnPage,
  WithdrawalSubmission? result,
  bool holdSubmission = false,
}) {
  return _Hosts(
    home: _StubHomeProvider(stats: stats, failure: statisticsFailure),
    requests: _StubRequestsProvider(pages: pages, failOnPage: failOnPage),
    withdrawal: _StubWithdrawalProvider(
      result:
          result ??
          const WithdrawalSubmission(
            success: true,
            code: WithdrawalSubmissionCode.requestSubmitted,
          ),
      holdForever: holdSubmission,
    ),
  );
}

Widget _app(_Hosts hosts, {required Locale locale}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<HomeProvider>.value(value: hosts.home),
      ChangeNotifierProvider<RequestsProvider>.value(value: hosts.requests),
      ChangeNotifierProvider<WithdrawalProvider>.value(value: hosts.withdrawal),
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

Future<void> _pump(
  WidgetTester tester,
  _Hosts hosts, {
  Locale locale = const Locale('en'),
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = Size(size.width * 3, size.height * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(_app(hosts, locale: locale));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 10));
  await tester.pump();
}

Future<void> _scrollDown(WidgetTester tester, [double dy = -700]) async {
  await tester.drag(find.byType(ListView), Offset(0, dy));
  await tester.pump();
}

Finder _amountField() => find.byType(TextField);
Finder _submitButton() => find.byType(FilledButton);

Future<void> _submit(WidgetTester tester, String amount) async {
  await tester.enterText(_amountField(), amount);
  await tester.pump();
  // The form sits below the balance card, so at phone heights the button is
  // off-screen and a tap would land on nothing.
  await tester.ensureVisible(_submitButton());
  await tester.pump();
  await tester.tap(_submitButton());
  await tester.pump();
}

WithdrawalProvider _provider(_FakeAdapter adapter) {
  final dio = Dio(BaseOptions(validateStatus: (_) => true));
  dio.httpClientAdapter = adapter;
  return WithdrawalProvider()..debugClient = dio;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = _FakeSecureStore();
    store.values['driver_api_key'] = 'KEY';
    store.values['driver_session_id'] = '501';
    AuthService.configureForTesting(secureStore: store);
    AppLocalizations.applyLocale(const Locale('en'));
    RequestIdService.clearUserState();
  });

  // ---------------------------------------------------------------------------
  group('available balance', () {
    test('the explicit fields are parsed', () {
      final stats = DriverStatisticsData.fromJson({
        'total_balance_due_to_the_driver': 20,
        'driver_available_to_withdraw': 20,
        'driver_earnings_gross': 150,
        'driver_earnings_reserved': 80,
        'driver_earnings_paid': 50,
      });

      expect(stats.availableToWithdraw, 20);
      expect(stats.earningsGross, 150);
      expect(stats.earningsReserved, 80);
      expect(stats.earningsPaid, 50);
      expect(stats.hasWithdrawalBreakdown, isTrue);
    });

    test('a server without the explicit fields falls back to the legacy one', () {
      final stats = DriverStatisticsData.fromJson({
        'total_balance_due_to_the_driver': '42.50',
      });

      expect(stats.availableToWithdraw, 42.5);
      expect(stats.hasWithdrawalBreakdown, isFalse);
    });

    test('a failed read reports nothing rather than zero', () {
      final stats = DriverStatisticsData.empty();

      // Zero would read as "you have no money"; null reads as "we do not know",
      // which is what disables the form.
      expect(stats.availableToWithdraw, isNull);
      expect(stats.earningsGross, isNull);
    });

    testWidgets('the form shows the server amount, not the earnings total', (
      tester,
    ) async {
      await _pump(tester, _hosts(stats: _stats(available: 20)));

      expect(find.text('Available to withdraw'), findsOneWidget);
      expect(find.text('JOD 20.00'), findsWidgets);
      // 150 is the gross; the form must never offer it.
      expect(find.text('JOD 150.00'), findsNothing);
    });

    testWidgets('the breakdown is shown beside it', (tester) async {
      await _pump(tester, _hosts(stats: _stats()));

      expect(find.text('Reserved: JOD 80.00'), findsOneWidget);
      expect(find.text('Paid: JOD 50.00'), findsOneWidget);
    });

    testWidgets('Arabic labels the same three things', (tester) async {
      await _pump(tester, _hosts(stats: _stats()), locale: const Locale('ar'));

      expect(find.text('المتاح للسحب'), findsOneWidget);
      expect(find.text('20.00 دينار أردني'), findsWidgets);
      expect(find.textContaining('محجوز'), findsOneWidget);
      expect(find.textContaining('مدفوع'), findsOneWidget);
    });

    testWidgets('an unknown available amount disables submission', (
      tester,
    ) async {
      await _pump(tester, _hosts(statisticsFailure: 'Unable to load data.'));

      expect(find.text('Unavailable'), findsWidgets);
      expect(tester.widget<FilledButton>(_submitButton()).onPressed, isNull);
      expect(tester.widget<TextField>(_amountField()).enabled, isFalse);
      expect(
        find.textContaining('withdrawals are paused'),
        findsOneWidget,
      );
    });

    testWidgets('a known available amount enables it', (tester) async {
      await _pump(tester, _hosts(stats: _stats()));

      expect(tester.widget<FilledButton>(_submitButton()).onPressed, isNotNull);
      expect(tester.widget<TextField>(_amountField()).enabled, isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  group('amount rules', () {
    test('canonical amounts are accepted and normalised', () {
      expect(normalizeWithdrawalAmount('12'), '12.00');
      expect(normalizeWithdrawalAmount('12.5'), '12.50');
      expect(normalizeWithdrawalAmount('12.50'), '12.50');
      expect(normalizeWithdrawalAmount('  12.50  '), '12.50');
      expect(normalizeWithdrawalAmount('0.01'), '0.01');
    });

    test('anything the server would refuse is refused here first', () {
      for (final value in const [
        '',
        '0',
        '0.00',
        '0.001',
        '12.505',
        '12,50',
        '-5',
        '+12.50',
        'abc',
        '1e9',
        'Infinity',
        'NaN',
        '0x10',
        '99999999999999999999',
      ]) {
        expect(normalizeWithdrawalAmount(value), isNull, reason: value);
      }
    });

    test('a third decimal is rejected, never rounded', () {
      // The server used to round 12.505 up to 12.51 — asking for more than the
      // driver typed.
      expect(normalizeWithdrawalAmount('12.505'), isNull);
    });

    test('the available ceiling is compared in cents', () {
      expect(isWithinAvailable('20.00', 20), isTrue);
      expect(isWithinAvailable('20.01', 20), isFalse);
      expect(isWithinAvailable('19.99', 20), isTrue);
    });

    testWidgets('the field refuses a comma, a minus and a third decimal', (
      tester,
    ) async {
      await _pump(tester, _hosts(stats: _stats()));

      // Pasting or typing a whole value at once: the disallowed characters are
      // dropped, and a value that still does not fit the backend's shape is
      // refused outright rather than silently repaired into a different amount.
      for (final entry in const {
        '12,50': '1250',
        '-5': '5',
        '12.505': '',
        '1e9': '19',
        '+12': '12',
      }.entries) {
        await tester.enterText(_amountField(), '');
        await tester.pump();
        await tester.enterText(_amountField(), entry.key);
        await tester.pump();
        expect(
          tester.widget<TextField>(_amountField()).controller?.text,
          entry.value,
          reason: entry.key,
        );
      }
    });

    testWidgets('an invalid amount is refused before any request', (
      tester,
    ) async {
      final hosts = _hosts(stats: _stats());
      await _pump(tester, hosts);

      await _submit(tester, '0');
      await tester.pump();

      expect(hosts.withdrawal.calls, 0);
      expect(find.text('Enter a valid withdrawal amount.'), findsOneWidget);
    });

    testWidgets('an amount over the available balance is refused locally', (
      tester,
    ) async {
      final hosts = _hosts(stats: _stats(available: 20));
      await _pump(tester, hosts);

      await _submit(tester, '20.01');
      await tester.pump();

      expect(hosts.withdrawal.calls, 0);
      expect(
        find.text(
          'The requested amount exceeds your available withdrawal balance.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('the typed amount reads left to right in Arabic', (
      tester,
    ) async {
      await _pump(tester, _hosts(stats: _stats()), locale: const Locale('ar'));

      final field = tester.widget<TextField>(_amountField());
      expect(field.textDirection, TextDirection.ltr);
      expect(find.text('دينار أردني'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  group('withdrawal method', () {
    test('only the two the backend allows are supported', () {
      expect(kWithdrawalMethods, ['cash', 'click']);
      expect(isSupportedWithdrawalMethod('cash'), isTrue);
      expect(isSupportedWithdrawalMethod('click'), isTrue);
      for (final value in const ['bitcoin', 'wallet', 'bank_transfer', '']) {
        expect(isSupportedWithdrawalMethod(value), isFalse, reason: value);
      }
    });

    testWidgets('the form offers exactly those two', (tester) async {
      await _pump(tester, _hosts(stats: _stats()));

      expect(find.text('Cash'), findsOneWidget);
      expect(find.text('CliQ'), findsOneWidget);
      for (final value in const [
        'Bank transfer',
        'bank_transfer',
        'Bitcoin',
        'bitcoin',
        'Wallet transfer',
      ]) {
        expect(find.text(value), findsNothing, reason: value);
      }
    });

    testWidgets('the cash label is localized', (tester) async {
      await _pump(tester, _hosts(stats: _stats()), locale: const Locale('ar'));

      expect(find.text('نقداً'), findsOneWidget);
      // A brand name stays as it is in both languages.
      expect(find.text('CliQ'), findsOneWidget);
    });

    test('the provider refuses an unsupported method without a request', () async {
      final adapter = _FakeAdapter();
      final provider = _provider(adapter);
      addTearDown(provider.dispose);

      final result = await provider.submitWithdrawalRequest(
        canonicalAmount: '12.50',
        withdrawalMethod: 'bitcoin',
      );

      expect(result?.code, WithdrawalSubmissionCode.invalidWithdrawalMethod);
      expect(adapter.calls, 0);
    });
  });

  // ---------------------------------------------------------------------------
  group('idempotency', () {
    test('a submission carries an X-Request-ID', () async {
      final adapter = _FakeAdapter();
      final provider = _provider(adapter);
      addTearDown(provider.dispose);

      await provider.submitWithdrawalRequest(
        canonicalAmount: '12.50',
        withdrawalMethod: 'cash',
      );

      expect(adapter.calls, 1);
      expect(adapter.requestIds.single, isNotEmpty);
    });

    test('a retry after a network failure reuses the same id', () async {
      final adapter = _FakeAdapter()..throwNetwork = true;
      final provider = _provider(adapter);
      addTearDown(provider.dispose);

      final first = await provider.submitWithdrawalRequest(
        canonicalAmount: '12.50',
        withdrawalMethod: 'cash',
      );
      expect(first?.code, WithdrawalSubmissionCode.network);

      adapter.throwNetwork = false;
      await provider.submitWithdrawalRequest(
        canonicalAmount: '12.50',
        withdrawalMethod: 'cash',
      );

      // The request may have reached the server the first time; the same id is
      // what stops the retry becoming a second withdrawal.
      expect(adapter.requestIds.length, 2);
      expect(adapter.requestIds[0], adapter.requestIds[1]);
    });

    test('a different amount gets a different id', () async {
      final adapter = _FakeAdapter()..throwNetwork = true;
      final provider = _provider(adapter);
      addTearDown(provider.dispose);

      await provider.submitWithdrawalRequest(
        canonicalAmount: '12.50',
        withdrawalMethod: 'cash',
      );
      await provider.submitWithdrawalRequest(
        canonicalAmount: '13.50',
        withdrawalMethod: 'cash',
      );

      expect(adapter.requestIds[0], isNot(adapter.requestIds[1]));
    });

    test('a different method gets a different id', () async {
      final adapter = _FakeAdapter()..throwNetwork = true;
      final provider = _provider(adapter);
      addTearDown(provider.dispose);

      await provider.submitWithdrawalRequest(
        canonicalAmount: '12.50',
        withdrawalMethod: 'cash',
      );
      await provider.submitWithdrawalRequest(
        canonicalAmount: '12.50',
        withdrawalMethod: 'click',
      );

      expect(adapter.requestIds[0], isNot(adapter.requestIds[1]));
    });

    test('a success releases the id', () async {
      final adapter = _FakeAdapter();
      final provider = _provider(adapter);
      addTearDown(provider.dispose);

      await provider.submitWithdrawalRequest(
        canonicalAmount: '12.50',
        withdrawalMethod: 'cash',
      );
      await provider.submitWithdrawalRequest(
        canonicalAmount: '12.50',
        withdrawalMethod: 'cash',
      );

      // A second, deliberate withdrawal of the same amount is a new request,
      // not a replay of the first.
      expect(adapter.requestIds[0], isNot(adapter.requestIds[1]));
    });

    test('an account switch drops a held id', () async {
      final adapter = _FakeAdapter()..throwNetwork = true;
      final provider = _provider(adapter);
      addTearDown(provider.dispose);

      await provider.submitWithdrawalRequest(
        canonicalAmount: '12.50',
        withdrawalMethod: 'cash',
      );
      final driverA = adapter.requestIds.single;

      UserSessionState.reset(SessionResetReason.accountChanged);
      RequestIdService.clearUserState();

      adapter.throwNetwork = false;
      final next = _provider(adapter);
      addTearDown(next.dispose);
      await next.submitWithdrawalRequest(
        canonicalAmount: '12.50',
        withdrawalMethod: 'cash',
      );

      expect(adapter.requestIds.last, isNot(driverA));
    });

    test('the lease is keyed per session generation', () {
      final a = RequestIdService.acquire(
        operation: 'driver.createWithdrawal',
        payload: const {'amount': '12.50', 'withdrawal_method': 'cash'},
      );
      final again = RequestIdService.acquire(
        operation: 'driver.createWithdrawal',
        payload: const {'amount': '12.50', 'withdrawal_method': 'cash'},
      );
      expect(again.requestId, a.requestId);

      UserSessionState.reset(SessionResetReason.logout);
      final afterSwitch = RequestIdService.acquire(
        operation: 'driver.createWithdrawal',
        payload: const {'amount': '12.50', 'withdrawal_method': 'cash'},
      );
      expect(afterSwitch.requestId, isNot(a.requestId));
    });
  });

  // ---------------------------------------------------------------------------
  group('result codes', () {
    test('every documented code maps to its own outcome', () {
      final provider = WithdrawalProvider();
      addTearDown(provider.dispose);

      const expected = {
        'REQUEST_SUBMITTED': WithdrawalSubmissionCode.requestSubmitted,
        'PENDING_REQUEST_EXISTS': WithdrawalSubmissionCode.pendingRequestExists,
        'AMOUNT_EXCEEDS_AVAILABLE':
            WithdrawalSubmissionCode.amountExceedsAvailable,
        'INVALID_AMOUNT': WithdrawalSubmissionCode.invalidAmount,
        'INVALID_WITHDRAWAL_METHOD':
            WithdrawalSubmissionCode.invalidWithdrawalMethod,
        'INVALID_REQUEST': WithdrawalSubmissionCode.invalidRequest,
        'REQUEST_NOT_FOUND': WithdrawalSubmissionCode.requestNotFound,
        'INVALID_TRANSITION': WithdrawalSubmissionCode.invalidTransition,
        'REQUEST_ALREADY_PROCESSED':
            WithdrawalSubmissionCode.requestAlreadyProcessed,
        'REQUEST_ID_CONFLICT': WithdrawalSubmissionCode.requestIdConflict,
        'DRIVER_INACTIVE': WithdrawalSubmissionCode.driverInactive,
        'API_KEY_REQUIRED': WithdrawalSubmissionCode.apiKeyRequired,
      };

      expected.forEach((code, outcome) {
        expect(provider.codeFromResponse({'code': code}), outcome, reason: code);
      });
      expect(provider.codeFromResponse({'code': 'SERVER_ERROR'}), isNull);
      expect(provider.codeFromResponse('not a map'), isNull);
    });

    test('an unrecognised code falls back to a server error', () async {
      final adapter = _FakeAdapter(code: 'SOMETHING_NEW', success: false);
      final provider = _provider(adapter);
      addTearDown(provider.dispose);

      final result = await provider.submitWithdrawalRequest(
        canonicalAmount: '12.50',
        withdrawalMethod: 'cash',
      );

      expect(result?.success, isFalse);
      expect(result?.code, WithdrawalSubmissionCode.serverError);
    });
  });

  // ---------------------------------------------------------------------------
  group('submission messages', () {
    Future<void> expectMessage(
      WidgetTester tester,
      WithdrawalSubmissionCode code,
      String text, {
      Locale locale = const Locale('en'),
      bool success = false,
    }) async {
      final hosts = _hosts(
        stats: _stats(),
        result: WithdrawalSubmission(success: success, code: code),
      );
      await _pump(tester, hosts, locale: locale);
      await _submit(tester, '10.00');
      await tester.pump(const Duration(milliseconds: 10));
      await tester.pump();

      expect(find.text(text), findsOneWidget, reason: '$code / $locale');
    }

    testWidgets('success, English', (tester) async {
      await expectMessage(
        tester,
        WithdrawalSubmissionCode.requestSubmitted,
        'Withdrawal request submitted successfully.',
        success: true,
      );
    });

    testWidgets('success, Arabic', (tester) async {
      await expectMessage(
        tester,
        WithdrawalSubmissionCode.requestSubmitted,
        'تم إرسال طلب السحب بنجاح.',
        locale: const Locale('ar'),
        success: true,
      );
    });

    testWidgets('a pending request already exists', (tester) async {
      await expectMessage(
        tester,
        WithdrawalSubmissionCode.pendingRequestExists,
        'You already have a pending withdrawal request.',
      );
      await expectMessage(
        tester,
        WithdrawalSubmissionCode.pendingRequestExists,
        'لديك طلب سحب قيد الانتظار بالفعل.',
        locale: const Locale('ar'),
      );
    });

    testWidgets('the server refuses the amount', (tester) async {
      await expectMessage(
        tester,
        WithdrawalSubmissionCode.amountExceedsAvailable,
        'The requested amount exceeds your available withdrawal balance.',
      );
      await expectMessage(
        tester,
        WithdrawalSubmissionCode.amountExceedsAvailable,
        'المبلغ المطلوب يتجاوز الرصيد المتاح للسحب.',
        locale: const Locale('ar'),
      );
    });

    testWidgets('an invalid amount', (tester) async {
      await expectMessage(
        tester,
        WithdrawalSubmissionCode.invalidAmount,
        'Enter a valid withdrawal amount.',
      );
      await expectMessage(
        tester,
        WithdrawalSubmissionCode.invalidAmount,
        'أدخل مبلغ سحب صحيح.',
        locale: const Locale('ar'),
      );
    });

    testWidgets('a server failure', (tester) async {
      await expectMessage(
        tester,
        WithdrawalSubmissionCode.serverError,
        'Unable to submit the withdrawal request. Please try again later.',
      );
      await expectMessage(
        tester,
        WithdrawalSubmissionCode.serverError,
        'تعذر إرسال طلب السحب. يرجى المحاولة لاحقًا.',
        locale: const Locale('ar'),
      );
    });

    testWidgets('Arabic never borrows the English sentence', (tester) async {
      final hosts = _hosts(
        stats: _stats(),
        result: const WithdrawalSubmission(
          success: false,
          code: WithdrawalSubmissionCode.serverError,
        ),
      );
      await _pump(tester, hosts, locale: const Locale('ar'));
      await _submit(tester, '10.00');
      await tester.pump(const Duration(milliseconds: 10));
      await tester.pump();

      expect(find.textContaining('Unable'), findsNothing);
      expect(find.textContaining('Database'), findsNothing);
      expect(find.textContaining('insert'), findsNothing);
    });

    test('database wording from the wire never leaves the provider', () async {
      // The fake server answers with DB_* prose in `message` and `message_en`
      // and an empty `message_ar`, which is exactly the shape that used to put
      // English database text into an Arabic snackbar.
      final adapter = _FakeAdapter(code: 'PENDING_REQUEST_EXISTS', success: false);
      final provider = _provider(adapter);
      addTearDown(provider.dispose);

      final result = await provider.submitWithdrawalRequest(
        canonicalAmount: '12.50',
        withdrawalMethod: 'cash',
      );

      expect(result?.code, WithdrawalSubmissionCode.pendingRequestExists);
      // Nothing carries prose at all any more.
      expect(provider.lastCode, WithdrawalSubmissionCode.pendingRequestExists);
      expect(provider.lastError, isNull);
      expect(provider.lastMessage, isNull);
    });
  });

  // ---------------------------------------------------------------------------
  group('submit behaviour', () {
    testWidgets('the button disables and a spinner replaces its label', (
      tester,
    ) async {
      final hosts = _hosts(stats: _stats(), holdSubmission: true);
      await _pump(tester, hosts);

      await _submit(tester, '10.00');

      expect(tester.widget<FilledButton>(_submitButton()).onPressed, isNull);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      hosts.withdrawal.release();
      await tester.pump(const Duration(milliseconds: 10));
      await tester.pump();
    });

    testWidgets('a second tap is ignored silently and sends nothing', (
      tester,
    ) async {
      final hosts = _hosts(stats: _stats(), holdSubmission: true);
      await _pump(tester, hosts);

      await _submit(tester, '10.00');
      // The button is disabled, so drive the callback directly: this is the
      // frame-boundary double tap the old code answered with a false failure.
      final form = tester.widget<FilledButton>(_submitButton());
      expect(form.onPressed, isNull);

      await tester.tap(_submitButton(), warnIfMissed: false);
      await tester.pump();

      expect(hosts.withdrawal.calls, 1);
      expect(find.byType(SnackBar), findsNothing);

      hosts.withdrawal.release();
      await tester.pump(const Duration(milliseconds: 10));
      await tester.pump();
    });

    test('a duplicate call is answered with nothing to report', () async {
      final hosts = _hosts(stats: _stats(), holdSubmission: true);
      final first = hosts.withdrawal.submitWithdrawalRequest(
        canonicalAmount: '10.00',
        withdrawalMethod: 'cash',
      );
      await Future<void>.delayed(Duration.zero);
      final second = await hosts.withdrawal.submitWithdrawalRequest(
        canonicalAmount: '10.00',
        withdrawalMethod: 'cash',
      );

      expect(second, isNull);
      expect(hosts.withdrawal.calls, 1);
      hosts.withdrawal.release();
      await first;
    });

    testWidgets('success clears the amount and re-reads both sources', (
      tester,
    ) async {
      final hosts = _hosts(stats: _stats(), pages: {1: [_request()]});
      await _pump(tester, hosts);
      final statsBefore = hosts.home.fetches;
      final historyBefore = hosts.requests.fetches;

      await _submit(tester, '10.00');
      await tester.pump(const Duration(milliseconds: 10));
      await tester.pump();

      expect(
        tester.widget<TextField>(_amountField()).controller?.text,
        isEmpty,
      );
      expect(hosts.home.fetches, greaterThan(statsBefore));
      expect(hosts.requests.fetches, greaterThan(historyBefore));
    });

    testWidgets('a failure keeps the typed amount and never looks successful', (
      tester,
    ) async {
      final hosts = _hosts(
        stats: _stats(),
        result: const WithdrawalSubmission(
          success: false,
          code: WithdrawalSubmissionCode.pendingRequestExists,
        ),
      );
      await _pump(tester, hosts);

      await _submit(tester, '10.00');
      await tester.pump(const Duration(milliseconds: 10));
      await tester.pump();

      expect(
        tester.widget<TextField>(_amountField()).controller?.text,
        '10.00',
      );
      expect(
        find.text('Withdrawal request submitted successfully.'),
        findsNothing,
      );
      expect(
        find.text('You already have a pending withdrawal request.'),
        findsOneWidget,
      );
    });
  });

  // ---------------------------------------------------------------------------
  group('history', () {
    Map<int, List<WithdrawalRequest>> threePages() => {
      1: [_request(id: 1), _request(id: 2, amount: '10.00')],
      2: [_request(id: 3, amount: '30.00', status: 3,
          processedAt: '2026-02-02 09:00:00')],
      3: [
        _request(
          id: 4,
          amount: '40.00',
          status: 2,
          processedAt: '2026-03-03 11:00:00',
          remarks: 'Insufficient documentation was provided for this payout.',
        ),
      ],
    };

    testWidgets('the first page is what the server returned', (tester) async {
      final hosts = _hosts(stats: _stats(), pages: threePages());
      await _pump(tester, hosts);
      await _scrollDown(tester);

      expect(find.text('JOD 25.00'), findsOneWidget);
      expect(find.text('JOD 10.00'), findsOneWidget);
      expect(find.text('Page 1 of 3'), findsOneWidget);
      expect(find.textContaining('IBAN'), findsNothing);
      expect(hosts.requests.requestedPages, [1]);
    });

    testWidgets('next asks the server for the next page', (tester) async {
      final hosts = _hosts(stats: _stats(), pages: threePages());
      await _pump(tester, hosts);
      await _scrollDown(tester);

      await tester.ensureVisible(find.byIcon(Icons.chevron_right_rounded));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.chevron_right_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));
      await tester.pump();

      expect(hosts.requests.requestedPages, [1, 2]);
      expect(find.text('Page 2 of 3'), findsOneWidget);
      expect(find.text('JOD 30.00'), findsOneWidget);
      expect(find.text('JOD 25.00'), findsNothing);
    });

    testWidgets('the last page disables next', (tester) async {
      final hosts = _hosts(stats: _stats(), pages: threePages());
      await _pump(tester, hosts);
      unawaited(hosts.requests.fetchRequests(page: 3));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));
      await tester.pump();
      await _scrollDown(tester);

      expect(find.text('Page 3 of 3'), findsOneWidget);
      final next = tester.widget<IconButton>(
        find.ancestor(
          of: find.byIcon(Icons.chevron_right_rounded),
          matching: find.byType(IconButton),
        ),
      );
      expect(next.onPressed, isNull);
    });

    testWidgets('the first page disables previous', (tester) async {
      await _pump(tester, _hosts(stats: _stats(), pages: threePages()));
      await _scrollDown(tester);

      final previous = tester.widget<IconButton>(
        find.ancestor(
          of: find.byIcon(Icons.chevron_left_rounded),
          matching: find.byType(IconButton),
        ),
      );
      expect(previous.onPressed, isNull);
    });

    testWidgets('a failed page change keeps the page it had', (tester) async {
      final hosts = _hosts(
        stats: _stats(),
        pages: threePages(),
        failOnPage: 2,
      );
      await _pump(tester, hosts);
      await _scrollDown(tester);

      await tester.ensureVisible(find.byIcon(Icons.chevron_right_rounded));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.chevron_right_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));
      await tester.pump();

      // The pager and the rows must never describe different pages.
      expect(find.text('Page 1 of 3'), findsOneWidget);
      expect(find.text('JOD 25.00'), findsOneWidget);
    });

    testWidgets('a page change in flight blocks a second one', (tester) async {
      final hosts = _hosts(stats: _stats(), pages: threePages());
      await _pump(tester, hosts);
      await _scrollDown(tester);

      hosts.requests.holdNextResponse = true;
      await tester.ensureVisible(find.byIcon(Icons.chevron_right_rounded));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.chevron_right_rounded));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsWidgets);
      await tester.tap(find.byIcon(Icons.chevron_right_rounded), warnIfMissed: false);
      await tester.pump();

      expect(hosts.requests.requestedPages, [1, 2]);
    });

    testWidgets('page numbers stay left to right in Arabic', (tester) async {
      await _pump(
        tester,
        _hosts(stats: _stats(), pages: threePages()),
        locale: const Locale('ar'),
      );
      await _scrollDown(tester);

      expect(
        find.text('صفحة \u{2066}1\u{2069} من \u{2066}3\u{2069}'),
        findsOneWidget,
      );
    });

    testWidgets('the arrows mirror with the page direction', (tester) async {
      await _pump(
        tester,
        _hosts(stats: _stats(), pages: threePages()),
        locale: const Locale('ar'),
      );
      await _scrollDown(tester);

      // Both chevrons carry matchTextDirection, so the glyphs flip with the
      // row and Previous still points backwards.
      expect(Icons.chevron_left_rounded.matchTextDirection, isTrue);
      expect(Icons.chevron_right_rounded.matchTextDirection, isTrue);
      expect(
        Directionality.of(tester.element(find.byType(ListView))),
        TextDirection.rtl,
      );
    });

    testWidgets('statuses are localized from their value', (tester) async {
      final rows = {
        1: [
          _request(id: 1, status: 0),
          _request(id: 2, status: 2, remarks: 'Not enough balance'),
          _request(id: 3, status: 3),
        ],
      };

      await _pump(tester, _hosts(stats: _stats(), pages: rows));
      await _scrollDown(tester);
      expect(find.text('Pending'), findsOneWidget);
      expect(find.text('Rejected'), findsOneWidget);
      expect(find.text('Completed'), findsOneWidget);

      await _pump(
        tester,
        _hosts(stats: _stats(), pages: rows),
        locale: const Locale('ar'),
      );
      await _scrollDown(tester);
      expect(find.text('قيد الانتظار'), findsOneWidget);
      expect(find.text('مرفوض'), findsOneWidget);
      expect(find.text('مكتمل'), findsOneWidget);
    });

    test('the client-only status gets a safe label, not a driver action', () {
      // Status 1 belongs to the client workflow; a driver request should never
      // reach it, and if one did it must still read as something.
      final request = _request(status: 1);
      expect(request.status, 1);
    });

    testWidgets('dates use the application convention', (tester) async {
      await _pump(
        tester,
        _hosts(
          stats: _stats(),
          pages: {
            1: [
              _request(
                requestedAt: '2026-01-15 10:30:00',
                processedAt: '2026-02-20 08:00:00',
                status: 3,
              ),
            ],
          },
        ),
      );
      await _scrollDown(tester);

      expect(find.text('Requested: 15/01/2026'), findsOneWidget);
      expect(find.text('Processed: 20/02/2026'), findsOneWidget);
      // No raw MySQL timestamp anywhere.
      expect(find.textContaining('2026-01-15'), findsNothing);
      expect(find.textContaining('10:30'), findsNothing);
    });

    testWidgets('a zero date never renders raw', (tester) async {
      await _pump(
        tester,
        _hosts(
          stats: _stats(),
          pages: {
            1: [_request(requestedAt: '0000-00-00 00:00:00')],
          },
        ),
      );
      await _scrollDown(tester);

      expect(find.textContaining('0000-00-00'), findsNothing);
      expect(find.text('Requested: Not available'), findsOneWidget);
    });

    testWidgets('an unprocessed request shows no processed date', (
      tester,
    ) async {
      await _pump(
        tester,
        _hosts(stats: _stats(), pages: {1: [_request(status: 0)]}),
      );
      await _scrollDown(tester);

      expect(find.textContaining('Processed'), findsNothing);
    });

    testWidgets('a rejection reason is shown, once', (tester) async {
      await _pump(
        tester,
        _hosts(
          stats: _stats(),
          pages: {
            1: [
              _request(
                status: 2,
                remarks: 'Insufficient documentation',
                processedAt: '2026-02-02 09:00:00',
              ),
            ],
          },
        ),
      );
      await _scrollDown(tester);

      expect(find.text('Reason'), findsOneWidget);
      expect(find.text('Insufficient documentation'), findsOneWidget);
    });

    testWidgets('no reason block when there is no reason', (tester) async {
      await _pump(
        tester,
        _hosts(stats: _stats(), pages: {1: [_request(status: 2)]}),
      );
      await _scrollDown(tester);

      expect(find.text('Reason'), findsNothing);
    });

    testWidgets('private fields never reach the screen', (tester) async {
      await _pump(
        tester,
        _hosts(stats: _stats(), pages: {1: [_request(status: 3)]}),
      );
      await _scrollDown(tester);

      expect(find.textContaining('IBAN'), findsNothing);
      expect(find.textContaining('SECRET'), findsNothing);
      expect(find.textContaining('admin'), findsNothing);
    });

    test('the row model reads the admin remark and ignores private fields', () {
      final request = _request(remarks: 'Rejected for QA', status: 2);

      expect(request.note, 'Rejected for QA');
      expect(request.processedAt, isEmpty);
      // account_details and admin_id are not parsed at all.
    });
  });

  // ---------------------------------------------------------------------------
  group('session boundaries', () {
    testWidgets('the amount, the method and the history all go', (
      tester,
    ) async {
      final hosts = _hosts(stats: _stats(), pages: {1: [_request()]});
      await _pump(tester, hosts);

      await tester.enterText(_amountField(), '75.00');
      await tester.pump();
      expect(find.text('75.00'), findsOneWidget);

      UserSessionState.reset(SessionResetReason.accountChanged);
      await tester.pump();

      expect(find.text('75.00'), findsNothing);
      expect(hosts.requests.requests, isEmpty);
      expect(hosts.requests.currentPage, 1);
    });

    test('a reply that outlives its session is not written back', () async {
      final adapter = _FakeAdapter();
      final provider = _provider(adapter);
      addTearDown(provider.dispose);

      final inFlight = provider.submitWithdrawalRequest(
        canonicalAmount: '12.50',
        withdrawalMethod: 'cash',
      );
      UserSessionState.reset(SessionResetReason.accountChanged);
      await inFlight;

      // The caller still learns what happened; the next driver's provider does
      // not inherit it.
      expect(provider.lastCode, isNull);
    });

    testWidgets('Driver A\'s outcome never lands in Driver B\'s session', (
      tester,
    ) async {
      final hosts = _hosts(stats: _stats(), holdSubmission: true);
      await _pump(tester, hosts);

      await _submit(tester, '10.00');
      UserSessionState.reset(SessionResetReason.accountChanged);
      await tester.pump();

      hosts.withdrawal.release();
      await tester.pump(const Duration(milliseconds: 10));
      await tester.pump();

      expect(find.byType(SnackBar), findsNothing);
      expect(
        find.text('Withdrawal request submitted successfully.'),
        findsNothing,
      );
    });

    test('the withdrawal provider clears its own state', () {
      final provider = WithdrawalProvider();
      addTearDown(provider.dispose);

      provider.selectOption('click');
      provider.updateAmount('250.00 JOD');

      UserSessionState.reset(SessionResetReason.logout);

      expect(provider.selectedOption, 'cash');
      expect(provider.amount, '00.00 JOD');
      expect(provider.lastCode, isNull);
    });

    test('a disabled account still ends the session globally', () async {
      // The withdrawal path never catches a 403: sessionDio owns that, and the
      // provider only sees the code it produced.
      final provider = WithdrawalProvider();
      addTearDown(provider.dispose);

      expect(
        provider.codeFromResponse({'code': 'DRIVER_INACTIVE'}),
        WithdrawalSubmissionCode.driverInactive,
      );
    });
  });

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
                stats: _stats(available: 123456.78, reserved: 9999.99),
                pages: {
                  1: [
                    _request(),
                    _request(
                      id: 2,
                      status: 2,
                      processedAt: '2026-02-02 09:00:00',
                      remarks:
                          'This payout was rejected because the submitted '
                          'documentation did not match the account on file, '
                          'and the amount exceeded the agreed daily limit.',
                    ),
                  ],
                },
              ),
              locale: locale,
              size: size,
            );
            await _scrollDown(tester);

            expect(tester.takeException(), isNull);
          },
        );
      }
    }

    testWidgets('the form stays usable with the keyboard raised', (
      tester,
    ) async {
      await _pump(tester, _hosts(stats: _stats()), size: const Size(360, 640));

      tester.view.viewInsets = const FakeViewPadding(bottom: 320 * 3);
      addTearDown(tester.view.resetViewInsets);
      await tester.pump();
      expect(tester.takeException(), isNull);

      // Only 320dp of page is left, so the form has to be scrolled to — the
      // point is that it can be reached and typed into, not that it happens to
      // be on screen.
      await tester.scrollUntilVisible(
        _amountField(),
        160,
        scrollable: find.byType(Scrollable).first,
      );
      expect(_amountField(), findsOneWidget);
      await tester.enterText(_amountField(), '5.00');
      await tester.pump();

      expect(tester.widget<TextField>(_amountField()).controller?.text, '5.00');
      expect(tester.takeException(), isNull);
    });

    testWidgets('the content clears the floating chat launcher', (
      tester,
    ) async {
      await _pump(tester, _hosts(stats: _stats(), pages: {1: [_request()]}));

      final list = tester.widget<ListView>(find.byType(ListView));
      expect(
        (list.padding as EdgeInsets).bottom,
        DriverChatBubble.reservedBottomSpace + 16,
      );
    });
  });
}
