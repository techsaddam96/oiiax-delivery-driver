import 'dart:convert';
import 'dart:typed_data';

import 'package:blockatie/constants/app_urls.dart';
import 'package:blockatie/models/driver_tour.dart';
import 'package:blockatie/services/driver_tour_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _CapturedRequest {
  const _CapturedRequest(this.options, this.body);
  final RequestOptions options;
  final String body;
  String get wire => '${options.uri.query}&$body';
}

class _Adapter implements HttpClientAdapter {
  _Adapter(this._handler);
  final Future<ResponseBody> Function(RequestOptions options) _handler;
  final requests = <_CapturedRequest>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    var body = '';
    if (requestStream != null) {
      final chunks = await requestStream.toList();
      body = utf8.decode(chunks.expand((chunk) => chunk).toList());
    }
    requests.add(_CapturedRequest(options, body));
    return _handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Map<String, dynamic> body, {int status = 200}) =>
    ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );

Map<String, dynamic> _ok(Map<String, dynamic> data) => <String, dynamic>{
  'success': true,
  'status': 'success',
  'data': data,
};

Map<String, dynamic> _failure(String code) => <String, dynamic>{
  'success': false,
  'status': 'error',
  'code': code,
};

({DriverTourService service, _Adapter adapter}) _service(
  Future<ResponseBody> Function(RequestOptions) responder,
) {
  final adapter = _Adapter(responder);
  final dio = Dio(BaseOptions(validateStatus: (_) => true))
    ..httpClientAdapter = adapter;
  return (
    service: DriverTourService(dio: dio, apiKeyLoader: () async => 'tour-key'),
    adapter: adapter,
  );
}

Map<String, dynamic> _tour({
  int id = 71,
  String state = 'ready',
  int version = 3,
}) => <String, dynamic>{
  'tour_id': id,
  'tour_state': state,
  'state_version': version,
  'planned_stop_count': 2,
  'requires_explicit_start': state == 'ready',
  'started_at': null,
  'interrupted_at': null,
  'completed_at': null,
};

Map<String, dynamic> _details({
  int id = 71,
  String state = 'ready',
  bool accepted = false,
}) => <String, dynamic>{
  'tour': _tour(id: id, state: state),
  'summary': <String, dynamic>{
    'planned_stop_count': 2,
    'snapshot_stop_count': 2,
    'outcome_stop_count': 0,
    'remaining_stop_count': 2,
    'can_complete': false,
  },
  'stops': <Map<String, dynamic>>[
    <String, dynamic>{
      'stop_id': 800,
      'shipment_id': 901,
      'stop_order': 1,
      'stop_state': 'pending',
      'driver_has_accepted': accepted,
      // A malicious/misconfigured response must not become PII in the app
      // before the explicit acceptance flag is true.
      'policy_num': 'BLK-901',
      'recipient_name': 'Private recipient',
      'recipient_phone': '0790000000',
      'delivery_address': 'Private address',
    },
  ],
};

