// B2 (release blocker RG-11): the "Delivered" request against the isolated
// local STAGING backend (Apache 127.0.0.1:8088, database blockatie_staging).
//
// Opt-in only. Skipped unless B2_STAGING_FIXTURES names a manifest written by
// tools/tests/prepare_b2_delivered_staging_fixtures.php (main repository): a
// fresh block of synthetic drivers and B2-* shipments per run. Run:
//   B2_STAGING_FIXTURES=<manifest> flutter test test/b2_delivered_staging_test.dart \
//     --dart-define=API_BASE_URL=http://127.0.0.1:8088/services
// Before the first request it refuses any base URL other than local staging and
// any server that does not identify itself as staging. Keys are never printed.
// Each run consumes its fixtures (three shipments end at status 11).

import 'dart:convert';
import 'dart:io';

import 'package:blockatie/constants/app_urls.dart';
import 'package:blockatie/provider/operational_readiness.dart';
import 'package:blockatie/provider/shipment_instsnt.dart';
import 'package:blockatie/services/auth_secure_store.dart';
import 'package:blockatie/services/auth_services.dart';
import 'package:blockatie/services/user_session_state.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _stagingBase = 'http://127.0.0.1:8088/services';

class _FakeSecureStore implements AuthSecureStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

class _Provider extends ShipmentInstantprovider {
  int listRefreshes = 0;

  @override
  Future<void> getShipmentsInstant({bool force = false, int? page}) async {
    listRefreshes++;
  }
}

class _Driver {
  _Driver(Map data) : id = data['id'] as int, key = data['key'] as String;

  final int id;
  final String key;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final manifestPath = Platform.environment['B2_STAGING_FIXTURES'] ?? '';
  final skip =
      manifestPath.isEmpty
          ? 'B2_STAGING_FIXTURES is not set (opt-in staging contract test)'
          : null;

  late Map<String, _Driver> drivers;
  late Map<String, int> shipments;
  late int missingShipment;
  late Dio raw;
  var stamp = 0;

  String requestId(String label) =>
      'b2-stg-$label-${DateTime.now().microsecondsSinceEpoch}-${stamp++}';

