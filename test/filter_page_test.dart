// Tests for the Filter page.
//
// What these start from: the page force-unwrapped the status options, so the
// first build — before the fetch returned — threw; every failure path set one
// `noShipmentFound` flag, so an offline driver was told they had no work; a
// zero-result search wiped the filters the driver had just entered; only the
// first page of matches was ever shown; and Reset parked the date on
// 2021-11-23.

import 'dart:convert';
import 'dart:io';

import 'package:blockatie/models/client.dart';
import 'package:blockatie/models/filter.dart';
import 'package:blockatie/provider/filter.dart';
import 'package:blockatie/services/auth_secure_store.dart';
import 'package:blockatie/services/auth_services.dart';
import 'package:blockatie/services/user_session_state.dart';
import 'package:blockatie/utils/size_config.dart';
import 'package:blockatie/utils/localization.dart';
import 'package:blockatie/utils/nav.dart';
import 'package:blockatie/views/pages/home/filter/filter.dart';
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

/// One canned answer. A null [body] means the transport itself failed.
class _Reply {
  const _Reply({this.body, this.status = 200, this.delay = Duration.zero});

  final Object? body;
  final int status;
  final Duration delay;
}

/// Routes the three endpoints this page talks to, and records what was asked.
///
/// The transport is replaced, not the provider's methods — so the real
/// re-entry guard, the real revision check and the real parsing all run.
class _Server {
  _Reply status = const _Reply(body: _statusBody);
  _Reply clients = const _Reply(body: _clientsBody);

  /// Answers keyed by the requested page number.
  final Map<int, _Reply> filterByPage = {};
  _Reply filterFallback = const _Reply(body: null);

  final List<Map<String, dynamic>> filterRequests = [];
  int statusCalls = 0;
  int clientCalls = 0;

  int get filterCalls => filterRequests.length;

