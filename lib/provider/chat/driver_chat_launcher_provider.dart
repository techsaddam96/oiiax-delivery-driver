import 'package:blockatie/services/auth_services.dart';
import 'package:blockatie/services/user_session_state.dart';

/// How the launcher asks whether a driver is signed in. Production uses
/// [AuthService.getSessionSnapshot]; tests substitute it to avoid the secure
/// storage platform channel.
typedef DriverSessionReader = Future<DriverSession> Function();

/// Decides whether the floating chat launcher belongs on screen.
///
/// Four independent conditions, all of which must hold:
///   * a stored driver session exists,
///   * the authenticated shell (the bottom-nav scaffold) is mounted, so splash
///     and the auth screens never show it,
///   * no chat screen is on top, where the launcher would only offer to open
///     what the driver is already looking at,
///   * no dialog or modal sheet is on top. The launcher is drawn above the
///     Navigator, so it floated over the logout sheet, the status sheet and
///     every dialog — and intercepted taps in the band it occupies.
///
/// This decides visibility only. Authentication itself stays in [AuthService]
/// and the session boundary in [UserSessionState]; nothing here re-implements
/// either.
class DriverChatLauncherProvider extends UserScopedNotifier {
  DriverChatLauncherProvider({DriverSessionReader? sessionReader})
    : _sessionReader = sessionReader ?? AuthService.getSessionSnapshot;

  final DriverSessionReader _sessionReader;

  bool _isAuthenticated = false;
  bool _isAuthenticatedShellVisible = false;
  bool _isChatRouteOpen = false;
  bool _isModalRouteOpen = false;

  bool get isAuthenticated => _isAuthenticated;
  bool get isAuthenticatedShellVisible => _isAuthenticatedShellVisible;
  bool get isChatRouteOpen => _isChatRouteOpen;
  bool get isModalRouteOpen => _isModalRouteOpen;

  bool get shouldShow =>
      _isAuthenticated &&
      _isAuthenticatedShellVisible &&
      !_isChatRouteOpen &&
      !_isModalRouteOpen;

  /// Re-reads the stored session. Called after navigation, so a logout that
  /// replaces the shell takes the launcher with it without anyone having to
  /// name a route.
  Future<void> syncSession() async {
    final sessionGeneration = stateGeneration;
    try {
      final session = await guardSession(_sessionReader(), sessionGeneration);
      final isAuthenticated = session.isAuthenticated;
      if (_isAuthenticated == isAuthenticated) {
        return;
      }
      _isAuthenticated = isAuthenticated;
      if (!isAuthenticated) {
        _isAuthenticatedShellVisible = false;
        _isChatRouteOpen = false;
      }
      notifyListeners();
    } on SessionChanged {
      return;
    }
  }

  /// Set by the bottom-nav shell as it mounts and unmounts.
  void setAuthenticatedShellVisible(bool value) {
    if (_isAuthenticatedShellVisible == value) {
      return;
    }
    _isAuthenticatedShellVisible = value;
    notifyListeners();
  }

  /// Set by the navigation observer from the route on top of the stack.
  void setChatRouteOpen(bool value) {
    if (_isChatRouteOpen == value) {
      return;
    }
    _isChatRouteOpen = value;
    notifyListeners();
  }

  /// Set by the navigation observer when a dialog or modal sheet is the top
  /// route. Driven by route type, so no screen has to remember to announce its
  /// own modals — and none can forget to take the announcement back.
  void setModalRouteOpen(bool value) {
    if (_isModalRouteOpen == value) {
      return;
    }
    _isModalRouteOpen = value;
    notifyListeners();
  }

  /// Wipes the previous driver's visibility state on logout or account switch.
  /// The launcher disappears immediately, before any new session is read.
  @override
  void clearUserState() {
    _isAuthenticated = false;
    _isAuthenticatedShellVisible = false;
    _isChatRouteOpen = false;
    _isModalRouteOpen = false;
  }
}
