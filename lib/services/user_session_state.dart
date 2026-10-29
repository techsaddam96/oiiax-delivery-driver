import 'package:flutter/foundation.dart';

/// Why an account boundary was crossed. Used so the UI can distinguish an
/// explicit logout from a credential that the backend rejected.
///
/// [invalidSession] and [accountInactive] both end the session from the network
/// layer, but they differ in one way that matters: after [invalidSession] (a
/// 401) the stored API key has been rejected outright and can no longer be used
/// for anything, while after [accountInactive] (403 DRIVER_INACTIVE) the key is
/// still a valid credential for an account an Admin has disabled. The logout
/// endpoint deliberately still accepts it, so this device's FCM token can be
/// released before the credential is erased.
enum SessionResetReason {
  logout,
  accountChanged,
  invalidSession,
  accountInactive,
}

/// Whether this reason should release the device's FCM token server-side.
///
/// Everything except [SessionResetReason.invalidSession] does: only a 401 means
/// the key itself is dead, and calling logout with a dead key cannot succeed.
extension SessionResetReasonRevoke on SessionResetReason {
  bool get revokesDeviceToken => this != SessionResetReason.invalidSession;
}

/// Thrown when work started under a previous driver session tries to finish.
class SessionChanged implements Exception {
  const SessionChanged();
}

/// One synchronous boundary for all driver-owned state.
///
/// Providers register a reset callback here. Incrementing the generation is what
/// invalidates in-flight work: any response stamped with an older generation is
/// discarded instead of being written into the next driver's state.
class UserSessionState {
  UserSessionState._();

  static int _generation = 0;
  static final Set<VoidCallback> _resets = {};
  static final ValueNotifier<int> changes = ValueNotifier(0);
  static SessionResetReason? lastReason;

  static int get generation => _generation;
  static bool isCurrent(int generation) => generation == _generation;

  static void register(VoidCallback reset) => _resets.add(reset);
  static void unregister(VoidCallback reset) => _resets.remove(reset);

  static void reset(SessionResetReason reason) {
    // Invalidate late responses before clearing any account data, so a response
    // that lands mid-reset can never repopulate what we are about to clear.
    _generation++;
    lastReason = reason;
    for (final reset in List<VoidCallback>.of(_resets)) {
      reset();
    }
    changes.value = _generation;
  }
}

/// Base class for every provider that owns driver-specific data.
///
/// Subclasses implement [clearUserState] to wipe their own fields. They must not
/// clear device-level preferences such as language.
abstract class UserScopedNotifier extends ChangeNotifier {
  UserScopedNotifier() {
    UserSessionState.register(resetUserState);
  }

  int _stateGeneration = 0;
  bool _stateDisposed = false;

  int get stateGeneration => _stateGeneration;

  /// True only while the given generation is still the provider's current one.
  bool acceptsState(int generation) =>
      !_stateDisposed && generation == _stateGeneration;

  /// Awaits [operation] and refuses the result if the session moved on.
  Future<T> guardSession<T>(Future<T> operation, int generation) async {
    try {
      final result = await operation;
      if (!acceptsState(generation)) throw const SessionChanged();
      return result;
    } catch (_) {
      if (!acceptsState(generation)) throw const SessionChanged();
      rethrow;
    }
  }

  void resetUserState() {
    if (_stateDisposed) return;
    _stateGeneration++;
    clearUserState();
    notifyListeners();
  }

  /// Wipe every field that belongs to the authenticated driver.
  @protected
  void clearUserState();

  @override
  void notifyListeners() {
    if (!_stateDisposed) super.notifyListeners();
  }

  @override
  void dispose() {
    UserSessionState.unregister(resetUserState);
    _stateDisposed = true;
    _stateGeneration++;
    super.dispose();
  }
}
