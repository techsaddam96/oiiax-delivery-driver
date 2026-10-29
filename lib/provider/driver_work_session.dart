import 'dart:async';

import 'package:blockatie/constants/app_urls.dart';
import 'package:blockatie/provider/order_location.dart';
import 'package:blockatie/services/auth_services.dart';
import 'package:blockatie/services/driver_work_session_service.dart';
import 'package:blockatie/services/user_session_state.dart';

/// UI state for the optional secure work-session protocol. `active` means the
/// server confirmed the capability during this process; it is never restored
/// merely because a raw capability exists in secure storage.
enum DriverWorkSessionState {
  inactive,
  starting,
  active,
  ending,
  pendingEnd,
  disabled,
  unavailable,
  expired,
  locationUnavailable,
  legacyTracking,
}

class DriverWorkSessionProvider extends UserScopedNotifier {
  DriverWorkSessionProvider({
    DriverWorkSessionTransport? transport,
    bool? enabled,
  }) : _transport = transport ?? DioDriverWorkSessionTransport(),
       _enabled = enabled ?? AppUrls.driverWorkSessionsEnabled {
    AuthService.workSessionInvalidations.addListener(
      _onStoredSecretInvalidated,
    );
  }

  final DriverWorkSessionTransport _transport;
  final bool _enabled;
  OrderLocationProvider? _location;
  DriverWorkSessionState _state = DriverWorkSessionState.inactive;
  int _operation = 0;
  DriverWorkSessionSecret? _activeSecret;

  bool get isEnabled => _enabled;
  DriverWorkSessionState get state => _state;
  bool get isActive => _state == DriverWorkSessionState.active;
  bool get isBusy =>
      _state == DriverWorkSessionState.starting ||
      _state == DriverWorkSessionState.ending;

  /// The normal active-work path already has both pieces of server context in
  /// memory. It can stop GPS and dispatch End Work without blocking logout on
  /// another secure-storage read. A restored-but-not-yet-confirmed capability
  /// intentionally uses [stopForLogout]'s conservative fallback instead.
  bool get canStopForLogoutImmediately {
    if (!_enabled) return true;
    final session = AuthService.cachedSessionForTeardown;
    final secret = _activeSecret;
    return _state == DriverWorkSessionState.active &&
        session != null &&
        secret != null &&
        session.driverId == secret.driverId &&
        session.apiKey != null &&
        session.apiKey!.isNotEmpty;
  }

  void bindLocationProvider(OrderLocationProvider location) {
    if (identical(_location, location)) return;
    _location?.bindWorkSessionRejectionListener(null);
    _location = location;
    location.bindWorkSessionRejectionListener(_handleLocationSessionRejected);
  }

  void _set(DriverWorkSessionState value, int generation) {
    if (!UserSessionState.isCurrent(generation)) return;
    _state = value;
    notifyListeners();
  }

  bool _isCurrent(int generation, int operation) =>
      UserSessionState.isCurrent(generation) && operation == _operation;

  /// Restores only server-confirmed capability state. A cold start without a
  /// network response is intentionally inactive, even if secure storage still
  /// holds a valid-looking key.
  Future<void> restoreWorkSessionIfActive() async {
    if (!_enabled || isBusy) return;
    final location = _location;
    if (location == null) return;
    final generation = UserSessionState.generation;
    final operation = ++_operation;
    final session = await AuthService.getSessionSnapshot();
    if (!_isCurrent(generation, operation) || !session.isAuthenticated) return;

    final secret = await AuthService.getWorkSessionSecret(
      expectedGeneration: generation,
    );
    if (!_isCurrent(generation, operation) || secret == null) {
      if (_isCurrent(generation, operation)) {
        _set(DriverWorkSessionState.inactive, generation);
      }
      return;
    }
    _activeSecret = secret;

    if (secret.endPending) {
      _set(DriverWorkSessionState.pendingEnd, generation);
      await _finishPendingEnd(session, secret, generation, operation);
      return;
    }

    _set(DriverWorkSessionState.starting, generation);
    final remote = await _transport.status(session.apiKey!, secret.capability);
    if (!_isCurrent(generation, operation)) return;
    if (remote.state == DriverWorkSessionRemoteState.active) {
      location.activateVerifiedWorkSession(
        capability: secret.capability,
        driverId: session.driverId!,
        sessionGeneration: generation,
      );
      await location.startDriverLocationUpdates();
      if (!_isCurrent(generation, operation)) return;
      if (location.isTracking) {
        _set(DriverWorkSessionState.active, generation);
      } else {
        await _endAfterLocalStartFailure(
          session,
          secret,
          generation,
          operation,
        );
      }
      return;
    }

    location.clearVerifiedWorkSession();
    if (remote.state == DriverWorkSessionRemoteState.inactive) {
      await AuthService.clearWorkSessionSecret(
        expectedGeneration: generation,
        driverId: session.driverId,
      );
      _activeSecret = null;
      _set(DriverWorkSessionState.expired, generation);
    } else if (remote.mayUseLegacyLocationFlow ||
        remote.state == DriverWorkSessionRemoteState.failed) {
      _set(
        remote.state == DriverWorkSessionRemoteState.disabled
            ? DriverWorkSessionState.disabled
            : DriverWorkSessionState.unavailable,
        generation,
      );
    } else {
      _set(DriverWorkSessionState.inactive, generation);
    }
  }

