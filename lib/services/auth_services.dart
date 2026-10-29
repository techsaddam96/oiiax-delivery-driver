// lib/services/auth_service.dart

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/notification_system.dart';
import '../utils/session_redirect.dart';
import 'auth_secure_store.dart';
import 'driver_fcm_token_service.dart';
import 'request_id_service.dart';
import 'user_session_state.dart';

class DriverSession {
  const DriverSession({this.apiKey, this.driverId, this.fcmBinding});

  final String? apiKey;
  final String? driverId;
  final String? fcmBinding;

  bool get isAuthenticated =>
      apiKey != null &&
      apiKey!.trim().isNotEmpty &&
      driverId != null &&
      driverId!.trim().isNotEmpty;
}

/// An opaque server-issued capability stored only in the platform keystore.
///
/// This intentionally has no `isWorking` flag: only a fresh server status
/// response can establish that state after an app restart.
class DriverWorkSessionSecret {
  const DriverWorkSessionSecret({
    required this.capability,
    required this.driverId,
    required this.endPending,
  });

  final String capability;
  final String driverId;
  final bool endPending;
}

/// The completed local logout boundary. Calling [startDetachedCleanup] is safe
/// only after the caller has sent the user to Login; it never changes the
/// current Flutter session and is bounded by [AuthService].
class LogoutResult {
  LogoutResult._(this._context, this.storageCleared);

  final _LogoutContext? _context;
  final bool storageCleared;
  bool _cleanupStarted = false;

  void startDetachedCleanup() {
    if (_cleanupStarted) return;
    _cleanupStarted = true;
    final context = _context;
    if (context != null) AuthService._startDetachedCleanup(context);
  }

  void recordLoginNavigation() {
    final context = _context;
    if (context != null) {
      AuthService._debugTiming(
        'logout.navigation_ms',
        context.startedAt.elapsedMilliseconds,
      );
    }
  }
}

class _LogoutContext {
  const _LogoutContext({
    required this.driverId,
    required this.apiKey,
    required this.binding,
    required this.tokenFuture,
    required this.logoutGeneration,
    required this.startedAt,
    required this.revokesDeviceToken,
  });

  final String? driverId;
  final String? apiKey;
  final String? binding;
  final Future<String?> tokenFuture;
  final int logoutGeneration;
  final Stopwatch startedAt;
  final bool revokesDeviceToken;
}

/// Owns driver credentials and the account boundary.
///
/// Storage split:
/// - Driver-owned identity and credentials live in `flutter_secure_storage`
///   (Keychain / EncryptedSharedPreferences).
/// - Device preferences such as language stay in SharedPreferences and survive
///   logout untouched.
class AuthService {
  // Secure keys. Namespaced so they cannot collide with the legacy plaintext
  // keys that are being migrated away from.
  static const String _secureApiKey = 'driver_api_key';
  static const String _secureDriverId = 'driver_session_id';
  static const String _secureName = 'driver_session_name';
  static const String _securePhone = 'driver_session_phone';
  static const String _secureLatitude = 'driver_session_latitude';
  static const String _secureLongitude = 'driver_session_longitude';
  static const String _secureFcmBinding = 'driver_fcm_binding';
  static const String _secureWorkSessionCapability =
      'driver_work_session_capability';
  static const String _secureWorkSessionDriverId =
      'driver_work_session_driver_id';
  static const String _secureWorkSessionEndPending =
      'driver_work_session_end_pending';
  static const String _logoutPendingKey = 'driver_logout_pending';

  // Legacy plaintext SharedPreferences keys, read once for migration then
  // removed. The driver id was historically written under three names.
  static const String _legacyApiKey = 'api_key';
  static const String _legacyUserId = 'id';
  static const String _legacyDriverId = 'driver_id';
  static const String _legacyDriverIdCamel = 'driverId';
  static const String _legacyName = 'dname';
  static const String _legacyPhone = 'phone';
  static const String _legacyLatitude = 'latitude';
  static const String _legacyLongitude = 'longitude';

