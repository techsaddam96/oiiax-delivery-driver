import 'dart:async';
import 'dart:io';

import 'package:blockatie/provider/driver_work_session.dart';
import 'package:blockatie/provider/order_location.dart';
import 'package:blockatie/services/auth_secure_store.dart';
import 'package:blockatie/services/auth_services.dart';
import 'package:blockatie/services/driver_work_session_service.dart';
import 'package:blockatie/services/user_session_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemorySecureStore implements AuthSecureStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

class _FakeTransport implements DriverWorkSessionTransport {
  final List<DriverWorkSessionRemoteResult> starts = [];
  final List<DriverWorkSessionRemoteResult> ends = [];
  final List<DriverWorkSessionRemoteResult> statuses = [];
  int startCalls = 0;
  int endCalls = 0;
  int statusCalls = 0;

  @override
  Future<DriverWorkSessionRemoteResult> end(
    String apiKey,
    String capability, {
    required String reason,
  }) async {
    endCalls++;
    return ends.removeAt(0);
  }

  @override
  Future<DriverWorkSessionRemoteResult> start(String apiKey) async {
    startCalls++;
    return starts.removeAt(0);
  }

  @override
  Future<DriverWorkSessionRemoteResult> status(
    String apiKey,
    String capability,
  ) async {
    statusCalls++;
    return statuses.removeAt(0);
  }
}

class _DelayedStartTransport extends _FakeTransport {
  final Completer<DriverWorkSessionRemoteResult> startCompleter =
      Completer<DriverWorkSessionRemoteResult>();

  @override
  Future<DriverWorkSessionRemoteResult> start(String apiKey) {
    startCalls++;
    return startCompleter.future;
  }
}

class _LocationDouble extends OrderLocationProvider {
  bool tracking = false;
  bool verified = false;
  int startCalls = 0;
  int stopCalls = 0;
  String? capability;
  String? owner;

  @override
  bool get hasVerifiedWorkSession => verified;

  @override
  bool get isTracking => tracking;

  @override
  void activateVerifiedWorkSession({
    required String capability,
    required String driverId,
    required int sessionGeneration,
  }) {
    verified = true;
    this.capability = capability;
    owner = driverId;
  }

  @override
  void clearVerifiedWorkSession() {
    verified = false;
    capability = null;
    owner = null;
  }

  @override
  Future<void> startDriverLocationUpdates({
    BuildContext? context,
    bool allowLegacyFallback = false,
  }) async {
    startCalls++;
    tracking = true;
  }

  @override
  void stopDriverLocationUpdates({bool notify = true}) {
    stopCalls++;
    tracking = false;
  }
}

