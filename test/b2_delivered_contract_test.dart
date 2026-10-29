// B2 (release blocker RG-11): the "Delivered" request and its eligibility rule.
//
// ShipmentInstantprovider.deliverShipment is driven through a canned HTTP
// adapter that answers exactly what complete_shipment_driver.php answers
// (see SECURITY_RELEASE_B1_IMPLEMENTATION_REPORT.md section 3), including the
// pre-B1 server that sent HTTP 200 for every refusal. No network is used.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:blockatie/constants/app_urls.dart';
import 'package:blockatie/models/shipment_flow_config.dart';
import 'package:blockatie/provider/operational_readiness.dart';
import 'package:blockatie/provider/shipment_instsnt.dart';
import 'package:blockatie/services/auth_secure_store.dart';
import 'package:blockatie/services/auth_services.dart';
import 'package:blockatie/services/user_session_state.dart';
import 'package:blockatie/views/widgets/status_update_sheet.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeSecureStore implements AuthSecureStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

/// One scripted reply: a status and body, a missing reply (timeout), or a
/// reply held until [gate] completes.
class _Reply {
  const _Reply(this.status, this.body) : timeout = false, gate = null;
  const _Reply.timeout() : status = 0, body = '', timeout = true, gate = null;
  _Reply.held(this.status, this.body, Completer<void> this.gate)
    : timeout = false;

  final int status;
  final String body;
  final bool timeout;
  final Completer<void>? gate;
}