  static const List<String> _legacyDriverIdKeys = [
    _legacyUserId,
    _legacyDriverId,
    _legacyDriverIdCamel,
  ];

  /// Every sensitive key that must not remain in SharedPreferences.
  static const List<String> _legacySensitiveKeys = [
    _legacyApiKey,
    _legacyUserId,
    _legacyDriverId,
    _legacyDriverIdCamel,
    _legacyName,
    _legacyPhone,
    _legacyLatitude,
    _legacyLongitude,
    // Older builds also wrote these; clear them defensively.
    'driver_name',
    'driver_phone',
    'driver_profile',
    'cached_driver_data',
    'is_logged_in',
  ];

  /// Upper bound on the logout token-revoke call so a slow network cannot hold
  /// the driver on the logout screen.
  static const Duration _revokeTimeout = Duration(seconds: 6);

  /// Upper bound on the FCM topic cleanup that follows a teardown. It never
  /// delays the teardown itself (it runs after the credentials are erased and
  /// is not awaited); the bound only stops an unreachable FCM from keeping the
  /// work alive.
  static const Duration _topicCleanupTimeout = Duration(seconds: 5);

  static AuthSecureStore _secureStore = const FlutterAuthSecureStore();

  /// In-memory session cache. Secure reads are platform-channel calls and the
  /// credential getters are hit on nearly every request, so the resolved
  /// session is held until the account boundary invalidates it.
  static DriverSession? _cachedSession;
  static Future<void> _storageQueue = Future<void>.value();
  static bool _logoutTerminal = false;
  static bool _logoutCleanupRetryStarted = false;

  /// Password rotation, logout and account replacement can invalidate an
  /// in-memory work-session UI before a GPS request notices the storage wipe.
  static final ValueNotifier<int> _workSessionInvalidations =
      ValueNotifier<int>(0);
  static ValueListenable<int> get workSessionInvalidations =>
      _workSessionInvalidations;

  /// Serializes credential writes so a delayed logout cannot erase a newer
  /// login that started while it was still running.
  static Future<T> _exclusive<T>(Future<T> Function() action) {
    final operation = _storageQueue.then((_) => action());
    _storageQueue = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return operation;
  }

  // ---------------------------------------------------------------- migration

  /// Reads one value, migrating it out of SharedPreferences on first access.
  ///
  /// Secure storage wins if it already holds a value. Otherwise the legacy
  /// plaintext value is copied across, the copy is read back to confirm it
  /// stuck, and only then is the plaintext removed. If secure storage is
  /// unavailable the legacy value is returned so an existing user is never
  /// stranded, and the migration is retried on the next uncached read.
  ///
  // NOTE: Remove this migration once every supported build stores credentials
  // securely.
  static Future<String?> _readSecureWithLegacyMigration(
    SharedPreferences prefs,
    String secureKey,
    List<String> legacyKeys,
  ) async {
    // Once local logout starts, stored values must never be used to recreate a
    // session, even if a keystore delete has not completed yet.
    if (_logoutTerminal) return null;
    String legacyValue = '';
    for (final key in legacyKeys) {
      final candidate = prefs.getString(key)?.trim() ?? '';
      if (candidate.isNotEmpty) {
        legacyValue = candidate;
        break;
      }
    }

    try {
      final secureValue = (await _secureStore.read(secureKey))?.trim() ?? '';
      if (secureValue.isNotEmpty) {
        await _removeLegacyKeys(prefs, legacyKeys);
        return secureValue;
      }

      if (legacyValue.isEmpty) {
        await _removeLegacyKeys(prefs, legacyKeys);
        return null;
      }

      await _secureStore.write(secureKey, legacyValue);
      final verified = (await _secureStore.read(secureKey))?.trim() ?? '';
      if (verified != legacyValue) {
        // Roll back rather than leave a half-migrated credential behind.
        await _secureStore.delete(secureKey);
        throw StateError('Secure credential migration verification failed.');
      }

      await _removeLegacyKeys(prefs, legacyKeys);
      return verified;
    } catch (_) {
      return legacyValue.isEmpty ? null : legacyValue;
    }
  }