const _keyA =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _keyB =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MemorySecureStore store;

  Future<void> saveDriver(String id) =>
      AuthService.saveDriverSession(apiKey: 'api-$id', id: id);

  setUp(() async {
    store = _MemorySecureStore();
    SharedPreferences.setMockInitialValues({});
    AuthService.configureForTesting(secureStore: store);
    await saveDriver('101');
  });

  tearDown(AuthService.resetForTesting);

  DriverWorkSessionProvider provider(
    DriverWorkSessionTransport transport,
    _LocationDouble location,
  ) {
    final value = DriverWorkSessionProvider(
      transport: transport,
      enabled: true,
    );
    value.bindLocationProvider(location);
    return value;
  }

  test('Start Work persists a capability only in encrypted storage', () async {
    final transport =
        _FakeTransport()
          ..starts.add(
            const DriverWorkSessionRemoteResult(
              DriverWorkSessionRemoteState.started,
              capability: _keyA,
            ),
          );
    final location = _LocationDouble();
    final work = provider(transport, location);

    await work.startWork();

    expect(work.state, DriverWorkSessionState.active);
    expect(location.tracking, isTrue);
    expect(location.capability, _keyA);
    expect(store.values['driver_work_session_capability'], _keyA);
    expect(store.values['driver_work_session_driver_id'], '101');
    expect(store.values['driver_work_session_end_pending'], isNull);
    work.dispose();
  });

  test(
    'a new Start Work response atomically replaces the local capability',
    () async {
      final transport =
          _FakeTransport()
            ..starts.addAll(const [
              DriverWorkSessionRemoteResult(
                DriverWorkSessionRemoteState.started,
                capability: _keyA,
              ),
              DriverWorkSessionRemoteResult(
                DriverWorkSessionRemoteState.started,
                capability: _keyB,
              ),
            ]);
      final work = provider(transport, _LocationDouble());

      await work.startWork();
      await work.startWork();

      expect(transport.startCalls, 2);
      expect(store.values['driver_work_session_capability'], _keyB);
      expect(store.values.containsValue(_keyA), isFalse);
      work.dispose();
    },
  );

  test('restart requires server status before showing active work', () async {
    final firstTransport =
        _FakeTransport()
          ..starts.add(
            const DriverWorkSessionRemoteResult(
              DriverWorkSessionRemoteState.started,
              capability: _keyA,
            ),
          );
    final first = provider(firstTransport, _LocationDouble());
    await first.startWork();
    first.dispose();

    final restoredTransport =
        _FakeTransport()
          ..statuses.add(
            const DriverWorkSessionRemoteResult(
              DriverWorkSessionRemoteState.active,
            ),
          );
    final restoredLocation = _LocationDouble();
    final restored = provider(restoredTransport, restoredLocation);

    expect(restored.isActive, isFalse);
    await restored.restoreWorkSessionIfActive();

    expect(restoredTransport.statusCalls, 1);
    expect(restored.state, DriverWorkSessionState.active);
    expect(restoredLocation.tracking, isTrue);
    restored.dispose();
  });

  test(
    'account replacement removes a capability bound to the prior driver',
    () async {
      final transport =
          _FakeTransport()
            ..starts.add(
              const DriverWorkSessionRemoteResult(
                DriverWorkSessionRemoteState.started,
                capability: _keyA,
              ),
            );
      final work = provider(transport, _LocationDouble());
      await work.startWork();

      AuthService.resetAccountStateOnly(SessionResetReason.accountChanged);
      await saveDriver('202');

      final secret = await AuthService.getWorkSessionSecret(
        expectedGeneration: UserSessionState.generation,
      );
      expect(secret, isNull);
      expect(work.state, DriverWorkSessionState.inactive);
      work.dispose();
    },
  );

  test('API-key rotation invalidates the current work capability', () async {
    await AuthService.saveWorkSessionSecret(
      capability: _keyA,
      driverId: '101',
      expectedGeneration: UserSessionState.generation,
    );

    await AuthService.replaceApiKey(
      'api-101-rotated',
      expectedGeneration: UserSessionState.generation,
    );

    expect(store.values['driver_api_key'], 'api-101-rotated');
    expect(store.values['driver_work_session_capability'], isNull);
  });

  test(
    'offline End Work stops tracking and persists only a pending revocation',
    () async {
      final transport =
          _FakeTransport()
            ..starts.add(
              const DriverWorkSessionRemoteResult(
                DriverWorkSessionRemoteState.started,
                capability: _keyA,
              ),
            )
            ..ends.add(
              const DriverWorkSessionRemoteResult(
                DriverWorkSessionRemoteState.unavailable,
              ),
            );
      final location = _LocationDouble();
      final work = provider(transport, location);
      await work.startWork();

      await work.endWork();

      expect(work.state, DriverWorkSessionState.pendingEnd);
      expect(location.tracking, isFalse);
      expect(store.values['driver_work_session_end_pending'], '1');
      work.dispose();
    },
  );

  test(
    'a pending End Work retries on restart and never reactivates tracking',
    () async {
      await AuthService.saveWorkSessionSecret(
        capability: _keyA,
        driverId: '101',
        expectedGeneration: UserSessionState.generation,
      );
      await AuthService.markWorkSessionEndPending(
        capability: _keyA,
        driverId: '101',
        expectedGeneration: UserSessionState.generation,
      );
      final transport =
          _FakeTransport()
            ..ends.add(
              const DriverWorkSessionRemoteResult(
                DriverWorkSessionRemoteState.ended,
              ),
            );
      final location = _LocationDouble();
      final work = provider(transport, location);

      await work.restoreWorkSessionIfActive();

      expect(transport.endCalls, 1);
      expect(work.state, DriverWorkSessionState.inactive);
      expect(location.tracking, isFalse);
      expect(store.values['driver_work_session_capability'], isNull);
      work.dispose();
    },
  );

  test(
    'logout attempts End Work without retaining a local capability',
    () async {
      await AuthService.saveWorkSessionSecret(
        capability: _keyA,
        driverId: '101',
        expectedGeneration: UserSessionState.generation,
      );
      final transport =
          _FakeTransport()
            ..ends.add(
              const DriverWorkSessionRemoteResult(
                DriverWorkSessionRemoteState.ended,
              ),
            );
      final location = _LocationDouble();
      final work = provider(transport, location);

      await work.stopForLogout();
      await AuthService.clearSession();

      expect(transport.endCalls, 1);
      expect(work.state, DriverWorkSessionState.inactive);
      expect(location.tracking, isFalse);
      expect(store.values['driver_work_session_capability'], isNull);
      work.dispose();
    },
  );

  test(
    'active work detaches End Work from the local logout boundary',
    () async {
      final transport =
          _FakeTransport()
            ..starts.add(
              const DriverWorkSessionRemoteResult(
                DriverWorkSessionRemoteState.started,
                capability: _keyA,
              ),
            )
            ..ends.add(
              const DriverWorkSessionRemoteResult(
                DriverWorkSessionRemoteState.ended,
              ),
            );
      final location = _LocationDouble();
      final work = provider(transport, location);

      await work.startWork();
      expect(work.canStopForLogoutImmediately, isTrue);

      // No secure-store lookup or server response is awaited here. The old
      // authenticated context is captured before AuthService clears it.
      work.stopForLogoutImmediately();
      await AuthService.clearSession();

      expect(transport.endCalls, 1);
      expect(location.tracking, isFalse);
      expect(work.state, DriverWorkSessionState.inactive);
      expect((await AuthService.getSessionSnapshot()).isAuthenticated, isFalse);
      work.dispose();
    },
  );

  test(
    'an expired server capability is cleared and cannot look active',
    () async {
      await AuthService.saveWorkSessionSecret(
        capability: _keyA,
        driverId: '101',
        expectedGeneration: UserSessionState.generation,
      );
      final transport =
          _FakeTransport()
            ..statuses.add(
              const DriverWorkSessionRemoteResult(
                DriverWorkSessionRemoteState.inactive,
              ),
            );
      final work = provider(transport, _LocationDouble());

      await work.restoreWorkSessionIfActive();

      expect(work.state, DriverWorkSessionState.expired);
      expect(store.values['driver_work_session_capability'], isNull);
      work.dispose();
    },
  );

  test(
    'a delayed Start Work response cannot recreate a cleared session',
    () async {
      final transport = _DelayedStartTransport();
      final work = provider(transport, _LocationDouble());

      final start = work.startWork();
      await Future<void>.delayed(Duration.zero);
      await AuthService.clearSession();
      transport.startCompleter.complete(
        const DriverWorkSessionRemoteResult(
          DriverWorkSessionRemoteState.started,
          capability: _keyA,
        ),
      );
      await start;

      expect(store.values['driver_work_session_capability'], isNull);
      expect(work.isActive, isFalse);
      work.dispose();
    },
  );

  test(
    'disabled opt-in does not claim active v2 work and uses legacy only after tap',
    () async {
      final transport =
          _FakeTransport()
            ..starts.add(
              const DriverWorkSessionRemoteResult(
                DriverWorkSessionRemoteState.disabled,
              ),
            );
      final location = _LocationDouble();
      final work = provider(transport, location);

      await work.startWork();

      expect(work.isActive, isFalse);
      expect(work.state, DriverWorkSessionState.legacyTracking);
      expect(location.startCalls, 1);
      expect(location.verified, isFalse);
      work.dispose();
    },
  );

  test(
    'logout clears the capability before any detached network cleanup',
    () async {
      await AuthService.saveWorkSessionSecret(
        capability: _keyA,
        driverId: '101',
        expectedGeneration: UserSessionState.generation,
      );

      await AuthService.clearSession();

      expect(store.values['driver_work_session_capability'], isNull);
      expect(store.values['driver_work_session_driver_id'], isNull);
      expect(store.values['driver_work_session_end_pending'], isNull);
      expect((await AuthService.getSessionSnapshot()).isAuthenticated, isFalse);
    },
  );

  test('a disabled client build cannot create a v2 session', () async {
    final transport = _FakeTransport();
    final work = DriverWorkSessionProvider(transport: transport, enabled: false)
      ..bindLocationProvider(_LocationDouble());

    await work.startWork();

    expect(transport.startCalls, 0);
    expect(work.isActive, isFalse);
    expect(store.values['driver_work_session_capability'], isNull);
    work.dispose();
  });

  test(
    'location writer has verified GPS fields and does not enroll arrival',
    () {
      final writer =
          File('lib/provider/order_location.dart').readAsStringSync();
      final instant =
          File('lib/provider/shipment_instsnt.dart').readAsStringSync();

      expect(
        writer,
        contains("'accuracy_meters': locationAccuracyMeters!.toString()"),
      );
      expect(writer, contains("'measured_at_ms':"));
      expect(
        writer,
        contains("'X-DRIVER-WORK-SESSION': workSessionCapability"),
      );
      expect(writer, contains('accuracyMeters > 100'));
      expect(writer, contains('const Duration(seconds: 120)'));
      expect(writer, contains('const Duration(seconds: -60)'));
      expect(instant, isNot(contains('X-DRIVER-WORK-SESSION')));
    },
  );
}