  /// Explicit driver consent is the only path that creates a capability. A
  /// disabled/unavailable Batch 2A endpoint falls back to the established
  /// location workflow, but never reports a live v2 work session.
  Future<void> startWork() async {
    if (!_enabled || isBusy) return;
    final location = _location;
    if (location == null) return;
    final generation = UserSessionState.generation;
    final operation = ++_operation;

    if (_state == DriverWorkSessionState.pendingEnd) {
      await restoreWorkSessionIfActive();
      return;
    }

    _set(DriverWorkSessionState.starting, generation);
    final session = await AuthService.getSessionSnapshot();
    if (!_isCurrent(generation, operation) || !session.isAuthenticated) {
      _set(DriverWorkSessionState.inactive, generation);
      return;
    }

    final remote = await _transport.start(session.apiKey!);
    if (!_isCurrent(generation, operation)) return;
    if (remote.state == DriverWorkSessionRemoteState.started &&
        remote.capability != null) {
      final stored = await AuthService.saveWorkSessionSecret(
        capability: remote.capability!,
        driverId: session.driverId!,
        expectedGeneration: generation,
      );
      if (!_isCurrent(generation, operation)) return;
      if (!stored) {
        // The raw key must never be used if it could not be kept in the
        // platform keystore. Best-effort End Work avoids a needless server row.
        await _transport.end(
          session.apiKey!,
          remote.capability!,
          reason: 'secure_storage_unavailable',
        );
        _set(DriverWorkSessionState.unavailable, generation);
        return;
      }

      _activeSecret = DriverWorkSessionSecret(
        capability: remote.capability!,
        driverId: session.driverId!,
        endPending: false,
      );

      location.activateVerifiedWorkSession(
        capability: remote.capability!,
        driverId: session.driverId!,
        sessionGeneration: generation,
      );
      await location.startDriverLocationUpdates();
      if (!_isCurrent(generation, operation)) return;
      if (location.isTracking) {
        _set(DriverWorkSessionState.active, generation);
      } else {
        final secret = await AuthService.getWorkSessionSecret(
          expectedGeneration: generation,
        );
        if (secret != null && _isCurrent(generation, operation)) {
          await _endAfterLocalStartFailure(
            session,
            secret,
            generation,
            operation,
          );
        }
      }
      return;
    }

    location.clearVerifiedWorkSession();
    if (remote.mayUseLegacyLocationFlow) {
      // This remains a legacy location state, not a v2 work state. It starts
      // only in response to the driver's explicit tap.
      await location.startDriverLocationUpdates(allowLegacyFallback: true);
      if (!_isCurrent(generation, operation)) return;
      _set(
        location.isTracking
            ? DriverWorkSessionState.legacyTracking
            : (remote.state == DriverWorkSessionRemoteState.disabled
                ? DriverWorkSessionState.disabled
                : DriverWorkSessionState.unavailable),
        generation,
      );
      return;
    }

    _set(
      remote.state == DriverWorkSessionRemoteState.unauthorized
          ? DriverWorkSessionState.inactive
          : DriverWorkSessionState.unavailable,
      generation,
    );
  }

  /// End Work stops local location sharing first. On an offline failure the
  /// encrypted capability is retained only as a pending revocation; it cannot
  /// reactivate tracking or create a new server session.
  Future<void> endWork({String reason = 'ended_by_driver'}) async {
    if (!_enabled || _state == DriverWorkSessionState.ending) return;
    final location = _location;
    final generation = UserSessionState.generation;
    final operation = ++_operation;
    _set(DriverWorkSessionState.ending, generation);
    location?.clearVerifiedWorkSession();
    location?.stopDriverLocationUpdates(notify: false);

    final session = await AuthService.getSessionSnapshot();
    final secret = await AuthService.getWorkSessionSecret(
      expectedGeneration: generation,
    );
    if (!_isCurrent(generation, operation)) return;
    if (!session.isAuthenticated || secret == null) {
      _activeSecret = null;
      _set(DriverWorkSessionState.inactive, generation);
      return;
    }
    _activeSecret = secret;

    final marked = await AuthService.markWorkSessionEndPending(
      capability: secret.capability,
      driverId: session.driverId!,
      expectedGeneration: generation,
    );
    if (!_isCurrent(generation, operation)) return;
    if (!marked) {
      await AuthService.clearWorkSessionSecret(
        expectedGeneration: generation,
        driverId: session.driverId,
      );
      _activeSecret = null;
      _set(DriverWorkSessionState.inactive, generation);
      return;
    }

    await _finishPendingEnd(
      session,
      DriverWorkSessionSecret(
        capability: secret.capability,
        driverId: secret.driverId,
        endPending: true,
      ),
      generation,
      operation,
      reason: reason,
    );
  }