  static Future<void> _removeLegacyKeys(
    SharedPreferences prefs,
    List<String> legacyKeys,
  ) async {
    for (final key in legacyKeys) {
      if (prefs.containsKey(key)) {
        await prefs.remove(key);
      }
    }
  }

  static Future<String?> _readSecureValue(
    String secureKey,
    List<String> legacyKeys,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    return _readSecureWithLegacyMigration(prefs, secureKey, legacyKeys);
  }

  static Future<void> _writeSecureValue(String secureKey, String? value) async {
    final clean = value?.trim() ?? '';
    if (clean.isEmpty) return;
    try {
      await _secureStore.write(secureKey, clean);
    } catch (e) {
      debugPrint('Secure credential write failed: ${e.runtimeType}');
    }
  }

  // -------------------------------------------------------------------- write

  static Future<void> saveApiKey(String apiKey, String id) async {
    await saveDriverSession(apiKey: apiKey, id: id);
  }

  static Future<void> saveDriverSession({
    required String apiKey,
    required String id,
    String? dname,
    String? phone,
    String? latitude,
    String? longitude,
  }) {
    return _exclusive(() async {
      await _writeSecureValue(_secureApiKey, apiKey);
      await _writeSecureValue(_secureDriverId, id);
      await _writeSecureValue(_secureName, dname);
      await _writeSecureValue(_securePhone, phone);
      await _writeSecureValue(_secureLatitude, latitude);
      await _writeSecureValue(_secureLongitude, longitude);
      // A binding belongs to one server-side FCM registration, not to the
      // login credential. The next registration writes a fresh one.
      await _secureStore.delete(_secureFcmBinding);
      await _deleteWorkSessionSecretUnsafe(notify: true);

      // A fresh login must not leave the previous plaintext copies behind.
      final prefs = await SharedPreferences.getInstance();
      await _removeLegacyKeys(prefs, _legacySensitiveKeys);
      await prefs.remove(_logoutPendingKey);

      _cachedSession = DriverSession(
        apiKey: apiKey.trim(),
        driverId: id.trim(),
      );
      _logoutTerminal = false;
      _logoutCleanupRetryStarted = false;
    });
  }

  /// Persists the opaque FCM registration fence only if the registration still
  /// belongs to the active session. A response from a pre-logout registration
  /// can therefore never attach itself to the next driver.
  static Future<bool> saveFcmBinding(
    String binding, {
    required int expectedGeneration,
    required String apiKey,
    required String driverId,
  }) async {
    final normalized = binding.trim();
    if (!_isFcmBinding(normalized)) return false;

    return _exclusive(() async {
      final current = _cachedSession;
      if (_logoutTerminal ||
          !UserSessionState.isCurrent(expectedGeneration) ||
          current == null ||
          current.apiKey != apiKey.trim() ||
          current.driverId != driverId.trim()) {
        return false;
      }
      try {
        await _secureStore.write(_secureFcmBinding, normalized);
        _cachedSession = DriverSession(
          apiKey: current.apiKey,
          driverId: current.driverId,
          fcmBinding: normalized,
        );
        return true;
      } catch (e) {
        debugPrint('FCM binding storage failed: ${e.runtimeType}');
        return false;
      }
    });
  }

  /// The server rotated this driver's key after a password change: the same
  /// session continues with the new credential; nothing else is touched.
  static Future<void> replaceApiKey(
    String apiKey, {
    int? expectedGeneration,
  }) async {
    final generation = expectedGeneration ?? UserSessionState.generation;
    final driverId = (await getSessionSnapshot()).driverId;
    await _exclusive(() async {
      // A sign-out while the change was in flight wins: never write a key
      // without the driver it belongs to.
      if (!UserSessionState.isCurrent(generation) ||
          driverId == null ||
          driverId.trim().isEmpty) {
        throw const SessionChanged();
      }
      await _writeSecureValue(_secureApiKey, apiKey);
      // A rotated API key ends the local work capability too. Session actions
      // require both credentials on the server; retaining an old capability
      // in memory would still create a misleading active UI state.
      await _deleteWorkSessionSecretUnsafe(notify: true);
      _cachedSession = DriverSession(
        apiKey: apiKey.trim(),
        driverId: driverId,
        fcmBinding: _cachedSession?.fcmBinding,
      );
    });
  }