void main() {
  group('release gating', () {
    test('Tours stay hidden unless the build activates them', () {
      expect(AppUrls.driverToursEnabled, isFalse);
    });

    test('the Tours API follows the services host by default', () {
      final services = Uri.parse(AppUrls.baseUrl);
      final tours = Uri.parse(AppUrls.driverTours);
      expect(tours.origin, services.origin);
      expect(tours.path, '/modules/driver_tours/api/driver_tours.php');
      if (AppUrls.baseUrl == 'https://dashboard.blockatie.com/services') {
        expect(
          AppUrls.driverTours,
          'https://dashboard.blockatie.com/modules/driver_tours/api/driver_tours.php',
        );
      }
    });
  });

  group('privacy-safe model parsing', () {
    test(
      'a pre-start stop drops PII even if it appears in a malformed body',
      () {
        final details = DriverTourDetails.fromJson(_details(accepted: false));
        final stop = details.stops.single;
        expect(stop.driverHasAccepted, isFalse);
        expect(stop.policyNumber, isNull);
      },
    );

    test('an accepted stop exposes only its authorized shipment reference', () {
      final details = DriverTourDetails.fromJson(_details(accepted: true));
      expect(details.stops.single.policyNumber, 'BLK-901');
    });
  });

  test(
    'current uses the exact authenticated GET contract and no identity field',
    () async {
      final built = _service(
        (_) async => _json(
          _ok(<String, dynamic>{
            'tours': <dynamic>[_tour()],
          }),
        ),
      );

      final tours = await built.service.current();

      expect(tours.single.id, 71);
      final request = built.adapter.requests.single;
      expect(
        request.options.uri.toString(),
        '${AppUrls.driverTours}?action=current',
      );
      expect(request.options.method, 'GET');
      expect(request.options.uri.queryParameters, <String, String>{
        'action': 'current',
      });
      expect(request.options.headers['X-API-KEY'], 'tour-key');
      expect(request.wire.contains('driver_id'), isFalse);
      expect(request.wire.contains('driverId'), isFalse);
    },
  );

  test(
    'details sends only tour_id and preserves the server privacy projection',
    () async {
      final built = _service((_) async => _json(_ok(_details())));

      final details = await built.service.details(71);

      expect(details.stops.single.driverHasAccepted, isFalse);
      expect(details.stops.single.policyNumber, isNull);
      final request = built.adapter.requests.single;
      expect(request.options.uri.queryParameters, <String, String>{
        'action': 'details',
        'tour_id': '71',
      });
      expect(request.wire.contains('driver_id'), isFalse);
    },
  );

  test('start uses JSON, CAS and a valid UUID idempotency header only', () async {
    final built = _service(
      (_) async => _json(
        _ok(<String, dynamic>{
          'tour_id': 72,
          'state': 'active',
          'idempotent': false,
        }),
      ),
    );

    final result = await built.service.command(
      action: 'start',
      tourId: 72,
      expectedStateVersion: 4,
    );

    expect(result.state, DriverTourState.active);
    final request = built.adapter.requests.single;
    expect(request.options.method, 'POST');
    expect(request.options.uri.toString(), AppUrls.driverTours);
    expect(request.options.headers['X-API-KEY'], 'tour-key');
    final key = request.options.headers['Idempotency-Key']?.toString() ?? '';
    expect(
      RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      ).hasMatch(key),
      isTrue,
    );
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    expect(body, <String, dynamic>{
      'action': 'start',
      'tour_id': 72,
      'expected_state_version': 4,
    });
    expect(request.wire.contains('driver_id'), isFalse);
    expect(request.wire.contains('actor'), isFalse);
  });

  test('an interrupt requires a reason before a request is made', () async {
    final built = _service((_) async => _json(_ok(const <String, dynamic>{})));
    await expectLater(
      built.service.command(
        action: 'interrupt',
        tourId: 73,
        expectedStateVersion: 1,
        reason: ' ',
      ),
      throwsA(
        isA<DriverTourException>().having(
          (error) => error.code,
          'code',
          'INVALID_INTERRUPT_REASON',
        ),
      ),
    );
    expect(built.adapter.requests, isEmpty);
  });

  test(
    'a retry after an unknown network result keeps the same idempotency key',
    () async {
      var calls = 0;
      final built = _service((options) async {
        calls++;
        if (calls == 1) {
          throw DioException(
            requestOptions: options,
            type: DioExceptionType.connectionError,
          );
        }
        return _json(
          _ok(<String, dynamic>{
            'tour_id': 74,
            'state': 'active',
            'idempotent': true,
          }),
        );
      });

      await expectLater(
        built.service.command(
          action: 'start',
          tourId: 74,
          expectedStateVersion: 1,
        ),
        throwsA(isA<DriverTourException>()),
      );
      final result = await built.service.command(
        action: 'start',
        tourId: 74,
        expectedStateVersion: 1,
      );

      expect(result.idempotent, isTrue);
      expect(built.adapter.requests, hasLength(2));
      expect(
        built.adapter.requests[1].options.headers['Idempotency-Key'],
        built.adapter.requests[0].options.headers['Idempotency-Key'],
      );
    },
  );

  test('409 is a recoverable conflict, not a lifecycle success', () async {
    final built = _service(
      (_) async => _json(_failure('TOUR_COMMAND_REJECTED'), status: 409),
    );
    await expectLater(
      built.service.command(
        action: 'resume',
        tourId: 75,
        expectedStateVersion: 2,
      ),
      throwsA(
        isA<DriverTourException>()
            .having(
              (error) => error.kind,
              'kind',
              DriverTourFailureKind.conflict,
            )
            .having((error) => error.statusCode, 'status', 409),
      ),
    );
  });
}
