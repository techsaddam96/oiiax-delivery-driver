// Tests for the driver settlements list and settlement details.
//
// The defect these start from is a contract one: every settlement endpoint
// answers `{success, code, message…, data:{…}}` and the app read the envelope
// as if it were the payload, so a perfectly good response parsed into an empty
// list, a blank settlement and a JOD 0.00 summary that looked authoritative.
// The envelopes below are copied verbatim from the real endpoints, so a future
// change to either side breaks a test rather than a driver's screen.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:blockatie/constants/fonts.dart';
import 'package:blockatie/models/settlements/driver_financial_summary.dart';
import 'package:blockatie/models/settlements/driver_performance_summary.dart';
import 'package:blockatie/models/settlements/driver_settlement.dart';
import 'package:blockatie/models/settlements/driver_settlement_details.dart';
import 'package:blockatie/models/settlements/driver_settlement_line.dart';
import 'package:blockatie/models/settlements/settlement_pagination.dart';
import 'package:blockatie/provider/bottom_nav.dart';
import 'package:blockatie/provider/home.dart';
import 'package:blockatie/provider/localization.dart';
import 'package:blockatie/provider/notification.dart';
import 'package:blockatie/provider/settlements/driver_settlement_details_provider.dart';
import 'package:blockatie/provider/settlements/driver_settlements_provider.dart';
import 'package:blockatie/provider/shipment.dart';
import 'package:blockatie/services/auth_secure_store.dart';
import 'package:blockatie/services/auth_services.dart';
import 'package:blockatie/services/driver_settlement_service.dart';
import 'package:blockatie/services/user_session_state.dart';
import 'package:blockatie/utils/localization.dart';
import 'package:blockatie/views/pages/settlements/driver_settlement_details_page.dart';
import 'package:blockatie/views/pages/settlements/driver_settlements_page.dart';
import 'package:blockatie/views/pages/settlements/settlement_copy.dart';
import 'package:blockatie/views/widgets/driver_chat_bubble.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// -----------------------------------------------------------------------------
// The real wire format
// -----------------------------------------------------------------------------

/// Captured from `GET api_driver_settlements.php` on a disposable instance.
Map<String, dynamic> listEnvelope({List<Map<String, dynamic>>? settlements}) =>
    {
      'success': true,
      'status': 'success',
      'code': 'OK',
      'message': 'Request completed successfully.',
      'message_en': 'Request completed successfully.',
      'message_ar': 'تم تنفيذ الطلب بنجاح.',
      'data': {
        'settlements':
            settlements ??
            [
              {
                'settlement_id': 7001,
                'statement_number': 'DS-260922-7001',
                'period_from': '2026-08-01',
                'period_to': '2026-08-31',
                'net_amount': 250,
                'remaining_amount': 100,
                'status': 'partial',
                'created_at': '2026-09-22 14:46:09',
                'paid_at': '',
                'shipments_count': 3,
                'has_pdf': false,
              },
            ],
        'pagination': {'page': 1, 'limit': 15, 'total': 1, 'pages': 1},
      },
    };

/// Captured from `GET api_driver_settlement_details.php`.
Map<String, dynamic> detailsEnvelope({
  int shipmentsCount = 3,
  int total = 3,
  int pages = 1,
  int page = 1,
  bool hasPdf = false,
}) => {
  'success': true,
  'status': 'success',
  'code': 'OK',
  'message_en': 'Request completed successfully.',
  'message_ar': 'تم تنفيذ الطلب بنجاح.',
  'data': {
    'settlement': {
      'settlement_id': 7001,
      'statement_number': 'DS-260922-7001',
      'period_from': '2026-08-01',
      'period_to': '2026-08-31',
      'settlement_amount': 250,
      'remaining_amount': 100,
      'status': 'partial',
      'created_at': '2026-09-22 14:46:09',
      'paid_at': '',
      'shipments_count': shipmentsCount,
      'has_pdf': hasPdf,
    },
    // `shipment_status` is the legacy prose the endpoint used to send on its
    // own — a full sentence, always in English. It is still in the payload for
    // older app builds, and is kept here so a test fails if the screen ever
    // starts rendering it again.
    'lines': [
      {
        'shipment_id': 9001,
        'shipment_reference': 'DEMO-9001',
        'shipment_amount': 120.5,
        'net_amount': 120.5,
        'shipment_status_id': 7,
        'status_name_en': 'Delivered',
        'status_name_ar': 'تم التسليم',
        'shipment_status': 'Order was delivered to the customer',
        'shipment_date': '2026-08-05 14:00:00',
      },
      {
        'shipment_id': 9002,
        'shipment_reference': 'DEMO-9002',
        'shipment_amount': 80.25,
        'net_amount': 80.25,
        'shipment_status_id': 11,
        'status_name_en': 'Completed',
        'status_name_ar': 'مكتمل',
        'shipment_status': 'Order is completed and closed in the system',
        'shipment_date': '2026-08-12 09:30:00',
      },
      {
        'shipment_id': 9003,
        'shipment_reference': 'DEMO-9003',
        'shipment_amount': 49.25,
        'net_amount': 49.25,
        'shipment_status_id': 7,
        'status_name_en': 'Delivered',
        'status_name_ar': 'تم التسليم',
        'shipment_status': 'Order was delivered to the customer',
        'shipment_date': '0000-00-00 00:00:00',
      },
    ],
    'pagination': {'page': page, 'limit': 20, 'total': total, 'pages': pages},
  },
};

/// Captured from `GET api_driver_financial_summary.php`.
Map<String, dynamic> financialEnvelope({double cash = 49.25}) => {
  'success': true,
  'status': 'success',
  'code': 'OK',
  'message_en': 'Request completed successfully.',
  'message_ar': 'تم تنفيذ الطلب بنجاح.',
  'data': {
    'cash_in_hand': cash,
    'delivered_unsettled_shipments_count': 1,
    'settled_total': 12.61,
    'settled_statements_count': 1,
    'open_settlements_count': 1,
    'open_settlements_total': 250,
  },
};

/// Captured from `GET api_driver_performance_summary.php`.
Map<String, dynamic> performanceEnvelope() => {
  'success': true,
  'status': 'success',
  'code': 'OK',
  'message_en': 'Request completed successfully.',
  'message_ar': 'تم تنفيذ الطلب بنجاح.',
  'data': {
    'average_rating': 4.6,
    'ratings_count': 12,
    'shipments': {
      'total': 20,
      'delivered': 17,
      'in_progress': 1,
      'failed': 1,
      'returned': 1,
      'cancelled': 0,
      'success_rate': 89.5,
    },
  },
};