  static Future<void> saveName(String dname) =>
      _exclusive(() => _writeSecureValue(_secureName, dname));

  /// Persists the display name returned by the authenticated profile endpoint.
  ///
  /// A profile response is allowed to replace the login-response fallback only
  /// when it still belongs to the same live session. This closes the small
  /// window where Driver A's profile request might otherwise finish after
  /// Driver B has signed in on the same device.
  static Future<bool> saveProfileNameIfCurrent({
    required String dname,
    required int expectedGeneration,
    required String apiKey,
    required String driverId,
  }) async {
    final name = dname.trim();
    if (name.isEmpty) return false;

    return _exclusive(() async {
      final current = _cachedSession;
      if (_logoutTerminal ||
          !UserSessionState.isCurrent(expectedGeneration) ||
          current == null ||
          current.apiKey != apiKey.trim() ||
          current.driverId != driverId.trim()) {
        return false;
      }

      await _writeSecureValue(_secureName, name);
      return true;
    });
  }

  static Future<void> savePhone(String phone) =>
      _exclusive(() => _writeSecureValue(_securePhone, phone));

  // --------------------------------------------------------------------- read

  static Future<String?> getApiKey() async =>
      (await getSessionSnapshot()).apiKey;

  static Future<String?> getuserId() async =>
      (await getSessionSnapshot()).driverId;

  /// Returns only an already-loaded session for a teardown that must capture
  /// its server context before credentials are erased. It never performs a
  /// storage read and becomes unavailable as soon as the local logout boundary
  /// starts, so it cannot recreate or leak a prior session.
  static DriverSession? get cachedSessionForTeardown {
    final session = _cachedSession;
    if (_logoutTerminal || session == null || !session.isAuthenticated) {
      return null;
    }
    return session;
  }

  static Future<String?> getDrivername() =>
      _readSecureValue(_secureName, const [_legacyName, 'driver_name']);

  static Future<String?> getPhone() =>
      _readSecureValue(_securePhone, const [_legacyPhone, 'driver_phone']);

  static Future<String?> getStoredLatitude() =>
      _readSecureValue(_secureLatitude, const [_legacyLatitude]);

  static Future<String?> getStoredLongitude() =>
      _readSecureValue(_secureLongitude, const [_legacyLongitude]);

  // --------------------------------------------------------- work sessions

  static bool _isWorkSessionCapability(String value) =>
      RegExp(r'^[a-f0-9]{64}$', caseSensitive: false).hasMatch(value);

  static void _notifyWorkSessionInvalidated() {
    _workSessionInvalidations.value++;
  }

  static Future<void> _deleteWorkSessionSecretUnsafe({
    required bool notify,
  }) async {
    try {
      await Future.wait([
        _secureStore.delete(_secureWorkSessionCapability),
        _secureStore.delete(_secureWorkSessionDriverId),
        _secureStore.delete(_secureWorkSessionEndPending),
      ]);
    } catch (e) {
      debugPrint('Work session credential wipe failed: ${e.runtimeType}');
    } finally {
      if (notify) _notifyWorkSessionInvalidated();
    }
  }