class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this.replies);

  final List<_Reply> replies;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final reply = replies.removeAt(0);
    if (reply.gate != null) await reply.gate!.future;
    if (reply.timeout) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.receiveTimeout,
      );
    }
    return ResponseBody.fromString(
      reply.body,
      reply.status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _Provider extends ShipmentInstantprovider {
  int listRefreshes = 0;

  @override
  Future<void> getShipmentsInstant({bool force = false, int? page}) async {
    listRefreshes++;
  }
}

String _body(bool success, String code, {String en = '', String ar = ''}) =>
    jsonEncode({
      'success': success,
      'code': code,
      'message': en,
      'message_en': en,
      'message_ar': ar,
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeSecureStore store;
  late _Provider provider;
  late _ScriptedAdapter adapter;

  void script(List<_Reply> replies) {
    adapter = _ScriptedAdapter(replies);
    provider.deliveryDioFactory = () => Dio()..httpClientAdapter = adapter;
  }

  setUp(() {
    store =
        _FakeSecureStore()
          ..values['driver_api_key'] = 'b2-test-key'
          ..values['driver_session_id'] = '601';
    SharedPreferences.setMockInitialValues({});
    AuthService.configureForTesting(secureStore: store);
    // Location on and no VPN, so the operational gate lets requests through;
    // R4 covers the blocked case.
    OperationalReadinessProvider.currentState = OperationalReadinessState.ready;
    provider = _Provider();
  });

  tearDown(() {
    OperationalReadinessProvider.currentState =
        OperationalReadinessState.locationUnavailable;
    AuthService.resetForTesting();
  });

  group('eligibility (verified server rule: 4 -> 11)', () {
    test('E1. only in transit (4) offers Delivered', () {
      expect(canMarkDelivered(4), isTrue);
      for (final id in [0, 1, 2, 3, 5, 6, 7, 8, 9, 10, 11]) {
        expect(canMarkDelivered(id), isFalse, reason: 'status $id');
      }
      expect(driverDeliveredStatusId, 11);
    });

    test('E2. the offline flow config no longer advertises 5 -> 6', () {
      final delivered = ShipmentFlowConfig.fallback().actions.firstWhere(
        (action) => action.actionKey == 'delivered',
      );
      expect(delivered.fromStatusIds, [4]);
      expect(delivered.targetStatusId, 11);
      expect(delivered.endpoint, 'complete_shipment_driver.php');
      expect(delivered.requiresConfirmation, isTrue);
      expect(
        ShipmentFlowConfig.fallback().statuses.any((s) => s.id == 11),
        isTrue,
      );
    });
  });

  group('request', () {
    test(
      'R1. posts to complete_shipment_driver.php with the session identity',
      () async {
        script([_Reply(200, _body(true, 'SHIPMENT_COMPLETED'))]);
        await provider.deliverShipment(7001);

        final request = adapter.requests.single;
        expect(request.uri.toString(), AppUrls.completeShipment);
        expect(request.method, 'POST');
        expect(request.headers['X-API-KEY'], 'b2-test-key');
        expect(request.headers['X-Request-ID'], isNotNull);
        final data = request.data as Map;
        expect(data['shipment_id'], 7001);
        // The driver id is the signed-in session's own, never a caller value.
        expect(data['driver_id'], '601');
        expect(data.keys.toSet(), {'shipment_id', 'driver_id'});
      },
    );

    test('R2. no session means no request', () async {
      store.values.clear();
      AuthService.configureForTesting(secureStore: store);
      script([]);
      final result = await provider.deliverShipment(7001);
      expect(result.success, isFalse);
      expect(adapter.requests, isEmpty);
    });

    test('R3. an invalid shipment id sends nothing', () async {
      script([]);
      expect((await provider.deliverShipment(0)).success, isFalse);
      expect((await provider.deliverShipment(null)).success, isFalse);
      expect(adapter.requests, isEmpty);
    });

    test('R4. without location / with a VPN active, nothing is sent', () async {
      script([_Reply(200, _body(true, 'SHIPMENT_COMPLETED'))]);
      OperationalReadinessProvider.currentState =
          OperationalReadinessState.vpnActive;
      final result = await provider.deliverShipment(7001);
      expect(result.success, isFalse);
      expect(result.code, 'DRIVER_NOT_OPERATIONALLY_READY');
      expect(adapter.requests, isEmpty);
      expect(provider.listRefreshes, 0);
    });
  });

  group('server answers', () {
    test(
      'S1. 200 SHIPMENT_COMPLETED is a success and refreshes the list',
      () async {
        script([
          _Reply(200, _body(true, 'SHIPMENT_COMPLETED', en: 'Delivered OK')),
        ]);
        final result = await provider.deliverShipment(7001);
        expect(result.success, isTrue);
        expect(result.code, 'SHIPMENT_COMPLETED');
        expect(result.message, 'Delivered OK');
        expect(provider.listRefreshes, 1);
        expect(provider.isShipmentBusy(7001), isFalse);
      },
    );

    test('S2. 200 ..._ALREADY_PROCESSED (a retry) is a success', () async {
      script([_Reply(200, _body(true, 'SHIPMENT_COMPLETE_ALREADY_PROCESSED'))]);
      expect((await provider.deliverShipment(7001)).success, isTrue);
    });

    test('S3. 409 INVALID_STATUS is a conflict, never a success', () async {
      script([_Reply(409, _body(false, 'INVALID_STATUS'))]);
      final result = await provider.deliverShipment(7001);
      expect(result.success, isFalse);
      expect(result.isStateConflict, isTrue);
      expect(result.httpStatus, 409);
      expect(result.message, contains('status changed'));
      expect(provider.listRefreshes, 0);
    });

    test('S4. 409 SHIPMENT_STATE_CONFLICT (lost race) is a conflict', () async {
      script([_Reply(409, _body(false, 'SHIPMENT_STATE_CONFLICT'))]);
      final result = await provider.deliverShipment(7001);
      expect(result.isStateConflict, isTrue);
    });

    test(
      'S5. a pre-B1 server (HTTP 200 + INVALID_STATUS) is still a conflict',
      () async {
        script([_Reply(200, _body(false, 'INVALID_STATUS'))]);
        final result = await provider.deliverShipment(7001);
        expect(result.success, isFalse);
        expect(result.isStateConflict, isTrue);
      },
    );

    test(
      'S6. 200 with success=false and an unknown code is not a success',
      () async {
        script([_Reply(200, _body(false, 'DB_UPDATE_ERROR'))]);
        expect((await provider.deliverShipment(7001)).success, isFalse);
      },
    );

    test('S7. 403 NOT_ASSIGNED keeps the session and explains', () async {
      final before = UserSessionState.generation;
      script([_Reply(403, _body(false, 'NOT_ASSIGNED'))]);
      final result = await provider.deliverShipment(7001);
      expect(result.success, isFalse);
      expect(result.httpStatus, 403);
      expect(result.message, contains('no longer assigned'));
      expect(UserSessionState.generation, before);
    });

    test('S8. 403 DRIVER_SUBSCRIPTION_INACTIVE keeps the session', () async {
      final before = UserSessionState.generation;
      script([_Reply(403, _body(false, 'DRIVER_SUBSCRIPTION_INACTIVE'))]);
      final result = await provider.deliverShipment(7001);
      expect(result.success, isFalse);
      expect(UserSessionState.generation, before);
    });

    test('S9. 404 SHIPMENT_NOT_FOUND', () async {
      script([_Reply(404, _body(false, 'SHIPMENT_NOT_FOUND'))]);
      final result = await provider.deliverShipment(7001);
      expect(result.success, isFalse);
      expect(result.httpStatus, 404);
    });

    test('S10. 401 ends the session through the shared interceptor', () async {
      final before = UserSessionState.generation;
      script([_Reply(401, _body(false, 'INVALID_DRIVER_AUTH'))]);
      final result = await provider.deliverShipment(7001);
      expect(result.success, isFalse);
      expect(UserSessionState.generation, isNot(before));
    });

    test('S11. 403 DRIVER_INACTIVE ends the session', () async {
      final before = UserSessionState.generation;
      script([_Reply(403, _body(false, 'DRIVER_INACTIVE'))]);
      expect((await provider.deliverShipment(7001)).success, isFalse);
      expect(UserSessionState.generation, isNot(before));
    });

    test('S12. 500 is a failure with a retry hint', () async {
      script([_Reply(500, _body(false, 'DB_UPDATE_ERROR'))]);
      final result = await provider.deliverShipment(7001);
      expect(result.success, isFalse);
      expect(result.isStateConflict, isFalse);
    });

    test('S13. Arabic wording for a conflict', () async {
      script([_Reply(409, _body(false, 'INVALID_STATUS'))]);
      final result = await provider.deliverShipment(7001, languageCode: 'ar');
      expect(result.message, contains('تغيّرت حالة هذه الشحنة'));
    });
  });

  group('retry and concurrency', () {
    test(
      'T1. a timeout is unconfirmed and is not resent automatically',
      () async {
        script([const _Reply.timeout()]);
        final result = await provider.deliverShipment(7001);
        expect(result.success, isFalse);
        expect(result.unconfirmed, isTrue);
        expect(adapter.requests, hasLength(1));
        expect(provider.listRefreshes, 0);
      },
    );

    test('T2. a manual retry after a timeout reuses the request id', () async {
      script([
        const _Reply.timeout(),
        _Reply(200, _body(true, 'SHIPMENT_COMPLETE_ALREADY_PROCESSED')),
      ]);
      await provider.deliverShipment(7001);
      final retry = await provider.deliverShipment(7001);
      expect(retry.success, isTrue);
      expect(
        adapter.requests[1].headers['X-Request-ID'],
        adapter.requests[0].headers['X-Request-ID'],
      );
    });

    test(
      'T3. after a definitive reply, a new attempt gets a new request id',
      () async {
        script([
          _Reply(409, _body(false, 'REQUEST_IN_PROGRESS')),
          _Reply(200, _body(true, 'SHIPMENT_COMPLETED')),
        ]);
        await provider.deliverShipment(7001);
        await provider.deliverShipment(7001);
        expect(
          adapter.requests[1].headers['X-Request-ID'],
          isNot(adapter.requests[0].headers['X-Request-ID']),
        );
      },
    );

    test(
      'T4. a second tap while the first is in flight sends nothing',
      () async {
        final gate = Completer<void>();
        script([_Reply.held(200, _body(true, 'SHIPMENT_COMPLETED'), gate)]);
        final first = provider.deliverShipment(7001);
        await Future<void>.delayed(Duration.zero);
        expect(provider.isShipmentBusy(7001), isTrue);

        final second = await provider.deliverShipment(7001);
        expect(second.success, isFalse);
        expect(second.code, 'REQUEST_IN_PROGRESS');

        gate.complete();
        expect((await first).success, isTrue);
        expect(adapter.requests, hasLength(1));
        expect(provider.isShipmentBusy(7001), isFalse);
      },
    );

    test('T5. a session change while waiting discards the reply', () async {
      final gate = Completer<void>();
      script([_Reply.held(200, _body(true, 'SHIPMENT_COMPLETED'), gate)]);
      final pending = provider.deliverShipment(7001);
      await Future<void>.delayed(Duration.zero);
      UserSessionState.reset(SessionResetReason.accountChanged);
      gate.complete();
      final result = await pending;
      expect(result.success, isFalse);
      expect(result.code, 'SESSION_CHANGED');
    });
  });
}