  _Reply route(RequestOptions options) {
    if (options.path.contains('api_order_status.php')) {
      statusCalls++;
      return status;
    }
    if (options.path.contains('api_driver_stores.php')) {
      clientCalls++;
      return clients;
    }
    final sent = Map<String, dynamic>.from(options.data as Map);
    filterRequests.add(sent);
    final page = int.tryParse('${sent['page']}') ?? 1;
    return filterByPage[page] ?? filterFallback;
  }
}

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.server);

  final _Server server;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final reply = server.route(options);
    if (reply.delay > Duration.zero) {
      await Future<void>.delayed(reply.delay);
    }
    final payload = reply.body;
    if (payload == null) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'offline',
      );
    }
    return ResponseBody.fromString(
      payload is String ? payload : jsonEncode(payload),
      reply.status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

// -----------------------------------------------------------------------------
// Payloads
// -----------------------------------------------------------------------------

const Map<String, dynamic> _statusBody = {
  'success': true,
  'count': 3,
  'status': [
    {'id': 7, 'status_name_en': 'Delivered', 'status_name_ar': 'تم التسليم'},
    {'id': 8, 'status_name_en': 'Returned', 'status_name_ar': 'مرتجع'},
    {'id': 9, 'status_name_en': 'Postponed', 'status_name_ar': 'مؤجل'},
  ],
};

const Map<String, dynamic> _clientsBody = {
  'success': true,
  'count': 2,
  'clients': [
    {
      'id': '3',
      'nclient': 'Amman Store',
      'nstore': 'Downtown',
      'loshop': null,
      'subscription': '1',
      'status': '0',
    },
    {
      'id': '4',
      'nclient': 'Irbid Store',
      'nstore': 'North',
      'loshop': null,
      'subscription': '1',
      'status': '0',
    },
  ],
};

ClientModel _client(String id, String name) => ClientModel(
  id: id,
  nclient: name,
  nstore: name,
  subscription: '1',
  status: '0',
);

Map<String, dynamic> _rows(
  List<int> ids, {
  int page = 1,
  int total = 0,
  int pages = 1,
}) => {
  'success': true,
  'code': 'OK',
  'shipments': [
    for (final id in ids)
      {
        'id': id,
        'policy_num': 'POL-$id',
        'recipient_name': 'Recipient $id',
        'recipient_phone': '079000000$id',
        'shipment_date': '2026-09-10',
      },
  ],
  'pagination': {
    'page': page,
    'limit': FilterProvider.pageSize,
    'total': total == 0 ? ids.length : total,
    'pages': pages,
  },
};

const Map<String, dynamic> _emptyBody = {
  'success': true,
  'code': 'EMPTY',
  'message': 'server prose that must never be rendered',
  'shipments': <dynamic>[],
  'pagination': {'page': 1, 'limit': 20, 'total': 0, 'pages': 0},
};

// -----------------------------------------------------------------------------
// Harness
// -----------------------------------------------------------------------------

({FilterProvider provider, _Server server}) _build() {
  final server = _Server();
  final dio = Dio(BaseOptions(validateStatus: (_) => true))
    ..httpClientAdapter = _FakeAdapter(server)
    // Dio's default transformer decodes JSON on a background isolate, which a
    // widget test's fake clock cannot flush. Decoding inline keeps the reply on
    // the same timeline as the pumps.
    ..transformer = SyncTransformer();
  return (provider: FilterProvider(httpClient: dio), server: server);
}

Widget _app(FilterProvider provider, {Locale locale = const Locale('en')}) {
  return ChangeNotifierProvider<FilterProvider>.value(
    value: provider,
    child: MaterialApp(
      navigatorKey: Nav.key,
      locale: locale,
      supportedLocales: const [Locale('en'), Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const FilterPage(),
    ),
  );
}

Future<void> _pump(
  WidgetTester tester,
  FilterProvider provider, {
  Locale locale = const Locale('en'),
  int frames = 6,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  // The page sizes two controls from SizeConfig; without this they collapse to
  // zero height and the layout, not the code under test, is what fails.
  SizeConfig().init(
    const BoxConstraints(maxWidth: 390, maxHeight: 844),
    Orientation.portrait,
  );

  await tester.pumpWidget(_app(provider, locale: locale));
  await _settle(tester, frames: frames);
}

/// Pumps a bounded number of frames.
///
/// `pumpAndSettle` cannot be used here: the loading states render an
/// indefinite CircularProgressIndicator, which never settles.
Future<void> _settle(WidgetTester tester, {int frames = 6}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
}

String _source(String path) => File(path).readAsStringSync();

/// The file with its comments removed, so a sentence explaining a removed API
/// cannot satisfy a scan looking for that API.
String _code(String path) => _source(path)
    .split('\n')
    .where(
      (line) =>
          !line.trimLeft().startsWith('//') && !line.trimLeft().startsWith('*'),
    )
    .join('\n');

const _page = 'lib/views/pages/home/filter/filter.dart';
const _providerFile = 'lib/provider/filter.dart';
const _modelFile = 'lib/models/filter.dart';
const _calendarFile = 'lib/views/bottmsheets/calander_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    AuthService.configureForTesting(secureStore: _FakeSecureStore());
    await AuthService.saveApiKey('test-api-key', '9');
    AppLocalizations.applyLocale(const Locale('en'));
  });

  tearDown(AuthService.resetForTesting);

  // ---------------------------------------------------------------------------
  group('contract', () {
    test('1. the provider never reaches for the root navigator context', () {
      expect(_code(_providerFile).contains('Nav.context'), isFalse);
    });

    test('2. the provider shows no dialogs and raises no toasts', () {
      final source = _code(_providerFile);
      expect(source.contains('showAlertDialog'), isFalse);
      expect(source.contains('AppUtils'), isFalse);
      expect(source.contains('ScaffoldMessenger'), isFalse);
    });

    test('3. the API-key wording is gone from the provider', () {
      expect(
        _source(_providerFile).contains('Missing user ID or API key'),
        isFalse,
      );
    });

    test('4. the provider owns no copy and resolves no locale', () {
      final source = _code(_providerFile);
      expect(source.contains('easy_localization'), isFalse);
      expect(source.contains('AppLocalizations'), isFalse);
      expect(RegExp(r'\btr\(').hasMatch(source), isFalse);
    });

    test('5. no hardcoded date survives anywhere in the feature', () {
      for (final file in [_providerFile, _page, _calendarFile]) {
        expect(_code(file).contains('DateTime(2021'), isFalse, reason: file);
      }
    });

    test('6. the filter no longer reaches into TimeProvider', () {
      for (final file in [_providerFile, _page]) {
        expect(_code(file).contains('TimeProvider'), isFalse, reason: file);
      }
    });

    test('7. the request never carries a driver or client identity', () {
      final source = _code(_providerFile);
      expect(source.contains("'driver_id'"), isFalse);
      expect(source.contains("'client_id'"), isFalse);
    });

    test('8. the page reads the locale MaterialApp resolved', () {
      final source = _code(_page);
      expect(source.contains('Localizations.localeOf(context)'), isTrue);
      expect(source.contains('context.locale'), isFalse);
    });

    test('9. the page no longer depends on EasyLocalization', () {
      expect(
        _code(_page).contains("import 'package:easy_localization"),
        isFalse,
      );
    });

    test('10. the status options are never force-unwrapped', () {
      final source = _code(_page);
      expect(source.contains('statusShipmentData!'), isFalse);
      expect(source.contains('.status!'), isFalse);
    });

    test('11. status labels come from the one shared table', () {
      expect(_code(_page).contains('getStatusLabel('), isTrue);
    });

    test('12. the page clears the floating chat launcher', () {
      expect(
        _code(_page).contains('DriverChatBubble.reservedBottomSpace + 16'),
        isTrue,
      );
    });

    test('13. alignment is directional, so Arabic mirrors', () {
      final source = _code(_page);
      expect(source.contains('AlignmentDirectional.centerStart'), isTrue);
      expect(source.contains('Alignment.centerLeft'), isFalse);
      expect(source.contains('EdgeInsets.only(left:'), isFalse);
    });

    test('14. the model does not carry the endpoint prose', () {
      final source = _code(_modelFile);
      expect(source.contains("json['message']"), isFalse);
      expect(source.contains('final String message'), isFalse);
    });

    test('15. opening the calendar does not write a date', () {
      // The two lines that used to run here set the field before the driver had
      // touched anything, so open-then-cancel left a date behind.
      final show = _code(
        _calendarFile,
      ).split('showModalBottomSheet').first.split('static Future').last;
      expect(show.contains('dateController'), isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  group('FilterCriteria', () {
    test('16. the default status is All', () {
      expect(const FilterCriteria().statusId, 0);
    });

    test('17. a neutral criteria filters nothing', () {
      expect(const FilterCriteria().hasAny, isFalse);
      expect(const FilterCriteria(statusId: 7).hasAny, isTrue);
      expect(const FilterCriteria(storeId: '3').hasAny, isTrue);
      expect(FilterCriteria(date: DateTime(2026, 1, 1)).hasAny, isTrue);
    });

    test('18. no date means no date parameter', () {
      expect(const FilterCriteria().isoDate, isNull);
    });

    test('19. the wire format is a zero-padded yyyy-MM-dd', () {
      expect(FilterCriteria(date: DateTime(2026, 3, 7)).isoDate, '2026-03-07');
      expect(
        FilterCriteria(date: DateTime(2026, 12, 31)).isoDate,
        '2026-12-31',
      );
    });

    test('20. an unset date is omitted, never sent empty', () {
      final body = const FilterCriteria().toRequest(page: 1, limit: 20);
      expect(body.containsKey('shipment_date'), isFalse);
    });

    test('21. All status is omitted, never sent as 0', () {
      final body = const FilterCriteria().toRequest(page: 1, limit: 20);
      expect(body.containsKey('shipment_status'), isFalse);
    });

    test('22. all stores is omitted, never sent as an empty string', () {
      final body = const FilterCriteria().toRequest(page: 1, limit: 20);
      expect(body.containsKey('store_id'), isFalse);
    });

    test('23. every set filter reaches the request with the cursor', () {
      final body = FilterCriteria(
        date: DateTime(2026, 5, 4),
        statusId: 7,
        storeId: '3',
      ).toRequest(page: 2, limit: 20);

      expect(body['page'], '2');
      expect(body['limit'], '20');
      expect(body['shipment_date'], '2026-05-04');
      expect(body['shipment_status'], '7');
      expect(body['store_id'], '3');
    });

    test('24. the date can be cleared explicitly', () {
      final criteria = FilterCriteria(date: DateTime(2026, 5, 4));
      expect(criteria.copyWith(date: null).date, isNull);
    });

    test('25. the store can be cleared explicitly', () {
      const criteria = FilterCriteria(storeId: '3');
      expect(criteria.copyWith(storeId: null).storeId, isNull);
    });

    test('26. an unmentioned field is left alone', () {
      final criteria = FilterCriteria(
        date: DateTime(2026, 5, 4),
        statusId: 7,
        storeId: '3',
      );
      final next = criteria.copyWith(statusId: 8);

      expect(next.statusId, 8);
      expect(next.date, criteria.date);
      expect(next.storeId, '3');
    });
  });

  // ---------------------------------------------------------------------------
  group('response model', () {
    test('27. the cursor parses the strings the endpoint sends', () {
      final cursor = FilterPagination.fromJson({
        'page': '2',
        'limit': '20',
        'total': '45',
        'pages': '3',
      });

      expect(cursor, isNotNull);
      expect(cursor!.page, 2);
      expect(cursor.total, 45);
      expect(cursor.pages, 3);
    });

    test('28. a missing field makes the cursor absent, not zero', () {
      expect(
        FilterPagination.fromJson({'page': 1, 'limit': 20, 'total': 45}),
        isNull,
      );
    });

    test('29. a cursor that is not a map is absent', () {
      expect(FilterPagination.fromJson('3'), isNull);
      expect(FilterPagination.fromJson(null), isNull);
    });

    test('30. an impossible cursor is refused', () {
      expect(
        FilterPagination.fromJson({
          'page': 0,
          'limit': 20,
          'total': 5,
          'pages': 1,
        }),
        isNull,
      );
    });

    test('31. there is more while the page is behind the last', () {
      const cursor = FilterPagination(page: 1, limit: 20, total: 45, pages: 3);
      expect(cursor.hasMore, isTrue);
    });

    test('32. the last page reports no more', () {
      const cursor = FilterPagination(page: 3, limit: 20, total: 45, pages: 3);
      expect(cursor.hasMore, isFalse);
    });

    test('33. a reply with no rows key cannot be trusted', () {
      expect(FilterResponse.fromJson({'success': true, 'code': 'OK'}), isNull);
    });

    test('34. a rows key that is not a list cannot be trusted', () {
      expect(
        FilterResponse.fromJson({'success': true, 'shipments': 'none'}),
        isNull,
      );
    });

    test('35. a reply that is not a map cannot be trusted', () {
      expect(FilterResponse.fromJson('<html>502</html>'), isNull);
    });

    test('36. rows parse and the code is normalised', () {
      final parsed = FilterResponse.fromJson({
        'success': true,
        'code': ' ok ',
        'shipments': [
          {'id': 1, 'policy_num': 'POL-1'},
        ],
        'pagination': {'page': 1, 'limit': 20, 'total': 1, 'pages': 1},
      });

      expect(parsed, isNotNull);
      expect(parsed!.code, 'OK');
      expect(parsed.shipments.single.id, 1);
      expect(parsed.pagination?.total, 1);
    });

    test('37. junk rows are dropped without losing the good ones', () {
      final parsed = FilterResponse.fromJson({
        'success': true,
        'shipments': [
          {'id': 1, 'policy_num': 'POL-1'},
          'garbage',
          null,
        ],
      });

      expect(parsed, isNotNull);
      expect(parsed!.shipments, hasLength(1));
      expect(parsed.pagination, isNull);
    });
  });

  // ---------------------------------------------------------------------------
  group('opening state', () {
    test('38. the status filter opens on All', () {
      final provider = _build().provider;
      addTearDown(provider.dispose);
      expect(provider.draft.statusId, 0);
    });

    test('39. nothing has been searched yet', () {
      final provider = _build().provider;
      addTearDown(provider.dispose);
      expect(provider.queryState, FilterQueryState.idle);
      expect(provider.isQuerying, isFalse);
    });

    test('40. there are no rows and no cursor', () {
      final provider = _build().provider;
      addTearDown(provider.dispose);
      expect(provider.shipments, isEmpty);
      expect(provider.pagination, isNull);
      expect(provider.hasMore, isFalse);
    });

    test('41. no day is preselected', () {
      final provider = _build().provider;
      addTearDown(provider.dispose);
      expect(provider.selectedDate, isNull);
      expect(provider.formattedDate, '');
    });

    test('42. the date field opens empty', () {
      final provider = _build().provider;
      addTearDown(provider.dispose);
      expect(provider.dateController.text, isEmpty);
    });

    test('43. the calendar opens on the current month', () {
      final provider = _build().provider;
      addTearDown(provider.dispose);
      final now = DateTime.now();
      expect(provider.visibleMonth.year, now.year);
      expect(provider.visibleMonth.month, now.month);
    });
  });

  // ---------------------------------------------------------------------------
  group('query outcome', () {
    test('44. matches are rows', () async {
      final harness = _build();
      addTearDown(harness.provider.dispose);
      harness.server.filterByPage[1] = _Reply(body: _rows([1, 2]));

      await harness.provider.filterShipment();

      expect(harness.provider.queryState, FilterQueryState.rows);
      expect(harness.provider.shipments, hasLength(2));
      expect(harness.provider.totalResults, 2);
    });

    test('45. a genuinely empty result is empty', () async {
      final harness = _build();
      addTearDown(harness.provider.dispose);
      harness.server.filterByPage[1] = const _Reply(body: _emptyBody);

      await harness.provider.filterShipment();

      expect(harness.provider.queryState, FilterQueryState.empty);
      expect(harness.provider.shipments, isEmpty);
    });

    test('46. an offline device fails, it does not report no work', () async {
      final harness = _build();
      addTearDown(harness.provider.dispose);
      harness.server.filterByPage[1] = const _Reply(body: null);

      await harness.provider.filterShipment();

      expect(harness.provider.queryState, FilterQueryState.failed);
      expect(harness.provider.queryState, isNot(FilterQueryState.empty));
    });

    test('47. a server error fails', () async {
      final harness = _build();
      addTearDown(harness.provider.dispose);
      harness.server.filterByPage[1] = const _Reply(
        body: {'success': false},
        status: 500,
      );

      await harness.provider.filterShipment();

      expect(harness.provider.queryState, FilterQueryState.failed);
    });

    test('48. a malformed 200 fails', () async {
      final harness = _build();
      addTearDown(harness.provider.dispose);
      harness.server.filterByPage[1] = const _Reply(body: '<html>oops</html>');

      await harness.provider.filterShipment();

      expect(harness.provider.queryState, FilterQueryState.failed);
      expect(harness.provider.shipments, isEmpty);
    });

    test('49. success:false is a failure, not an empty result', () async {
      final harness = _build();
      addTearDown(harness.provider.dispose);
      harness.server.filterByPage[1] = const _Reply(
        body: {'success': false, 'code': 'INVALID_INPUT', 'shipments': []},
      );

      await harness.provider.filterShipment();

      expect(harness.provider.queryState, FilterQueryState.failed);
    });

    test('50. a zero-result search keeps every filter on screen', () async {
      final harness = _build();
      final provider = harness.provider;
      addTearDown(provider.dispose);
      harness.server.filterByPage[1] = const _Reply(body: _emptyBody);

      provider.selectStatusId(7);
      provider.setSelectedClient(_client('3', 'Amman Store'));
      provider.selectDate(12);
      final date = provider.dateController.text;

      await provider.filterShipment();

      expect(provider.queryState, FilterQueryState.empty);
      expect(provider.draft.statusId, 7);
      expect(provider.draft.storeId, '3');
      expect(provider.selectedClient, isNotNull);
      expect(provider.dateController.text, date);
      expect(provider.selectedDate, isNotNull);
    });

    test('51. a failed search keeps every filter on screen', () async {
      final harness = _build();
      final provider = harness.provider;
      addTearDown(provider.dispose);
      harness.server.filterByPage[1] = const _Reply(body: null);

      provider.selectStatusId(8);
      provider.setSelectedClient(_client('4', 'Irbid Store'));

      await provider.filterShipment();

      expect(provider.queryState, FilterQueryState.failed);
      expect(provider.draft.statusId, 8);
      expect(provider.draft.storeId, '4');
    });

    test('52. the query reports itself busy only while in flight', () async {
      final harness = _build();
      final provider = harness.provider;
      addTearDown(provider.dispose);
      harness.server.filterByPage[1] = _Reply(
        body: _rows([1]),
        delay: const Duration(milliseconds: 20),
      );

      final inFlight = provider.filterShipment();
      expect(provider.isQuerying, isTrue);
      expect(provider.queryState, FilterQueryState.loading);

      await inFlight;
      expect(provider.isQuerying, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  group('pagination', () {
    test('53. the first page asks for page one and the page size', () async {
      final harness = _build();
      addTearDown(harness.provider.dispose);
      harness.server.filterByPage[1] = _Reply(body: _rows([1]));

      await harness.provider.filterShipment();

      expect(harness.server.filterRequests.single['page'], '1');
      expect(
        harness.server.filterRequests.single['limit'],
        '${FilterProvider.pageSize}',
      );
    });

    test('54. load more asks the server for the next page', () async {
      final harness = _build();
      addTearDown(harness.provider.dispose);
      harness.server.filterByPage[1] = _Reply(
        body: _rows([1, 2], page: 1, total: 4, pages: 2),
      );
      harness.server.filterByPage[2] = _Reply(
        body: _rows([3, 4], page: 2, total: 4, pages: 2),
      );

      await harness.provider.filterShipment();
      await harness.provider.loadMore();

      expect(harness.server.filterRequests, hasLength(2));
      expect(harness.server.filterRequests.last['page'], '2');
    });

    test('55. the next page is appended, not swapped in', () async {
      final harness = _build();
      addTearDown(harness.provider.dispose);
      harness.server.filterByPage[1] = _Reply(
        body: _rows([1, 2], page: 1, total: 4, pages: 2),
      );
      harness.server.filterByPage[2] = _Reply(
        body: _rows([3, 4], page: 2, total: 4, pages: 2),
      );

      await harness.provider.filterShipment();
      await harness.provider.loadMore();

      expect(harness.provider.shipments.map((s) => s.id).toList(), [
        1,
        2,
        3,
        4,
      ]);
      expect(harness.provider.totalResults, 4);
      expect(harness.provider.hasMore, isFalse);
    });

    test('56. a row repeated across pages is shown once', () async {
      final harness = _build();
      addTearDown(harness.provider.dispose);
      harness.server.filterByPage[1] = _Reply(
        body: _rows([1, 2], page: 1, total: 3, pages: 2),
      );
      harness.server.filterByPage[2] = _Reply(
        body: _rows([2, 3], page: 2, total: 3, pages: 2),
      );

      await harness.provider.filterShipment();
      await harness.provider.loadMore();

      expect(harness.provider.shipments.map((s) => s.id).toList(), [1, 2, 3]);
    });

    test('57. the last page asks for nothing more', () async {
      final harness = _build();
      addTearDown(harness.provider.dispose);
      harness.server.filterByPage[1] = _Reply(
        body: _rows([1, 2], page: 1, total: 2, pages: 1),
      );

      await harness.provider.filterShipment();
      await harness.provider.loadMore();

      expect(harness.provider.hasMore, isFalse);
      expect(harness.server.filterRequests, hasLength(1));
    });

    test('58. a failed next page keeps the rows already on screen', () async {
      final harness = _build();
      addTearDown(harness.provider.dispose);
      harness.server.filterByPage[1] = _Reply(
        body: _rows([1, 2], page: 1, total: 4, pages: 2),
      );
      harness.server.filterByPage[2] = const _Reply(body: null);

      await harness.provider.filterShipment();
      await harness.provider.loadMore();

      expect(harness.provider.queryState, FilterQueryState.rows);
      expect(harness.provider.shipments, hasLength(2));
      expect(harness.provider.loadMoreFailed, isTrue);
      expect(harness.provider.isLoadingMore, isFalse);
    });

    test('59. retrying the next page clears the failure', () async {
      final harness = _build();
      addTearDown(harness.provider.dispose);
      harness.server.filterByPage[1] = _Reply(
        body: _rows([1, 2], page: 1, total: 4, pages: 2),
      );
      harness.server.filterByPage[2] = const _Reply(body: null);

      await harness.provider.filterShipment();
      await harness.provider.loadMore();

      harness.server.filterByPage[2] = _Reply(
        body: _rows([3, 4], page: 2, total: 4, pages: 2),
      );
      await harness.provider.retryLoadMore();

      expect(harness.provider.loadMoreFailed, isFalse);
      expect(harness.provider.shipments, hasLength(4));
    });

    test('60. page two belongs to the query that produced page one', () async {
      final harness = _build();
      final provider = harness.provider;
      addTearDown(provider.dispose);
      harness.server.filterByPage[1] = _Reply(
        body: _rows([1, 2], page: 1, total: 4, pages: 2),
      );
      harness.server.filterByPage[2] = _Reply(
        body: _rows([3, 4], page: 2, total: 4, pages: 2),
      );

      provider.selectStatusId(7);
      await provider.filterShipment();

      // The driver edits the controls but does not press Search again.
      provider.selectStatusId(9);
      await provider.loadMore();

      expect(harness.server.filterRequests.last['shipment_status'], '7');
      expect(provider.draft.statusId, 9);
      expect(provider.activeCriteria.statusId, 7);
    });
  });

  // ---------------------------------------------------------------------------
  group('duplicate apply', () {
    test('61. a second tap while searching sends nothing', () async {
      final harness = _build();
      final provider = harness.provider;
      addTearDown(provider.dispose);
      harness.server.filterByPage[1] = _Reply(
        body: _rows([1]),
        delay: const Duration(milliseconds: 20),
      );

      final first = provider.filterShipment();
      await provider.filterShipment();
      await first;

      expect(harness.server.filterCalls, 1);
    });

    test('62. a new search is allowed once the first finishes', () async {
      final harness = _build();
      final provider = harness.provider;
      addTearDown(provider.dispose);
      harness.server.filterByPage[1] = _Reply(body: _rows([1]));

      await provider.filterShipment();
      await provider.filterShipment();

      expect(harness.server.filterCalls, 2);
    });
  });

  // ---------------------------------------------------------------------------
  group('staleness and session', () {
    test('63. a reply landing after Reset is discarded', () async {
      final harness = _build();
      final provider = harness.provider;
      addTearDown(provider.dispose);
      harness.server.filterByPage[1] = _Reply(
        body: _rows([1, 2]),
        delay: const Duration(milliseconds: 25),
      );

      final inFlight = provider.filterShipment();
      provider.resetFilters();
      await inFlight;

      expect(provider.queryState, FilterQueryState.idle);
      expect(provider.shipments, isEmpty);
      // Reset also releases the lock, so the driver can search again at once.
      expect(provider.isQuerying, isFalse);
      await provider.filterShipment();
      expect(harness.server.filterCalls, 2);
    });

    test('64. a reply landing after logout is discarded', () async {
      final harness = _build();
      final provider = harness.provider;
      addTearDown(provider.dispose);
      harness.server.filterByPage[1] = _Reply(
        body: _rows([1, 2]),
        delay: const Duration(milliseconds: 25),
      );

      final inFlight = provider.filterShipment();
      UserSessionState.reset(SessionResetReason.accountChanged);
      await inFlight;

      expect(provider.shipments, isEmpty);
      expect(provider.queryState, FilterQueryState.idle);
    });

    test('65. a next page landing after Reset is discarded', () async {
      final harness = _build();
      final provider = harness.provider;
      addTearDown(provider.dispose);
      harness.server.filterByPage[1] = _Reply(
        body: _rows([1, 2], page: 1, total: 4, pages: 2),
      );
      harness.server.filterByPage[2] = _Reply(
        body: _rows([3, 4], page: 2, total: 4, pages: 2),
        delay: const Duration(milliseconds: 25),
      );

      await provider.filterShipment();
      final more = provider.loadMore();
      provider.resetFilters();
      await more;

      expect(provider.shipments, isEmpty);
      expect(provider.queryState, FilterQueryState.idle);
      expect(provider.isLoadingMore, isFalse);
    });

    test('66. logout clears every driver-owned field', () async {
      final harness = _build();
      final provider = harness.provider;
      addTearDown(provider.dispose);
      harness.server.filterByPage[1] = _Reply(
        body: _rows([1, 2], page: 1, total: 4, pages: 2),
      );

      await provider.getStatusShipment();
      await provider.getClients();
      provider.selectStatusId(7);
      provider.setSelectedClient(_client('3', 'Amman Store'));
      provider.selectDate(9);
      await provider.filterShipment();
      expect(provider.shipments, isNotEmpty);

      UserSessionState.reset(SessionResetReason.logout);

      expect(provider.shipments, isEmpty);
      expect(provider.pagination, isNull);
      expect(provider.queryState, FilterQueryState.idle);
      expect(provider.statusState, FilterOptionsState.idle);
      expect(provider.clientsState, FilterOptionsState.idle);
      expect(provider.statusShipmentData, isNull);
      expect(provider.clientList, isEmpty);
      expect(provider.selectedClient, isNull);
      expect(provider.draft.statusId, 0);
      expect(provider.draft.date, isNull);
      expect(provider.draft.storeId, isNull);
      expect(provider.activeCriteria.hasAny, isFalse);
      expect(provider.dateController.text, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  group('reset, date and store', () {
    test('67. Reset returns the page to its neutral state', () async {
      final harness = _build();
      final provider = harness.provider;
      addTearDown(provider.dispose);
      harness.server.filterByPage[1] = _Reply(
        body: _rows([1, 2], page: 1, total: 4, pages: 2),
      );

      provider.selectStatusId(7);
      await provider.filterShipment();
      expect(provider.queryState, FilterQueryState.rows);

      provider.resetFilters();

      expect(provider.queryState, FilterQueryState.idle);
      expect(provider.shipments, isEmpty);
      expect(provider.pagination, isNull);
      expect(provider.loadMoreFailed, isFalse);
      expect(provider.draft.statusId, 0);
    });

    test('68. Reset clears the date field and the store', () {
      final provider = _build().provider;
      addTearDown(provider.dispose);

      provider.selectDate(14);
      provider.setSelectedClient(_client('3', 'Amman Store'));
      expect(provider.dateController.text, isNotEmpty);

      provider.resetFilters();

      expect(provider.dateController.text, isEmpty);
      expect(provider.selectedDate, isNull);
      expect(provider.selectedClient, isNull);
      expect(provider.draft.storeId, isNull);
    });

    test('69. Reset parks the calendar on today, not on a fixed day', () {
      final provider = _build().provider;
      addTearDown(provider.dispose);

      provider.previousMonth();
      provider.previousMonth();
      provider.resetFilters();

      final now = DateTime.now();
      expect(provider.visibleMonth.year, now.year);
      expect(provider.visibleMonth.month, now.month);
      expect(provider.selectedDate, isNull);
    });

    test(
      '70. a chosen day shows dd/MM/yyyy and is sent as yyyy-MM-dd',
      () async {
        final harness = _build();
        final provider = harness.provider;
        addTearDown(provider.dispose);
        harness.server.filterByPage[1] = _Reply(body: _rows([1]));

        provider.selectDate(5);
        final month = provider.visibleMonth;
        final mm = month.month.toString().padLeft(2, '0');

        expect(provider.formattedDate, '05/$mm/${month.year}');
        expect(provider.dateController.text, '05/$mm/${month.year}');

        await provider.filterShipment();

        expect(
          harness.server.filterRequests.single['shipment_date'],
          '${month.year}-$mm-05',
        );
      },
    );

    test(
      '71. all stores clears the filter, and a stale store is dropped',
      () async {
        final harness = _build();
        final provider = harness.provider;
        addTearDown(provider.dispose);

        provider.setSelectedClient(_client('3', 'Amman Store'));
        expect(provider.draft.storeId, '3');

        provider.setSelectedClient(null);
        expect(provider.draft.storeId, isNull);
        expect(provider.selectedClient, isNull);

        // A store that no longer belongs to this driver must not stay selected.
        provider.setSelectedClient(_client('99', 'Closed Store'));
        await provider.getClients();

        expect(provider.clientsState, FilterOptionsState.ready);
        expect(provider.selectedClient, isNull);
        expect(provider.draft.storeId, isNull);
      },
    );
  });

  // ---------------------------------------------------------------------------
  group('page', () {
    testWidgets('72. the first build survives options that have not arrived', (
      tester,
    ) async {
      final harness = _build();
      addTearDown(harness.provider.dispose);
      harness.server.status = const _Reply(
        body: _statusBody,
        delay: Duration(milliseconds: 500),
      );

      await _pump(tester, harness.provider, frames: 2);

      // This is the build that used to throw on a null status list.
      expect(tester.takeException(), isNull);
      expect(find.byType(CircularProgressIndicator), findsWidgets);
      expect(find.text('Choose your filters'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 600));
      await _settle(tester);
      expect(find.text('All'), findsOneWidget);
      expect(find.text('Delivered'), findsOneWidget);
      // The store dropdown lays out too, so a fixed height that is too small
      // for a labelled field is caught here as well as in Arabic.
      expect(tester.takeException(), isNull);
    });

    testWidgets('73. failed options offer a retry, not an empty row', (
      tester,
    ) async {
      final harness = _build();
      addTearDown(harness.provider.dispose);
      harness.server.status = const _Reply(body: null);
      harness.server.clients = const _Reply(body: null);

      await _pump(tester, harness.provider);

      expect(find.text('Unable to load shipment statuses.'), findsOneWidget);
      expect(find.text('Unable to load the store list.'), findsOneWidget);
      expect(find.text('Retry'), findsNWidgets(2));

      harness.server.status = const _Reply(body: _statusBody);
      await tester.tap(find.text('Retry').first);
      await _settle(tester);

      expect(harness.server.statusCalls, 2);
      expect(find.text('Delivered'), findsOneWidget);
    });

    testWidgets('74. a failed search never reads as "no shipments"', (
      tester,
    ) async {
      final harness = _build();
      final provider = harness.provider;
      addTearDown(provider.dispose);
      harness.server.filterByPage[1] = const _Reply(body: null);

      await _pump(tester, provider, locale: const Locale('ar'));

      await tester.tap(find.text('بحث'));
      await _settle(tester);

      expect(provider.queryState, FilterQueryState.failed);
      expect(find.text('تعذر تنفيذ البحث'), findsOneWidget);
      expect(find.text('لا توجد شحنات مطابقة'), findsNothing);
      expect(find.text('No shipments found'), findsNothing);
      expect(find.text('Search failed'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
