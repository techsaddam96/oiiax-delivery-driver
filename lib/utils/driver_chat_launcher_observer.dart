import 'package:blockatie/provider/chat/driver_chat_launcher_provider.dart';
import 'package:blockatie/views/pages/chat/driver_chat_navigation.dart';
import 'package:flutter/material.dart';

/// Keeps the floating chat launcher in step with the navigation stack.
///
/// Three jobs, all driven by what the Navigator actually did rather than by
/// callers remembering to report it:
///   * hide the launcher while a chat screen is the top route,
///   * hide it while a dialog or modal sheet is the top route,
///   * re-read the session after every navigation, so a logout that replaces
///     the authenticated shell takes the launcher with it.
class DriverChatLauncherObserver extends NavigatorObserver {
  DriverChatLauncherObserver(this._launcher);

  final DriverChatLauncherProvider _launcher;

  /// The routes this observer has seen, in stack order. Only the top one
  /// decides visibility — a chat screen buried under a pushed shipment screen
  /// must not keep the launcher hidden there.
  final List<Route<dynamic>> _stack = <Route<dynamic>>[];

  @visibleForTesting
  List<String?> get routeNames =>
      _stack.map((route) => route.settings.name).toList(growable: false);

  void _sync() {
    final top = _stack.isEmpty ? null : _stack.last;

    _launcher.setChatRouteOpen(
      top != null && DriverChatRoutes.hidesLauncher(top.settings.name),
    );

    // Decided from the route's type, not its name: `showDialog` and
    // `showModalBottomSheet` leave `settings.name` null, so a name-based rule
    // could never see them. Every dialog and modal sheet Flutter builds is a
    // PopupRoute, which makes this one check cover them all — including ones
    // added later that nobody remembers to register.
    _launcher.setModalRouteOpen(top is PopupRoute);
    // Deferred: the observer fires mid-navigation, and reading storage from
    // inside that frame would notify listeners while the tree is building.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _launcher.syncSession();
    });
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _stack.add(route);
    _sync();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    _stack.remove(route);
    _sync();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didRemove(route, previousRoute);
    _stack.remove(route);
    _sync();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    final index = oldRoute == null ? -1 : _stack.indexOf(oldRoute);
    if (index >= 0) {
      if (newRoute == null) {
        _stack.removeAt(index);
      } else {
        _stack[index] = newRoute;
      }
    } else if (newRoute != null) {
      _stack.add(newRoute);
    }
    _sync();
  }
}