  /// Writes a capability only when the current authenticated driver still owns
  /// the request. The capability is read back before it can be used.
  static Future<bool> saveWorkSessionSecret({
    required String capability,
    required String driverId,
    required int expectedGeneration,
  }) async {
    final normalizedCapability = capability.trim();
    final normalizedDriverId = driverId.trim();
    if (!_isWorkSessionCapability(normalizedCapability) ||
        normalizedDriverId.isEmpty ||
        !UserSessionState.isCurrent(expectedGeneration)) {
      return false;
    }

    final session = await getSessionSnapshot();
    if (!session.isAuthenticated ||
        session.driverId != normalizedDriverId ||
        !UserSessionState.isCurrent(expectedGeneration)) {
      return false;
    }

    return _exclusive(() async {
      final current = _cachedSession;
      if (_logoutTerminal ||
          !UserSessionState.isCurrent(expectedGeneration) ||
          current == null ||
          current.driverId != normalizedDriverId) {
        return false;
      }
      try {
        await _secureStore.write(
          _secureWorkSessionCapability,
          normalizedCapability,
        );
        await _secureStore.write(
          _secureWorkSessionDriverId,
          normalizedDriverId,
        );
        await _secureStore.delete(_secureWorkSessionEndPending);
        final storedCapability =
            (await _secureStore.read(_secureWorkSessionCapability))?.trim();
        final storedDriverId =
            (await _secureStore.read(_secureWorkSessionDriverId))?.trim();
        if (storedCapability == normalizedCapability &&
            storedDriverId == normalizedDriverId) {
          return true;
        }
      } catch (e) {
        debugPrint('Work session credential storage failed: ${e.runtimeType}');
      }
      await _deleteWorkSessionSecretUnsafe(notify: true);
      return false;
    });
  }

  /// Reads a capability only if it is cryptographically-shaped and belongs to
  /// the current authenticated driver. No plaintext migration is permitted.
  static Future<DriverWorkSessionSecret?> getWorkSessionSecret({
    required int expectedGeneration,
  }) async {
    if (!UserSessionState.isCurrent(expectedGeneration)) return null;
    final session = await getSessionSnapshot();
    if (!session.isAuthenticated ||
        !UserSessionState.isCurrent(expectedGeneration)) {
      return null;
    }

    return _exclusive(() async {
      final current = _cachedSession;
      if (_logoutTerminal ||
          !UserSessionState.isCurrent(expectedGeneration) ||
          current == null ||
          !current.isAuthenticated) {
        return null;
      }
      try {
        final capability =
            (await _secureStore.read(_secureWorkSessionCapability))?.trim() ??
            '';
        final owner =
            (await _secureStore.read(_secureWorkSessionDriverId))?.trim() ?? '';
        final endPending =
            (await _secureStore.read(_secureWorkSessionEndPending))?.trim() ==
            '1';
        if (_isWorkSessionCapability(capability) &&
            owner.isNotEmpty &&
            owner == current.driverId) {
          return DriverWorkSessionSecret(
            capability: capability,
            driverId: owner,
            endPending: endPending,
          );
        }
      } catch (e) {
        debugPrint('Work session credential read failed: ${e.runtimeType}');
        return null;
      }
      await _deleteWorkSessionSecretUnsafe(notify: true);
      return null;
    });
  }

  /// Marks an End Work request for retry. The capability remains encrypted so
  /// it can be revoked later, but callers must stop local tracking immediately.
  static Future<bool> markWorkSessionEndPending({
    required String capability,
    required String driverId,
    required int expectedGeneration,
  }) async {
    final normalizedCapability = capability.trim();
    final normalizedDriverId = driverId.trim();
    if (!_isWorkSessionCapability(normalizedCapability) ||
        normalizedDriverId.isEmpty ||
        !UserSessionState.isCurrent(expectedGeneration)) {
      return false;
    }
    return _exclusive(() async {
      final current = _cachedSession;
      if (_logoutTerminal ||
          !UserSessionState.isCurrent(expectedGeneration) ||
          current == null ||
          current.driverId != normalizedDriverId) {
        return false;
      }
      try {
        final storedCapability =
            (await _secureStore.read(_secureWorkSessionCapability))?.trim();
        final storedDriverId =
            (await _secureStore.read(_secureWorkSessionDriverId))?.trim();
        if (storedCapability != normalizedCapability ||
            storedDriverId != normalizedDriverId) {
          return false;
        }
        await _secureStore.write(_secureWorkSessionEndPending, '1');
        return true;
      } catch (e) {
        debugPrint('Work session end marker failed: ${e.runtimeType}');
        return false;
      }
    });
  }