  /// Stops local tracking and submits End Work from context captured during an
  /// already-confirmed active session. This is intentionally synchronous from
  /// the UI's perspective: the transport is still attempted, but logout never
  /// waits for a network request or a redundant secure-storage read.
  void stopForLogoutImmediately() {
    if (!canStopForLogoutImmediately) return;
    if (!_enabled) return;

    final generation = UserSessionState.generation;
    final operation = ++_operation;
    final session = AuthService.cachedSessionForTeardown;
    final secret = _activeSecret;
    _activeSecret = null;
    _location?.clearVerifiedWorkSession();
    _location?.stopDriverLocationUpdates(notify: false);
    _set(DriverWorkSessionState.inactive, generation);

    if (session == null ||
        secret == null ||
        !_isCurrent(generation, operation)) {
      return;
    }
    unawaited(
      _transport.end(session.apiKey!, secret.capability, reason: 'logout'),
    );
  }

  /// Conservative fallback for a capability that has not been captured in
  /// memory yet. Callers use it before clearing credentials, so End Work still
  /// receives its server capability after a cold restart.
  Future<void> stopForLogout() async {
    if (canStopForLogoutImmediately) {
      stopForLogoutImmediately();
      return;
    }
    if (!_enabled) return;
    final generation = UserSessionState.generation;
    final operation = ++_operation;
    _location?.clearVerifiedWorkSession();
    _location?.stopDriverLocationUpdates(notify: false);
    _set(DriverWorkSessionState.inactive, generation);

    final session = await AuthService.getSessionSnapshot();
    final secret = await AuthService.getWorkSessionSecret(
      expectedGeneration: generation,
    );
    if (!_isCurrent(generation, operation) ||
        !session.isAuthenticated ||
        secret == null) {
      return;
    }
    _activeSecret = null;
    unawaited(
      _transport.end(session.apiKey!, secret.capability, reason: 'logout'),
    );
  }

  Future<void> _endAfterLocalStartFailure(
    DriverSession session,
    DriverWorkSessionSecret secret,
    int generation,
    int operation,
  ) async {
    final location = _location;
    location?.clearVerifiedWorkSession();
    location?.stopDriverLocationUpdates(notify: false);
    final marked = await AuthService.markWorkSessionEndPending(
      capability: secret.capability,
      driverId: session.driverId!,
      expectedGeneration: generation,
    );
    if (!_isCurrent(generation, operation)) return;
    if (!marked) {
      await AuthService.clearWorkSessionSecret(
        expectedGeneration: generation,
        driverId: session.driverId,
      );
      _set(DriverWorkSessionState.locationUnavailable, generation);
      return;
    }
    _set(DriverWorkSessionState.pendingEnd, generation);
    await _finishPendingEnd(session, secret, generation, operation);
  }

  Future<void> _finishPendingEnd(
    DriverSession session,
    DriverWorkSessionSecret secret,
    int generation,
    int operation, {
    String reason = 'ended_by_driver',
  }) async {
    _location?.clearVerifiedWorkSession();
    _location?.stopDriverLocationUpdates(notify: false);
    final remote = await _transport.end(
      session.apiKey!,
      secret.capability,
      reason: reason,
    );
    if (!_isCurrent(generation, operation)) return;
    if (remote.terminalEnd) {
      await AuthService.clearWorkSessionSecret(
        expectedGeneration: generation,
        driverId: session.driverId,
      );
      _activeSecret = null;
      _set(DriverWorkSessionState.inactive, generation);
    } else {
      _set(DriverWorkSessionState.pendingEnd, generation);
    }
  }

  Future<void> _handleLocationSessionRejected(
    int sessionGeneration,
    String code,
  ) async {
    if (!_enabled || !UserSessionState.isCurrent(sessionGeneration)) return;
    final generation = UserSessionState.generation;
    _operation++;
    _activeSecret = null;
    _location?.clearVerifiedWorkSession();
    _location?.stopDriverLocationUpdates(notify: false);
    await AuthService.clearWorkSessionSecret(
      expectedGeneration: sessionGeneration,
    );
    if (!UserSessionState.isCurrent(generation) ||
        !UserSessionState.isCurrent(sessionGeneration)) {
      return;
    }
    _state = DriverWorkSessionState.expired;
    notifyListeners();
  }

  void _onStoredSecretInvalidated() {
    if (_state == DriverWorkSessionState.inactive &&
        _location?.hasVerifiedWorkSession != true) {
      return;
    }
    _operation++;
    _activeSecret = null;
    _location?.clearVerifiedWorkSession();
    _location?.stopDriverLocationUpdates(notify: false);
    _state = DriverWorkSessionState.inactive;
    notifyListeners();
  }

  @override
  void clearUserState() {
    _operation++;
    _activeSecret = null;
    _location?.clearVerifiedWorkSession();
    _state = DriverWorkSessionState.inactive;
  }

  @override
  void dispose() {
    AuthService.workSessionInvalidations.removeListener(
      _onStoredSecretInvalidated,
    );
    _location?.bindWorkSessionRejectionListener(null);
    super.dispose();
  }
}
