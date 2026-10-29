import 'package:blockatie/services/user_session_state.dart';
import 'package:blockatie/utils/nav.dart';
import 'package:blockatie/views/pages/welcome/driver_welcome_page.dart';
import 'package:flutter/material.dart';

/// The one place an ended session sends the driver back to Welcome.
///
/// Both the network layer (a server-confirmed dead session: 401, 403
/// INVALID_API_KEY, 403 DRIVER_INACTIVE) and the logout sheet end up here for
/// the same teardown, so the redirect is keyed to the session generation:
/// whoever arrives second for the same ended session is a no-op, and the
/// driver sees exactly one transition to Welcome.
class SessionRedirect {
  SessionRedirect._();

  static int? _redirectedGeneration;

  /// Replaces the whole route stack with Welcome, at most once per ended
  /// session.
  ///
  /// Call only after the stored credentials are erased: the new route must
  /// not find a session to resume. When no navigator exists yet (a teardown
  /// during start-up), nothing is pushed; Splash reads the erased session and
  /// opens Welcome on its own.
  static void toWelcome() {
    final generation = UserSessionState.generation;
    if (_redirectedGeneration == generation) return;

    final override = navigateForTesting;
    if (override != null) {
      _redirectedGeneration = generation;
      override();
      return;
    }

    final navigator = Nav.key.currentState;
    if (navigator == null) return;
    _redirectedGeneration = generation;
    navigator.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const DriverWelcomePage()),
      (_) => false,
    );
  }

  /// Replaces the navigation in tests that have no app shell.
  @visibleForTesting
  static VoidCallback? navigateForTesting;

  @visibleForTesting
  static void resetForTesting() {
    _redirectedGeneration = null;
    navigateForTesting = null;
  }
}