  static Future<bool> clearWorkSessionSecret({
    int? expectedGeneration,
    String? driverId,
  }) {
    return _exclusive(() async {
      if (expectedGeneration != null &&
          !UserSessionState.isCurrent(expectedGeneration)) {
        return false;
      }
      final current = _cachedSession;
      if (driverId != null &&
          (current == null || current.driverId != driverId.trim())) {
        return false;
      }
      await _deleteWorkSessionSecretUnsafe(notify: true);
      return true;
    });
  }

  static Future<DriverSession> getSessionSnapshot() async {
    if (_logoutTerminal) return const DriverSession();
    final cached = _cachedSession;
    if (cached != null) return cached;

    return _exclusive(() async {
      if (_logoutTerminal) return const DriverSession();
      final stillCached = _cachedSession;
      if (stillCached != null) return stillCached;

      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_logoutPendingKey) ?? false) {
        _logoutTerminal = true;
        _startPendingLogoutCleanupRetry();
        return const DriverSession();
      }
      final apiKey = await _readSecureWithLegacyMigration(
        prefs,
        _secureApiKey,
        const [_legacyApiKey],
      );
      final driverId = await _readSecureWithLegacyMigration(
        prefs,
        _secureDriverId,
        _legacyDriverIdKeys,
      );

      final fcmBinding = await _readSecureWithLegacyMigration(
        prefs,
        _secureFcmBinding,
        const [],
      );

      return _cachedSession = DriverSession(
        apiKey: apiKey,
        driverId: driverId,
        fcmBinding: fcmBinding,
      );
    });
  }

  // -------------------------------------------------------------------- clear

  static Future<void> clearApiKey() async {
    final result = await clearSession();
    result.startDetachedCleanup();
  }

  /// The single place driver-owned state is invalidated.
  ///
  /// Bumping the session generation first means any request already in flight is
  /// refused before the provider reset below wipes state.
  static void _resetAccountState(SessionResetReason reason) {
    // Drop the cached credentials with the rest of the account state so no
    // getter can hand out the previous driver's key.
    _logoutTerminal = true;
    _cachedSession = null;
    UserSessionState.reset(reason);
    RequestIdService.clearUserState();
  }

  /// Called by the network layer when a response ends the session. Only
  /// invalidates when the failing request still belongs to the session that is
  /// currently active, so a late response from a previous driver can never sign
  /// out — or revoke the token of — the driver who is signed in now.
  static Future<void> invalidateSessionIfCurrent(
    int generation, {
    SessionResetReason reason = SessionResetReason.invalidSession,
  }) async {
    if (!UserSessionState.isCurrent(generation)) return;
    // A teardown already running for this session is joined, not repeated.
    final inFlight = _clearingSession;
    if (inFlight != null) {
      await inFlight;
      return;
    }
    // Nothing left to end: a request sent after the credentials were erased
    // (it carries no key) must not start a second teardown and a second
    // redirect for a session that is already over.
    final session = await getSessionSnapshot();
    if (!session.isAuthenticated || !UserSessionState.isCurrent(generation)) {
      return;
    }
    await clearSession(reason: reason);
  }

  /// Resets driver-owned state without touching stored credentials. Used before
  /// a new driver's data is published so no previous account data is on screen.
  static void resetAccountStateOnly(SessionResetReason reason) {
    _resetAccountState(reason);
  }

  static Future<LogoutResult> clearSession({
    SessionResetReason reason = SessionResetReason.logout,
  }) {
    // A second teardown must not run while the first is still in flight.
    //
    // The generation check in invalidateSessionIfCurrent only starts guarding
    // once _resetAccountState has bumped it, and that happens after the awaited
    // revoke below. Without this guard, two DRIVER_INACTIVE responses landing
    // together would both pass that check and both revoke.
    //
    // Later callers join the running teardown instead of returning at once:
    // the logout sheet decides where to go from the session it finds when this
    // completes, so returning early while credentials still existed left it
    // believing the driver was signed in.
    final inFlight = _clearingSession;
    if (inFlight != null) return inFlight;
    final teardown = _clearSession(reason).whenComplete(() {
      _clearingSession = null;
    });
    _clearingSession = teardown;
    return teardown;
  }

  static Future<LogoutResult>? _clearingSession;

  static Future<LogoutResult> _clearSession(SessionResetReason reason) async {
    final startedAt = Stopwatch()..start();
    _debugTiming('logout.tap_ms', startedAt.elapsedMilliseconds);

    // Capture the old context before terminal invalidation. getToken is started
    // now but never awaited by the local logout boundary.
    final session = await getSessionSnapshot();
    final tokenFuture =
        fcmTokenCaptureForTesting?.call() ??
        NotificationSystem.captureCurrentFcmToken();
    _debugTiming('logout.context_capture_ms', startedAt.elapsedMilliseconds);

    // First invalidate all in-memory data and operational providers. Their
    // reset callbacks synchronously stop timers, polling and notification
    // routing; native service shutdown is requested without holding Login.
    _resetAccountState(reason);
    NotificationSystem.resetDriverSessionState();
    final logoutGeneration = UserSessionState.generation;
    _debugTiming('logout.local_reset_ms', startedAt.elapsedMilliseconds);

    // A persistent marker is written before any delete. If the keychain cannot
    // be fully wiped, a restart remains unauthenticated and retries cleanup;
    // old credentials are never read back into a session.
    final storageCleared = await _eraseStoredCredentials();
    _debugTiming('logout.storage_clear_ms', startedAt.elapsedMilliseconds);

    final context = _LogoutContext(
      driverId: session.driverId,
      apiKey: session.apiKey,
      binding: session.fcmBinding,
      tokenFuture: tokenFuture,
      logoutGeneration: logoutGeneration,
      startedAt: startedAt,
      revokesDeviceToken: reason.revokesDeviceToken,
    );
    final result = LogoutResult._(context, storageCleared);

    // A server-ended session has no owning widget. Its navigation is still
    // ahead of all server/FCM work; explicit logout starts the same cleanup
    // from the sheet after it has navigated.
    if (reason == SessionResetReason.invalidSession ||
        reason == SessionResetReason.accountInactive) {
      SessionRedirect.toWelcome();
      _debugTiming('logout.navigation_ms', startedAt.elapsedMilliseconds);
      result.startDetachedCleanup();
    }
    return result;
  }

  /// Best-effort, bounded FCM topic cleanup. Never awaited by the teardown.
  static void _startTopicCleanup(
    String? driverId,
    int logoutGeneration,
    Stopwatch logoutStopwatch,
  ) {
    if (driverId == null || driverId.trim().isEmpty) return;
    final cleanup =
        topicCleanupForTesting ??
        (String id) => NotificationSystem().unsubscribeDriverTopics(
          id,
          expectedGeneration: logoutGeneration,
        );
    unawaited(
      Future<void>.sync(() => cleanup(driverId))
          .timeout(_topicCleanupTimeout)
          .then<void>(
            (_) {
              _debugTiming(
                'logout.topic_cleanup_ms',
                logoutStopwatch.elapsedMilliseconds,
              );
            },
            onError: (Object e) {
              debugPrint('Topic cleanup abandoned: ${e.runtimeType}');
            },
          ),
    );
  }

  static Future<bool> _eraseStoredCredentials() async {
    return _exclusive(() async {
      var wiped = false;
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_logoutPendingKey, true);
        await Future.wait([
          _secureStore.delete(_secureApiKey),
          _secureStore.delete(_secureDriverId),
          _secureStore.delete(_secureName),
          _secureStore.delete(_securePhone),
          _secureStore.delete(_secureLatitude),
          _secureStore.delete(_secureLongitude),
          _secureStore.delete(_secureFcmBinding),
          _secureStore.delete(_secureWorkSessionCapability),
          _secureStore.delete(_secureWorkSessionDriverId),
          _secureStore.delete(_secureWorkSessionEndPending),
        ]);
        await _removeLegacyKeys(prefs, _legacySensitiveKeys);
        await prefs.remove(_logoutPendingKey);
        wiped = true;
      } catch (e) {
        debugPrint('Secure credential wipe failed: ${e.runtimeType}');
      } finally {
        _cachedSession = null;
        DriverFcmTokenService.clearRegistrationCache();
        _notifyWorkSessionInvalidated();
      }
      if (!wiped) _startPendingLogoutCleanupRetry();
      return wiped;
    });
  }

  static void _startDetachedCleanup(_LogoutContext context) {
    _startTopicCleanup(
      context.driverId,
      context.logoutGeneration,
      context.startedAt,
    );
    if (!context.revokesDeviceToken ||
        context.apiKey == null ||
        context.apiKey!.trim().isEmpty ||
        context.binding == null ||
        !_isFcmBinding(context.binding!)) {
      return;
    }

    unawaited(_revokeCapturedDeviceToken(context));
  }

  static Future<void> _revokeCapturedDeviceToken(_LogoutContext context) async {
    final remaining = _remainingRevokeTime(context.startedAt);
    if (remaining == null) return;
    try {
      final token = await context.tokenFuture.timeout(remaining);
      if (token == null || token.trim().isEmpty) return;
      final afterToken = _remainingRevokeTime(context.startedAt);
      if (afterToken == null) return;
      final testingRevoke = serverFcmRevokeForTesting;
      if (testingRevoke != null) {
        await testingRevoke(
          context.apiKey!,
          token,
          context.binding!,
          afterToken,
        );
      } else {
        await DriverFcmTokenService.revokeDriverFcmToken(
          apiKey: context.apiKey!,
          fcmToken: token,
          binding: context.binding!,
          timeout: afterToken,
        );
      }
    } catch (e) {
      debugPrint('Device token revoke skipped: ${e.runtimeType}');
    } finally {
      _debugTiming(
        'logout.server_revoke_ms',
        context.startedAt.elapsedMilliseconds,
      );
    }
  }

  static Duration? _remainingRevokeTime(Stopwatch stopwatch) {
    final remaining = _revokeTimeout - stopwatch.elapsed;
    return remaining > Duration.zero ? remaining : null;
  }

  static bool _isFcmBinding(String binding) =>
      RegExp(r'^[a-f0-9]{64}$', caseSensitive: false).hasMatch(binding);

  static void _debugTiming(String name, int milliseconds) {
    if (kDebugMode) debugPrint('$name=$milliseconds');
  }

  static void _startPendingLogoutCleanupRetry() {
    if (_logoutCleanupRetryStarted) return;
    _logoutCleanupRetryStarted = true;
    unawaited(
      Future<void>.delayed(const Duration(seconds: 1)).then((_) async {
        try {
          await _eraseStoredCredentials();
        } catch (_) {
          // The terminal marker stays set. A future app start or logout retries.
        } finally {
          _logoutCleanupRetryStarted = false;
        }
      }),
    );
  }

  // ------------------------------------------------------------------ testing

  /// Replaces the FCM topic cleanup, e.g. with one that never completes.
  @visibleForTesting
  static Future<void> Function(String driverId)? topicCleanupForTesting;

  /// Test seams keep logout timing tests off Firebase and the network.
  @visibleForTesting
  static Future<String?> Function()? fcmTokenCaptureForTesting;

  @visibleForTesting
  static Future<bool> Function(
    String apiKey,
    String fcmToken,
    String binding,
    Duration timeout,
  )?
  serverFcmRevokeForTesting;

  @visibleForTesting
  static void configureForTesting({required AuthSecureStore secureStore}) {
    _secureStore = secureStore;
    _cachedSession = null;
    _storageQueue = Future<void>.value();
    _logoutTerminal = false;
    _logoutCleanupRetryStarted = false;
    fcmTokenCaptureForTesting = null;
    serverFcmRevokeForTesting = null;
  }

  @visibleForTesting
  static void resetForTesting() {
    _secureStore = const FlutterAuthSecureStore();
    _cachedSession = null;
    _storageQueue = Future<void>.value();
    _clearingSession = null;
    topicCleanupForTesting = null;
    _logoutTerminal = false;
    _logoutCleanupRetryStarted = false;
    fcmTokenCaptureForTesting = null;
    serverFcmRevokeForTesting = null;
  }
}