Map<String, dynamic> failureEnvelope(String code) => {
  'success': false,
  'status': 'error',
  'code': code,
  'message': 'The requested settlement was not found.',
  'message_en': 'The requested settlement was not found.',
  'message_ar': 'كشف التسوية المطلوب غير موجود.',
};

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

/// Serves the captured envelopes, so the real service parses the real shape.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter();

  final Map<String, Object> responses = {};
  final List<String> requested = [];
  int status = 200;

  void on(String path, Object body) => responses[path] = body;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requested.add('${options.path}?${options.uri.query}');
    final key = responses.keys.firstWhere(
      (path) => options.path.contains(path),
      orElse: () => '',
    );
    final body =
        key.isEmpty ? failureEnvelope('SERVER_ERROR') : responses[key]!;
    if (body is DioException) throw body;
    if (body is List<int>) {
      return ResponseBody.fromBytes(body, status);
    }
    return ResponseBody.fromString(
      jsonEncode(body),
      body is Map && body['success'] == false ? 404 : status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

DriverSettlementService _service(_FakeAdapter adapter) {
  final dio = Dio(BaseOptions(validateStatus: (_) => true));
  dio.httpClientAdapter = adapter;
  return DriverSettlementService(dio: dio);
}

/// Feeds the pages without a transport.
class _StubService implements DriverSettlementService {
  _StubService({
    this.listPages = const {},
    this.details,
    this.financial,
    this.performance,
    this.failListPage,
    this.failDetailPage,
    this.financialCode,
    this.performanceCode,
    this.detailsCode,
    this.pdfCode,
    this.holdFinancial = false,
  });

  Map<int, DriverSettlementPageData> listPages;
  DriverSettlementDetails? details;
  DriverFinancialSummary? financial;
  DriverPerformanceSummary? performance;
  int? failListPage;
  int? failDetailPage;
  String? financialCode;
  String? performanceCode;
  String? detailsCode;
  String? pdfCode;
  bool holdFinancial;

  final List<int> requestedPages = [];
  final List<int> requestedDetailPages = [];
  int pdfCalls = 0;

  @override
  Future<DriverSettlementPageData> fetchSettlements({
    int page = 1,
    int limit = 15,
    String? status,
  }) async {
    requestedPages.add(page);
    await Future<void>.delayed(Duration.zero);
    if (failListPage == page) {
      throw const DriverSettlementException('SERVER_ERROR');
    }
    return listPages[page] ??
        const DriverSettlementPageData(
          [],
          SettlementPagination(page: 1, limit: 15, total: 0, pages: 0),
        );
  }

  @override
  Future<DriverSettlementDetails> fetchSettlementDetails(
    int settlementId, {
    int page = 1,
    int limit = 20,
  }) async {
    requestedDetailPages.add(page);
    await Future<void>.delayed(Duration.zero);
    if (detailsCode != null) throw DriverSettlementException(detailsCode!);
    if (failDetailPage == page) {
      throw const DriverSettlementException('NETWORK');
    }
    return details!;
  }

  @override
  Future<DriverFinancialSummary> fetchFinancialSummary() async {
    if (holdFinancial) return Completer<DriverFinancialSummary>().future;
    await Future<void>.delayed(Duration.zero);
    if (financialCode != null) throw DriverSettlementException(financialCode!);
    return financial ?? DriverFinancialSummary.fromJson(const {});
  }

  @override
  Future<DriverPerformanceSummary> fetchPerformanceSummary() async {
    await Future<void>.delayed(Duration.zero);
    if (performanceCode != null) {
      throw DriverSettlementException(performanceCode!);
    }
    return performance ?? DriverPerformanceSummary.fromJson(const {});
  }

  @override
  Future<File> downloadSettlementPdf(int settlementId, String reference) async {
    pdfCalls++;
    await Future<void>.delayed(Duration.zero);
    throw DriverSettlementException(pdfCode ?? 'PDF_FAILED');
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubNotificationProvider extends NotificationProvider {
  @override
  Future<void> refreshUnreadCount({bool force = false}) async {}
}

class _StubHomeProvider extends HomeProvider {
  @override
  Future<void> getOrderStatus({bool force = false}) async {}
}

// -----------------------------------------------------------------------------
// Fixtures
// -----------------------------------------------------------------------------

DriverSettlement _settlement({
  int id = 7001,
  String number = 'DS-260922-7001',
  double net = 250,
  double remaining = 100,
  String status = 'partial',
  int count = 3,
  bool hasPdf = false,
  String from = '2026-08-01',
  String to = '2026-08-31',
}) => DriverSettlement(
  settlementId: id,
  statementNumber: number,
  periodFrom: from,
  periodTo: to,
  netAmount: net,
  remainingAmount: remaining,
  status: status,
  createdAt: '2026-09-22 14:46:09',
  paidAt: '',
  shipmentsCount: count,
  hasPdf: hasPdf,
);

DriverSettlementLine _line({
  String reference = 'DEMO-9001',
  double amount = 120.5,
  String date = '2026-08-05 14:00:00',
  int statusId = 7,
  String statusNameEn = 'Delivered',
  String statusNameAr = 'تم التسليم',
}) => DriverSettlementLine(
  shipmentId: 9001,
  shipmentReference: reference,
  shipmentAmount: amount,
  netAmount: amount,
  shipmentStatusId: statusId,
  statusNameEn: statusNameEn,
  statusNameAr: statusNameAr,
  shipmentDate: date,
);

DriverSettlementPageData _page(
  List<DriverSettlement> items, {
  int page = 1,
  int pages = 1,
}) => DriverSettlementPageData(
  items,
  SettlementPagination(
    page: page,
    limit: 15,
    total: items.length * pages,
    pages: pages,
  ),
);

// -----------------------------------------------------------------------------
// Harness
// -----------------------------------------------------------------------------

Widget _app({
  required Widget page,
  required DriverSettlementsProvider settlements,
  required DriverSettlementDetailsProvider details,
  Locale locale = const Locale('en'),
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<DriverSettlementsProvider>.value(
        value: settlements,
      ),
      ChangeNotifierProvider<DriverSettlementDetailsProvider>.value(
        value: details,
      ),
      ChangeNotifierProvider<HomeProvider>(create: (_) => _StubHomeProvider()),
      ChangeNotifierProvider<NotificationProvider>(
        create: (_) => _StubNotificationProvider(),
      ),
      ChangeNotifierProvider<ShipmentProvider>(
        create: (_) => ShipmentProvider(),
      ),
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
      home: page,
    ),
  );
}

Future<void> _pumpList(
  WidgetTester tester,
  _StubService service, {
  Locale locale = const Locale('en'),
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = Size(size.width * 3, size.height * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final settlements = DriverSettlementsProvider(service: service);
  addTearDown(settlements.dispose);
  final details = DriverSettlementDetailsProvider(service: service);
  addTearDown(details.dispose);

  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(
    _app(
      page: const DriverSettlementsPage(),
      settlements: settlements,
      details: details,
      locale: locale,
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 10));
  await tester.pump();
}

Future<void> _pumpDetails(
  WidgetTester tester,
  _StubService service, {
  Locale locale = const Locale('en'),
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = Size(size.width * 3, size.height * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final settlements = DriverSettlementsProvider(service: service);
  addTearDown(settlements.dispose);
  final details = DriverSettlementDetailsProvider(service: service);
  addTearDown(details.dispose);

  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(
    _app(
      page: const DriverSettlementDetailsPage(settlementId: 7001),
      settlements: settlements,
      details: details,
      locale: locale,
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 10));
  await tester.pump();
}

Future<void> _scroll(WidgetTester tester, [double dy = -600]) async {
  await tester.drag(find.byType(Scrollable).first, Offset(0, dy));
  await tester.pump();
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
  });

  // ---------------------------------------------------------------------------
  group('response envelope', () {
    test('the settlements list unwraps its payload', () async {
      final adapter =
          _FakeAdapter()..on('api_driver_settlements.php', listEnvelope());
      final result = await _service(adapter).fetchSettlements();

      expect(result.items, hasLength(1));
      expect(result.items.single.settlementId, 7001);
      expect(result.items.single.netAmount, 250);
      expect(result.pagination.total, 1);
      expect(result.pagination.page, 1);
    });

    test('the details payload unwraps', () async {
      final adapter =
          _FakeAdapter()
            ..on('api_driver_settlement_details.php', detailsEnvelope());
      final result = await _service(adapter).fetchSettlementDetails(7001);

      expect(result.settlement.statementNumber, 'DS-260922-7001');
      expect(result.settlement.netAmount, 250);
      expect(result.settlement.remainingAmount, 100);
      expect(result.lines, hasLength(3));
      expect(result.lines.first.shipmentAmount, 120.5);
      expect(result.pagination.total, 3);
    });

    test('the financial summary unwraps', () async {
      final adapter =
          _FakeAdapter()
            ..on('api_driver_financial_summary.php', financialEnvelope());
      final summary = await _service(adapter).fetchFinancialSummary();

      expect(summary.cashInHand, 49.25);
      expect(summary.settledTotal, 12.61);
      expect(summary.openSettlementsTotal, 250);
    });

    test('the performance summary unwraps', () async {
      final adapter =
          _FakeAdapter()
            ..on('api_driver_performance_summary.php', performanceEnvelope());
      final summary = await _service(adapter).fetchPerformanceSummary();

      expect(summary.averageRating, 4.6);
      expect(summary.deliveredShipments, 17);
      expect(summary.successRate, 89.5);
    });

    test('a flat payload without the envelope still works', () {
      final service = DriverSettlementService(dio: Dio());
      final flat = service.debugPayload({'success': true, 'cash_in_hand': 5});

      expect(flat['cash_in_hand'], 5);
    });

    test('a success whose data is not a map is malformed, not empty', () {
      final service = DriverSettlementService(dio: Dio());

      expect(
        () => service.debugPayload({'success': true, 'data': 'nope'}),
        throwsA(
          isA<DriverSettlementException>().having(
            (e) => e.code,
            'code',
            'INVALID_RESPONSE',
          ),
        ),
      );
    });

    test('a successful empty list stays a valid empty list', () async {
      final adapter =
          _FakeAdapter()
            ..on('api_driver_settlements.php', listEnvelope(settlements: []));
      final result = await _service(adapter).fetchSettlements();

      expect(result.items, isEmpty);
    });

    test('a backend failure is a failure, never an empty list', () async {
      final adapter =
          _FakeAdapter()
            ..on('api_driver_settlements.php', failureEnvelope('NOT_FOUND'));

      expect(
        () => _service(adapter).fetchSettlements(),
        throwsA(
          isA<DriverSettlementException>().having(
            (e) => e.code,
            'code',
            'NOT_FOUND',
          ),
        ),
      );
    });
  });

  // ---------------------------------------------------------------------------
  group('settlements list', () {
    testWidgets('a real settlement renders', (tester) async {
      await _pumpList(
        tester,
        _StubService(
          listPages: {
            1: _page([_settlement()]),
          },
          financial: DriverFinancialSummary.fromJson(
            Map<String, dynamic>.from(financialEnvelope()['data'] as Map),
          ),
        ),
      );
      await _scroll(tester);

      expect(find.text('DS-260922-7001'), findsOneWidget);
      expect(find.text('JOD 250.00'), findsWidgets);
      expect(find.text('COD to hand over'), findsWidgets);
    });

    testWidgets('a successful empty list says so', (tester) async {
      await _pumpList(tester, _StubService(listPages: {1: _page(const [])}));
      await _scroll(tester);

      expect(find.textContaining('No settlements'), findsOneWidget);
    });

    testWidgets('a failed first page is an error, not an empty list', (
      tester,
    ) async {
      await _pumpList(tester, _StubService(failListPage: 1));

      expect(
        find.text('Unable to load settlement information. Please try again.'),
        findsOneWidget,
      );
      expect(find.textContaining('No settlements'), findsNothing);
    });

    testWidgets('every status has its own label and colour', (tester) async {
      const statuses = {
        'approved': 'Approved',
        'pdf_generated': 'Ready',
        'sent': 'Sent',
        'partial': 'Partial',
        'paid': 'Paid',
      };

      await _pumpList(
        tester,
        _StubService(
          listPages: {
            1: _page([
              for (final entry in statuses.entries)
                _settlement(
                  id: 7000 + statuses.keys.toList().indexOf(entry.key),
                  number: 'DS-${entry.key}',
                  status: entry.key,
                ),
            ]),
          },
        ),
      );
      await _scroll(tester);

      // Each label appears on its tile and again on its filter chip.
      for (final label in statuses.values) {
        expect(find.text(label), findsWidgets, reason: label);
      }
    });

    testWidgets('Arabic status labels', (tester) async {
      await _pumpList(
        tester,
        _StubService(
          listPages: {
            1: _page([
              _settlement(id: 1, number: 'A', status: 'approved'),
              _settlement(id: 2, number: 'B', status: 'pdf_generated'),
              _settlement(id: 3, number: 'C', status: 'sent'),
              _settlement(id: 4, number: 'D', status: 'partial'),
              _settlement(id: 5, number: 'E', status: 'paid'),
            ]),
          },
        ),
        locale: const Locale('ar'),
      );
      await _scroll(tester);

      for (final label in const [
        'معتمدة',
        'جاهزة',
        'تم الإرسال',
        'جزئية',
        'تمت التسوية',
      ]) {
        expect(find.text(label), findsWidgets, reason: label);
      }
    });

    testWidgets('statuses carry distinct colours, not one green', (
      tester,
    ) async {
      final styles = <String, SettlementStatusStyle>{};
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          supportedLocales: const [Locale('en'), Locale('ar')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Builder(
            builder: (context) {
              for (final status in const [
                'approved',
                'pdf_generated',
                'sent',
                'partial',
                'paid',
              ]) {
                styles[status] = settlementStatusStyle(context, status);
              }
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      // A single green for everything is what made an approved settlement look
      // settled.
      expect(
        styles.values.map((style) => style.foreground).toSet().length,
        greaterThanOrEqualTo(3),
      );
      expect(styles['paid']!.foreground, isNot(styles['partial']!.foreground));
      expect(styles['approved']!.foreground, isNot(styles['paid']!.foreground));
      expect(styles['paid']!.label, 'Paid');
      expect(styles['pdf_generated']!.label, 'Ready');
    });

    testWidgets('all five statuses can be filtered', (tester) async {
      final service = _StubService(
        listPages: {
          1: _page([_settlement()]),
        },
      );
      await _pumpList(tester, service);
      await _scroll(tester);

      for (final label in const [
        'All',
        'Approved',
        'Ready',
        'Sent',
        'Partial',
        'Paid',
      ]) {
        expect(find.text(label), findsWidgets, reason: label);
      }
    });
  });

  // ---------------------------------------------------------------------------
  group('money and dates', () {
    testWidgets('English puts the currency first', (tester) async {
      await _pumpList(
        tester,
        _StubService(
          listPages: {
            1: _page([_settlement(net: 250)]),
          },
        ),
      );
      await _scroll(tester);

      expect(find.text('JOD 250.00'), findsOneWidget);
    });

    testWidgets('Arabic puts the amount first', (tester) async {
      await _pumpList(
        tester,
        _StubService(
          listPages: {
            1: _page([_settlement(net: 250)]),
          },
        ),
        locale: const Locale('ar'),
      );
      await _scroll(tester);

      expect(find.text('250.00 دينار أردني'), findsOneWidget);
      expect(find.textContaining('JOD'), findsNothing);
    });

    testWidgets('trailing zeros are kept and a big total does not overflow', (
      tester,
    ) async {
      await _pumpList(
        tester,
        _StubService(
          listPages: {
            1: _page([_settlement(net: 123456.7)]),
          },
        ),
        size: const Size(360, 640),
      );
      await _scroll(tester);

      expect(find.text('JOD 123456.70'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    test('dates follow the app convention, and bad ones do not print', () {
      expect(settlementDateOrNull('2026-08-05 14:00:00'), '05/08/2026');
      expect(settlementDateOrNull('2026-08-01'), '01/08/2026');
      expect(settlementDateOrNull('0000-00-00 00:00:00'), isNull);
      expect(settlementDateOrNull('not a date'), isNull);
      expect(settlementDateOrNull(''), isNull);
      expect(settlementDate('0000-00-00 00:00:00'), '—');
    });

    test('a naive timestamp is not shifted by a timezone it never had', () {
      // 23:30 must stay on the same calendar day.
      expect(settlementDateOrNull('2026-08-05 23:30:00'), '05/08/2026');
    });

    testWidgets('no raw timestamp reaches the screen', (tester) async {
      await _pumpDetails(
        tester,
        _StubService(
          details: DriverSettlementDetails.fromJson(
            Map<String, dynamic>.from(detailsEnvelope()['data'] as Map),
          ),
        ),
      );

      expect(find.textContaining('0000-00-00'), findsNothing);
      expect(find.textContaining('14:00:00'), findsNothing);
      expect(find.textContaining('05/08/2026'), findsOneWidget);
      // The unparseable line date shows the em dash, not itself.
      expect(find.textContaining('—'), findsWidgets);
    });

    testWidgets('a period keeps its order in Arabic', (tester) async {
      await _pumpList(
        tester,
        _StubService(
          listPages: {
            1: _page([_settlement()]),
          },
        ),
        locale: const Locale('ar'),
      );
      await tester.scrollUntilVisible(
        find.text('DS-260922-7001'),
        200,
        scrollable: find.byType(Scrollable).first,
      );

      // One left-to-right isolate around the whole range: two separately
      // isolated dates would still be swapped by the paragraph.
      expect(
        find.text('\u{2066}01/08/2026 — 31/08/2026\u{2069}'),
        findsOneWidget,
      );
    });
  });

  // ---------------------------------------------------------------------------
  group('accounting semantics', () {
    testWidgets('the settlement total says what it is', (tester) async {
      await _pumpDetails(
        tester,
        _StubService(
          details: DriverSettlementDetails.fromJson(
            Map<String, dynamic>.from(detailsEnvelope()['data'] as Map),
          ),
        ),
      );

      expect(find.text('COD to hand over'), findsOneWidget);
      expect(find.text('Amount'), findsNothing);
      expect(find.text('Remaining'), findsOneWidget);
    });

    testWidgets('and in Arabic', (tester) async {
      await _pumpDetails(
        tester,
        _StubService(
          details: DriverSettlementDetails.fromJson(
            Map<String, dynamic>.from(detailsEnvelope()['data'] as Map),
          ),
        ),
        locale: const Locale('ar'),
      );

      expect(find.text('تحصيل مستحق للشركة'), findsOneWidget);
      expect(find.text('المبلغ'), findsNothing);
    });

    testWidgets('a line is COD, never Net', (tester) async {
      await _pumpDetails(
        tester,
        _StubService(
          details: DriverSettlementDetails.fromJson(
            Map<String, dynamic>.from(detailsEnvelope()['data'] as Map),
          ),
        ),
      );
      await _scroll(tester, -300);

      expect(find.text('COD'), findsWidgets);
      expect(find.text('Net'), findsNothing);
      expect(find.text('الصافي'), findsNothing);
    });

    testWidgets('the summary wording is distinct from the Wallet figure', (
      tester,
    ) async {
      await _pumpList(
        tester,
        _StubService(
          listPages: {
            1: _page([_settlement()]),
          },
          financial: DriverFinancialSummary.fromJson(
            Map<String, dynamic>.from(financialEnvelope()['data'] as Map),
          ),
        ),
      );

      expect(find.text('Cash in hand (COD + fees)'), findsOneWidget);
      expect(find.text('Settled COD'), findsOneWidget);
      expect(find.text('Open settlement COD'), findsOneWidget);
      // The Wallet uses this for COD minus commission — a different number.
      expect(find.text('Cash to settle'), findsNothing);
    });
  });

  // ---------------------------------------------------------------------------
  group('settlement details', () {
    DriverSettlementDetails parsed({
      int shipmentsCount = 3,
      int total = 3,
      int pages = 1,
      bool hasPdf = false,
    }) => DriverSettlementDetails.fromJson(
      Map<String, dynamic>.from(
        detailsEnvelope(
              shipmentsCount: shipmentsCount,
              total: total,
              pages: pages,
              hasPdf: hasPdf,
            )['data']
            as Map,
      ),
    );

    testWidgets('the header and every line render', (tester) async {
      await _pumpDetails(tester, _StubService(details: parsed()));

      expect(find.text('DS-260922-7001'), findsOneWidget);
      expect(find.text('JOD 250.00'), findsOneWidget);
      expect(find.text('JOD 100.00'), findsOneWidget);
      expect(find.text('DEMO-9001'), findsOneWidget);
      expect(find.text('JOD 120.50'), findsOneWidget);

      await _scroll(tester, -300);
      expect(find.text('JOD 80.25'), findsOneWidget);
      expect(find.text('JOD 49.25'), findsOneWidget);
    });

    test('the lines reconcile with the total', () {
      final details = parsed();
      final sum = details.lines.fold<double>(
        0,
        (total, line) => total + line.shipmentAmount,
      );

      expect(sum, details.settlement.netAmount);
    });

    testWidgets('the shipment count uses the stored total when it is real', (
      tester,
    ) async {
      await _pumpDetails(tester, _StubService(details: parsed()));

      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('a stored zero does not claim there are no shipments', (
      tester,
    ) async {
      // `total_shipments` is NOT NULL DEFAULT 0, so a settlement written with
      // zero would show "0 shipments" above three rendered lines.
      await _pumpDetails(
        tester,
        _StubService(details: parsed(shipmentsCount: 0, total: 3)),
      );

      expect(find.text('0'), findsNothing);
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('a settlement with no lines is a valid state', (tester) async {
      final details = DriverSettlementDetails(
        settlement: _settlement(count: 0),
        lines: const [],
        pagination: const SettlementPagination(
          page: 1,
          limit: 20,
          total: 0,
          pages: 0,
        ),
      );
      await _pumpDetails(tester, _StubService(details: details));

      expect(find.textContaining('No shipments'), findsOneWidget);
    });

    testWidgets('a missing settlement is an error, not a blank one', (
      tester,
    ) async {
      await _pumpDetails(tester, _StubService(detailsCode: 'NOT_FOUND'));

      expect(find.text('Settlement not found.'), findsOneWidget);
      expect(find.text('JOD 0.00'), findsNothing);
    });

    testWidgets('the partial status and its remaining amount are shown', (
      tester,
    ) async {
      await _pumpDetails(tester, _StubService(details: parsed()));

      expect(find.text('Remaining'), findsOneWidget);
      expect(find.text('JOD 100.00'), findsOneWidget);
    });

    test('no paid amount is invented when the endpoint omits it', () {
      final settlement = DriverSettlement.fromJson(
        Map<String, dynamic>.from(
          (detailsEnvelope()['data'] as Map)['settlement'] as Map,
        ),
      );

      // The details endpoint returns net and remaining only; the model has no
      // paid field to display, and none is derived.
      expect(settlement.netAmount, 250);
      expect(settlement.remainingAmount, 100);
    });
  });

  // ---------------------------------------------------------------------------
  group('pagination', () {
    testWidgets('the first page is requested once', (tester) async {
      final service = _StubService(
        listPages: {
          1: _page([_settlement()], pages: 2),
        },
      );
      await _pumpList(tester, service);

      expect(service.requestedPages, [1]);
    });

    test('a later page extends the list', () async {
      final service = _StubService(
        listPages: {
          1: _page([_settlement(id: 1, number: 'A')], page: 1, pages: 2),
          2: _page([_settlement(id: 2, number: 'B')], page: 2, pages: 2),
        },
      );
      final provider = DriverSettlementsProvider(service: service);
      addTearDown(provider.dispose);

      await provider.loadInitial();
      await provider.loadMore();

      expect(service.requestedPages, [1, 2]);
      expect(provider.items, hasLength(2));
      expect(provider.currentPage, 2);
    });

    test('a failed later page keeps the rows and the page it had', () async {
      final service = _StubService(
        listPages: {
          1: _page([_settlement()], page: 1, pages: 2),
        },
        failListPage: 2,
      );
      final provider = DriverSettlementsProvider(service: service);
      addTearDown(provider.dispose);

      await provider.loadInitial();
      await provider.loadMore();

      expect(provider.items, hasLength(1));
      expect(provider.currentPage, 1);
      expect(provider.listError, isNull);
      // Reported beside the rows, not instead of them.
      expect(provider.loadMoreError, 'SERVER_ERROR');
    });

    testWidgets('and says so on screen with a retry', (tester) async {
      final service = _StubService(
        listPages: {
          1: _page([_settlement()], page: 1, pages: 2),
        },
        failListPage: 2,
      );
      await _pumpList(tester, service);
      for (var i = 0; i < 4; i++) {
        await _scroll(tester, -600);
        await tester.pump(const Duration(milliseconds: 10));
      }
      await tester.pump();

      expect(service.requestedPages, contains(2));
      expect(
        find.text('Unable to load settlement information. Please try again.'),
        findsWidgets,
      );
    });

    test('a failed page is not retried until the driver asks', () async {
      final service = _StubService(
        listPages: {
          1: _page([_settlement()], page: 1, pages: 2),
        },
        failListPage: 2,
      );
      final provider = DriverSettlementsProvider(service: service);
      addTearDown(provider.dispose);

      await provider.loadInitial();
      await provider.loadMore();
      await provider.loadMore();
      await provider.loadMore();
      expect(service.requestedPages, [1, 2]);

      service.failListPage = null;
      service.listPages = {
        ...service.listPages,
        2: _page([_settlement(id: 2, number: 'B')], page: 2, pages: 2),
      };
      await provider.retryLoadMore();

      expect(service.requestedPages, [1, 2, 2]);
      expect(provider.items, hasLength(2));
      expect(provider.loadMoreError, isNull);
    });

    test('settlement lines page the same way', () async {
      final details = DriverSettlementDetails(
        settlement: _settlement(),
        lines: [_line()],
        pagination: const SettlementPagination(
          page: 1,
          limit: 20,
          total: 2,
          pages: 2,
        ),
      );
      final service = _StubService(details: details, failDetailPage: 2);
      final provider = DriverSettlementDetailsProvider(service: service);
      addTearDown(provider.dispose);

      await provider.load(7001);
      await provider.loadMore();

      expect(service.requestedDetailPages, [1, 2]);
      expect(provider.lines, hasLength(1));
      expect(provider.currentPage, 1);
      expect(provider.error, isNull);
      expect(provider.loadMoreError, 'NETWORK');
    });
  });

  // ---------------------------------------------------------------------------
  group('summary sections', () {
    testWidgets('a section still loading is not an error', (tester) async {
      await _pumpList(
        tester,
        _StubService(
          listPages: {
            1: _page([_settlement()]),
          },
          holdFinancial: true,
        ),
      );

      expect(find.textContaining('Unable to'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsWidgets);
    });

    testWidgets('a successful summary shows its figures', (tester) async {
      await _pumpList(
        tester,
        _StubService(
          listPages: {
            1: _page([_settlement()]),
          },
          financial: DriverFinancialSummary.fromJson(
            Map<String, dynamic>.from(financialEnvelope()['data'] as Map),
          ),
          performance: DriverPerformanceSummary.fromJson(
            Map<String, dynamic>.from(performanceEnvelope()['data'] as Map),
          ),
        ),
      );

      expect(find.text('JOD 49.25'), findsOneWidget);
      expect(find.text('JOD 12.61'), findsOneWidget);
      expect(find.text('4.6 ★'), findsOneWidget);
    });

    testWidgets('a failed summary says so once it has actually failed', (
      tester,
    ) async {
      await _pumpList(
        tester,
        _StubService(
          listPages: {
            1: _page([_settlement()]),
          },
          financialCode: 'SERVER_ERROR',
          performanceCode: 'SERVER_ERROR',
        ),
      );

      expect(
        find.text('Unable to load settlement information. Please try again.'),
        findsWidgets,
      );
    });

    testWidgets('zero is shown only when the server reports zero', (
      tester,
    ) async {
      await _pumpList(
        tester,
        _StubService(
          listPages: {
            1: _page([_settlement()]),
          },
          financial: DriverFinancialSummary.fromJson(
            Map<String, dynamic>.from(
              financialEnvelope(cash: 0)['data'] as Map,
            ),
          ),
        ),
      );

      expect(find.text('JOD 0.00'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  group('settlement document', () {
    DriverSettlementDetails withPdf() => DriverSettlementDetails(
      settlement: _settlement(hasPdf: true),
      lines: [_line()],
      pagination: const SettlementPagination(
        page: 1,
        limit: 20,
        total: 1,
        pages: 1,
      ),
    );

    testWidgets('the action appears only when a document exists', (
      tester,
    ) async {
      await _pumpDetails(tester, _StubService(details: withPdf()));
      expect(find.byIcon(Icons.picture_as_pdf_outlined), findsOneWidget);

      await _pumpDetails(
        tester,
        _StubService(
          details: DriverSettlementDetails(
            settlement: _settlement(),
            lines: const [],
            pagination: const SettlementPagination(
              page: 1,
              limit: 20,
              total: 0,
              pages: 0,
            ),
          ),
        ),
      );
      expect(find.byIcon(Icons.picture_as_pdf_outlined), findsNothing);
    });

    testWidgets('a failure to open is stated in English', (tester) async {
      await _pumpDetails(
        tester,
        _StubService(details: withPdf(), pdfCode: 'PDF_FAILED'),
      );
      await tester.tap(find.byIcon(Icons.picture_as_pdf_outlined));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));
      await tester.pump();

      expect(find.text('Unable to open settlement document.'), findsOneWidget);
    });

    testWidgets('and in Arabic', (tester) async {
      await _pumpDetails(
        tester,
        _StubService(details: withPdf(), pdfCode: 'PDF_FAILED'),
        locale: const Locale('ar'),
      );
      await tester.tap(find.byIcon(Icons.picture_as_pdf_outlined));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));
      await tester.pump();

      expect(find.text('تعذر فتح مستند التسوية.'), findsOneWidget);
      expect(find.textContaining('Unable'), findsNothing);
    });

    testWidgets('a document that is not ready reads differently', (
      tester,
    ) async {
      await _pumpDetails(
        tester,
        _StubService(details: withPdf(), pdfCode: 'PDF_NOT_AVAILABLE'),
      );
      await tester.tap(find.byIcon(Icons.picture_as_pdf_outlined));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));
      await tester.pump();

      expect(
        find.text('The settlement document is not available yet.'),
        findsOneWidget,
      );
    });

    test('the document is fetched from the authenticated endpoint only', () {
      final source =
          File(
            'lib/services/driver_settlement_service.dart',
          ).readAsStringSync();

      expect(source.contains('AppUrls.driverSettlementPdf'), isTrue);
      expect(source.contains('X-API-KEY'), isTrue);
      // No public invoice path is ever built.
      expect(source.contains('assets/invoices'), isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  group('session boundaries', () {
    test('the list is cleared on logout', () async {
      final service = _StubService(
        listPages: {
          1: _page([_settlement()]),
        },
        financial: DriverFinancialSummary.fromJson(
          Map<String, dynamic>.from(financialEnvelope()['data'] as Map),
        ),
      );
      final provider = DriverSettlementsProvider(service: service);
      addTearDown(provider.dispose);

      await provider.loadInitial();
      expect(provider.items, hasLength(1));

      UserSessionState.reset(SessionResetReason.logout);

      expect(provider.items, isEmpty);
      expect(provider.financialSummary, isNull);
      expect(provider.statusFilter, isNull);
    });

    test('a list reply that outlives its session is dropped', () async {
      final service = _StubService(
        listPages: {
          1: _page([_settlement()]),
        },
      );
      final provider = DriverSettlementsProvider(service: service);
      addTearDown(provider.dispose);

      final inFlight = provider.loadInitial();
      UserSessionState.reset(SessionResetReason.accountChanged);
      await inFlight;

      // Driver A's settlements must not land in Driver B's provider, and the
      // summaries that read would have gone on to fetch are abandoned too.
      expect(provider.items, isEmpty);
      expect(provider.financialSummary, isNull);
      expect(provider.listError, isNull);
    });

    test('a detail reply that outlives its session is dropped', () async {
      final details = DriverSettlementDetails(
        settlement: _settlement(),
        lines: [_line()],
        pagination: const SettlementPagination(
          page: 1,
          limit: 20,
          total: 1,
          pages: 1,
        ),
      );
      final provider = DriverSettlementDetailsProvider(
        service: _StubService(details: details),
      );
      addTearDown(provider.dispose);

      final inFlight = provider.load(7001);
      UserSessionState.reset(SessionResetReason.accountChanged);
      await inFlight;

      expect(provider.settlement, isNull);
      expect(provider.lines, isEmpty);
    });

    test(
      'a document fetched for the previous driver is not reported',
      () async {
        final service = _StubService(
          details: DriverSettlementDetails(
            settlement: _settlement(hasPdf: true),
            lines: const [],
            pagination: const SettlementPagination(
              page: 1,
              limit: 20,
              total: 0,
              pages: 0,
            ),
          ),
          pdfCode: 'PDF_FAILED',
        );
        final provider = DriverSettlementDetailsProvider(service: service);
        addTearDown(provider.dispose);

        await provider.load(7001);
        final inFlight = provider.downloadPdf();
        UserSessionState.reset(SessionResetReason.accountChanged);

        expect(await inFlight, isFalse);
        expect(provider.pdfError, isNull);
      },
    );

    test('a disabled account is still the session layer\'s job', () {
      // The settlement service maps transport codes only; 403 DRIVER_INACTIVE
      // is handled by sessionDio, which the shared client is built from.
      final source =
          File(
            'lib/services/driver_settlement_service.dart',
          ).readAsStringSync();

      expect(source.contains('sessionDio('), isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  group('layout', () {
    for (final size in const [Size(360, 640), Size(390, 844), Size(430, 932)]) {
      for (final locale in const [Locale('en'), Locale('ar')]) {
        testWidgets('list at ${size.width.toInt()}x${size.height.toInt()} in '
            '${locale.languageCode}', (tester) async {
          await _pumpList(
            tester,
            _StubService(
              listPages: {
                1: _page([
                  _settlement(net: 123456.78),
                  _settlement(
                    id: 2,
                    number: 'DS-260922-7002-EXTRA-LONG-REFERENCE-VALUE',
                    status: 'paid',
                  ),
                ]),
              },
              financial: DriverFinancialSummary.fromJson(
                Map<String, dynamic>.from(financialEnvelope()['data'] as Map),
              ),
              performance: DriverPerformanceSummary.fromJson(
                Map<String, dynamic>.from(performanceEnvelope()['data'] as Map),
              ),
            ),
            locale: locale,
            size: size,
          );
          await _scroll(tester);

          expect(tester.takeException(), isNull);
        });

        testWidgets(
          'details at ${size.width.toInt()}x${size.height.toInt()} in '
          '${locale.languageCode}',
          (tester) async {
            await _pumpDetails(
              tester,
              _StubService(
                details: DriverSettlementDetails(
                  settlement: _settlement(net: 123456.78, hasPdf: true),
                  lines: [
                    for (var i = 0; i < 12; i++)
                      _line(reference: 'DEMO-90$i', amount: 10.0 * (i + 1)),
                  ],
                  pagination: const SettlementPagination(
                    page: 1,
                    limit: 20,
                    total: 12,
                    pages: 1,
                  ),
                ),
              ),
              locale: locale,
              size: size,
            );
            await _scroll(tester);

            expect(tester.takeException(), isNull);
          },
        );
      }
    }

    testWidgets('both screens clear the floating chat launcher', (
      tester,
    ) async {
      await _pumpList(
        tester,
        _StubService(
          listPages: {
            1: _page([_settlement()]),
          },
        ),
      );
      final list = tester.widget<ListView>(find.byType(ListView));
      expect(
        (list.padding as EdgeInsets).bottom,
        DriverChatBubble.reservedBottomSpace + 16,
      );

      await _pumpDetails(
        tester,
        _StubService(
          details: DriverSettlementDetails(
            settlement: _settlement(),
            lines: [_line()],
            pagination: const SettlementPagination(
              page: 1,
              limit: 20,
              total: 1,
              pages: 1,
            ),
          ),
        ),
      );
      final detail = tester.widget<ListView>(find.byType(ListView));
      expect(
        (detail.padding as EdgeInsets).bottom,
        DriverChatBubble.reservedBottomSpace + 16,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // What the deployed server actually returned while "تسوياتي" failed to load:
  // HTTP 500 with a zero-length body, because the endpoint fatals before it can
  // emit its JSON error envelope. The app handled it correctly but silently, so
  // the console showed nothing and the failure looked like it came from nowhere.
  group('server fatal', () {
    /// A 500 that carries no body at all, exactly as observed in production.
    DioException emptyFatal(String path) {
      final options = RequestOptions(path: path);
      return DioException(
        requestOptions: options,
        type: DioExceptionType.badResponse,
        response: Response<dynamic>(
          requestOptions: options,
          statusCode: 500,
          data: '',
        ),
      );
    }

    test('an empty 500 is reported as SERVER_ERROR', () async {
      final adapter =
          _FakeAdapter()..on(
            'api_driver_settlements.php',
            emptyFatal('api_driver_settlements.php'),
          );

      await expectLater(
        _service(adapter).fetchSettlements(),
        throwsA(
          isA<DriverSettlementException>().having(
            (error) => error.code,
            'code',
            'SERVER_ERROR',
          ),
        ),
      );
    });

    test('the failure is logged with the status, never the key', () async {
      final lines = <String>[];
      final original = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) lines.add(message);
      };
      addTearDown(() => debugPrint = original);

      final adapter =
          _FakeAdapter()..on(
            'api_driver_settlements.php',
            emptyFatal('api_driver_settlements.php'),
          );
      try {
        await _service(adapter).fetchSettlements();
        fail('the fatal should have been reported');
      } on DriverSettlementException {
        // The point of this test is what was written to the console.
      }

      final logged = lines.join('\n');
      expect(logged, contains('api_driver_settlements.php'));
      expect(logged, contains('status=500'));
      expect(logged, contains('code=SERVER_ERROR'));
      // The one thing that must never reach a log line.
      expect(logged, isNot(contains('KEY')));
      expect(logged, isNot(contains('X-API-KEY')));
    });

    test('a server fatal is an error state, not an empty one', () async {
      final adapter =
          _FakeAdapter()..on(
            'api_driver_settlements.php',
            emptyFatal('api_driver_settlements.php'),
          );
      final provider = DriverSettlementsProvider(service: _service(adapter));
      addTearDown(provider.dispose);

      await provider.loadInitial();

      expect(provider.listError, 'SERVER_ERROR');
      expect(provider.items, isEmpty);
    });

    testWidgets('a shipment status reads in the screen language', (
      tester,
    ) async {
      await _pumpDetails(
        tester,
        _StubService(
          details: DriverSettlementDetails.fromJson(
            Map<String, dynamic>.from(detailsEnvelope()['data'] as Map),
          ),
        ),
        locale: const Locale('ar'),
      );

      // The endpoint's own sentence is English and arrives on every reply.
      // It must never be what the driver reads.
      expect(
        find.textContaining('Order is completed and closed'),
        findsNothing,
      );
      expect(find.textContaining('Order was delivered'), findsNothing);
      expect(find.textContaining('تم التسليم'), findsWidgets);
    });

    testWidgets('the same status reads in English on an English screen', (
      tester,
    ) async {
      await _pumpDetails(
        tester,
        _StubService(
          details: DriverSettlementDetails.fromJson(
            Map<String, dynamic>.from(detailsEnvelope()['data'] as Map),
          ),
        ),
      );

      expect(find.textContaining('Delivered'), findsWidgets);
      expect(
        find.textContaining('Order is completed and closed'),
        findsNothing,
      );
    });

    test('the line keeps the status id, not the prose', () {
      final details = DriverSettlementDetails.fromJson(
        Map<String, dynamic>.from(detailsEnvelope()['data'] as Map),
      );

      expect(details.lines.first.shipmentStatusId, 7);
      expect(details.lines.first.statusNameEn, 'Delivered');
      expect(details.lines.first.statusNameAr, 'تم التسليم');
    });

    testWidgets('a line with no status says so instead of guessing', (
      tester,
    ) async {
      final envelope = Map<String, dynamic>.from(
        detailsEnvelope()['data'] as Map,
      );
      envelope['lines'] = [
        {
          'shipment_id': 9001,
          'shipment_reference': 'DEMO-9001',
          'shipment_amount': 10,
          'net_amount': 10,
          'shipment_status_id': 0,
          'status_name_en': '',
          'status_name_ar': '',
          'shipment_date': '2026-08-05 14:00:00',
        },
      ];

      await _pumpDetails(
        tester,
        _StubService(details: DriverSettlementDetails.fromJson(envelope)),
      );

      expect(find.textContaining('Not available'), findsOneWidget);
      // Never the placeholder getStatusLabel would invent for id 0.
      expect(find.textContaining('Status #0'), findsNothing);
    });

    testWidgets('the details screen offers a way back', (tester) async {
      // It is opened without the bottom bar, so before this there was nothing
      // on screen to leave with — only the system back gesture.
      await _pumpDetails(
        tester,
        _StubService(
          details: DriverSettlementDetails.fromJson(
            Map<String, dynamic>.from(detailsEnvelope()['data'] as Map),
          ),
        ),
      );

      final back = find.byTooltip('Back');
      expect(back, findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the back control pops the details route', (tester) async {
      final service = _StubService(
        details: DriverSettlementDetails.fromJson(
          Map<String, dynamic>.from(detailsEnvelope()['data'] as Map),
        ),
      );
      final settlements = DriverSettlementsProvider(service: service);
      addTearDown(settlements.dispose);
      final details = DriverSettlementDetailsProvider(service: service);
      addTearDown(details.dispose);

      await tester.pumpWidget(
        _app(
          page: Builder(
            builder:
                (context) => Scaffold(
                  body: Center(
                    child: ElevatedButton(
                      onPressed:
                          () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder:
                                  (_) => const DriverSettlementDetailsPage(
                                    settlementId: 7001,
                                  ),
                            ),
                          ),
                      child: const Text('open'),
                    ),
                  ),
                ),
          ),
          settlements: settlements,
          details: details,
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Settlement Details'), findsOneWidget);

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      // Back on the opener, and the details route is gone.
      expect(find.text('open'), findsOneWidget);
      expect(find.text('Settlement Details'), findsNothing);
    });

    testWidgets('the settlements list offers a way back too', (tester) async {
      await _pumpList(tester, _StubService());
      expect(find.byTooltip('Back'), findsOneWidget);
    });

    testWidgets('the back arrow points the way the screen reads', (
      tester,
    ) async {
      await _pumpDetails(
        tester,
        _StubService(
          details: DriverSettlementDetails.fromJson(
            Map<String, dynamic>.from(detailsEnvelope()['data'] as Map),
          ),
        ),
        locale: const Locale('ar'),
      );

      final icon = tester.widget<Icon>(
        find.descendant(
          of: find.byTooltip('رجوع'),
          matching: find.byType(Icon),
        ),
      );
      // Arabic mirrors the row, so the control sits on the right and the
      // arrow has to point right with it.
      expect(icon.icon, Icons.arrow_forward_ios_rounded);
    });

    test('no settlements is an empty state, not an error', () async {
      final adapter =
          _FakeAdapter()..on('api_driver_settlements.php', {
            'success': true,
            'status': 'success',
            'code': 'OK',
            'data': {
              'settlements': <dynamic>[],
              'pagination': {'page': 1, 'limit': 15, 'total': 0, 'pages': 0},
            },
          });
      final provider = DriverSettlementsProvider(service: _service(adapter));
      addTearDown(provider.dispose);

      await provider.loadInitial();

      expect(provider.items, isEmpty);
      expect(provider.listError, isNull);
      expect(provider.hasMore, isFalse);
    });
  });
}