  Future<Response<dynamic>> post(
    int shipmentId,
    int driverId, {
    String? key,
    String? id,
  }) {
    return raw.post(
      AppUrls.completeShipment,
      data: {'shipment_id': '$shipmentId', 'driver_id': '$driverId'},
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        headers: {
          'Accept': 'application/json',
          if (key != null) 'X-API-KEY': key,
          if (id != null) 'X-Request-ID': id,
        },
      ),
    );
  }

  String? codeOf(Response<dynamic> response) {
    final data =
        response.data is String
            ? jsonDecode(response.data as String)
            : response.data;
    return data is Map ? data['code']?.toString() : null;
  }

  late _FakeSecureStore store;
  late _Provider provider;

  void signIn(String role, {String? keyOf}) {
    store =
        _FakeSecureStore()
          ..values['driver_api_key'] = drivers[keyOf ?? role]!.key
          ..values['driver_session_id'] = '${drivers[role]!.id}';
    AuthService.configureForTesting(secureStore: store);
    provider = _Provider();
  }

  setUpAll(() async {
    if (skip != null) return;
    // flutter_test answers every real HTTP request with 400; this test needs
    // the real loopback staging server.
    HttpOverrides.global = null;
    expect(
      AppUrls.baseUrl,
      _stagingBase,
      reason: 'refusing to run against anything but local staging',
    );
    final manifest =
        jsonDecode(File(manifestPath).readAsStringSync())
            as Map<String, dynamic>;
    drivers = {
      for (final entry in (manifest['drivers'] as Map).entries)
        entry.key as String: _Driver(entry.value as Map),
    };
    shipments = Map<String, int>.from(manifest['shipments'] as Map);
    missingShipment = manifest['missing_shipment'] as int;
    raw = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        validateStatus: (_) => true,
      ),
    );
    final probe = await raw.get(AppUrls.completeShipment);
    expect(
      probe.headers.value('x-blockatie-environment'),
      'staging',
      reason: 'the server must identify itself as staging',
    );
  });

  setUp(() {
    if (skip != null) return;
    SharedPreferences.setMockInitialValues({});
    OperationalReadinessProvider.currentState = OperationalReadinessState.ready;
  });

  tearDown(() {
    OperationalReadinessProvider.currentState =
        OperationalReadinessState.locationUnavailable;
    AuthService.resetForTesting();
  });

  test(
    'ST1. the app delivers an eligible shipment (4 -> 11); a second tap later is a conflict',
    () async {
      signIn('active');
      final shipment = shipments['deliver_app']!;
      final first = await provider.deliverShipment(shipment);
      expect(first.success, isTrue, reason: first.message);
      expect(first.code, 'SHIPMENT_COMPLETED');
      expect(first.httpStatus, 200);
      expect(provider.listRefreshes, 1);

      final again = await provider.deliverShipment(shipment);
      expect(again.success, isFalse);
      expect(again.httpStatus, 409);
      expect(again.code, 'INVALID_STATUS');
      expect(again.isStateConflict, isTrue);
    },
    skip: skip,
  );

  test(
    'ST2. a replayed request id is answered ALREADY_PROCESSED, a new id is 409',
    () async {
      final driver = drivers['active']!;
      final shipment = shipments['replay']!;
      final id = requestId('replay');
      final first = await post(shipment, driver.id, key: driver.key, id: id);
      expect(first.statusCode, 200);
      expect(codeOf(first), 'SHIPMENT_COMPLETED');

      final replay = await post(shipment, driver.id, key: driver.key, id: id);
      expect(replay.statusCode, 200);
      expect(codeOf(replay), 'SHIPMENT_COMPLETE_ALREADY_PROCESSED');

      final fresh = await post(
        shipment,
        driver.id,
        key: driver.key,
        id: requestId('fresh'),
      );
      expect(fresh.statusCode, 409);
      expect(codeOf(fresh), 'INVALID_STATUS');
    },
    skip: skip,
  );

  test(
    'ST3. not picked up (2), cancelled (7) and returned (8) are 409 conflicts',
    () async {
      signIn('active');
      for (final purpose in ['not_picked_up', 'cancelled', 'returned']) {
        final result = await provider.deliverShipment(shipments[purpose]);
        expect(result.success, isFalse, reason: purpose);
        expect(result.httpStatus, 409, reason: purpose);
        expect(result.code, 'INVALID_STATUS', reason: purpose);
        expect(result.isStateConflict, isTrue, reason: purpose);
      }
      expect(provider.listRefreshes, 0);
    },
    skip: skip,
  );

  test(
    'ST4. another driver\'s shipment is 403 NOT_ASSIGNED and keeps the session',
    () async {
      signIn('active');
      final generation = UserSessionState.generation;
      final result = await provider.deliverShipment(shipments['other_driver']);
      expect(result.success, isFalse);
      expect(result.httpStatus, 403);
      expect(result.code, 'NOT_ASSIGNED');
      expect(UserSessionState.generation, generation);
      expect(store.values['driver_api_key'], isNotNull);
    },
    skip: skip,
  );

  test('ST5. an inactive subscription is 403 and keeps the session', () async {
    signIn('unsubscribed');
    final generation = UserSessionState.generation;
    final result = await provider.deliverShipment(
      shipments['unsubscribed_driver'],
    );
    expect(result.success, isFalse);
    expect(result.httpStatus, 403);
    expect(result.code, 'DRIVER_SUBSCRIPTION_INACTIVE');
    expect(UserSessionState.generation, generation);
  }, skip: skip);

  test('ST6. an unknown shipment is 404 SHIPMENT_NOT_FOUND', () async {
    signIn('active');
    final result = await provider.deliverShipment(missingShipment);
    expect(result.success, isFalse);
    expect(result.httpStatus, 404);
    expect(result.code, 'SHIPMENT_NOT_FOUND');
  }, skip: skip);

  test(
    'ST7. two different request ids at once: exactly one delivery wins',
    () async {
      final driver = drivers['active']!;
      final shipment = shipments['race']!;
      final replies = await Future.wait([
        post(shipment, driver.id, key: driver.key, id: requestId('race-a')),
        post(shipment, driver.id, key: driver.key, id: requestId('race-b')),
      ]);
      final completed =
          replies
              .where(
                (r) => r.statusCode == 200 && codeOf(r) == 'SHIPMENT_COMPLETED',
              )
              .length;
      final conflicts =
          replies
              .where(
                (r) =>
                    r.statusCode == 409 &&
                    {
                      'INVALID_STATUS',
                      'SHIPMENT_STATE_CONFLICT',
                    }.contains(codeOf(r)),
              )
              .length;
      expect(completed, 1, reason: replies.map(codeOf).join(', '));
      expect(conflicts, 1, reason: replies.map(codeOf).join(', '));
    },
    skip: skip,
  );

  test(
    'ST8. no key is 401 API_KEY_MISSING; a key of another driver ends the session',
    () async {
      final other = drivers['other']!;
      final missing = await post(shipments['other_driver']!, other.id);
      expect(missing.statusCode, 401);
      expect(codeOf(missing), 'API_KEY_MISSING');

      // The active driver's session presenting the other driver's key: the
      // server binds the key to the driver id, so this is 401 and the app
      // signs out instead of reporting a delivery.
      signIn('active', keyOf: 'other');
      final generation = UserSessionState.generation;
      final result = await provider.deliverShipment(shipments['other_driver']);
      expect(result.success, isFalse);
      expect(result.code, 'SESSION_CHANGED');
      expect(UserSessionState.generation, isNot(generation));
    },
    skip: skip,
  );
}
