import 'package:blockatie/constants/colors.dart';
import 'package:blockatie/utils/nav.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:get/get_utils/src/get_utils/get_utils.dart';

class AppUtils {
  static void sucessToast(String message) {
    Fluttertoast.showToast(
      msg: message,
      toastLength: Toast.LENGTH_SHORT,
      gravity: ToastGravity.TOP,
      timeInSecForIosWeb: 1,
      backgroundColor: Colors.green,
      textColor: Colors.white,
      fontSize: 16.0,
    );
  }

  static void errorToast(String message) {
    Fluttertoast.showToast(
      msg: message,
      toastLength: Toast.LENGTH_SHORT,
      gravity: ToastGravity.TOP,
      timeInSecForIosWeb: 1,
      backgroundColor: Colors.red,
      textColor: Colors.white,
      fontSize: 16.0,
    );
  }

  /// The route this helper pushed, or null when no loader is up.
  ///
  /// Tracked so [hideLoaderDialog] can close the loader it actually opened
  /// rather than whatever happens to be on top. `hideLoaderDialog` used to be
  /// a bare `Navigator.pop`, which assumed a loader was always the top route.
  /// It is not: a flow that closed the loader and then threw called hide a
  /// second time and popped a real page.
  static Route<void>? _loaderRoute;

  /// Whether a loader opened by this helper is currently on screen.
  @visibleForTesting
  static bool get isLoaderVisible => _loaderRoute != null;

  static void showLoaderDialog() {
    final navigator = Nav.key.currentState;
    // Nothing to attach to, and one loader at a time.
    if (navigator == null || _loaderRoute != null) return;

    final route = DialogRoute<void>(
      context: navigator.context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Center(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
            ),
            width: 80,
            height: 80,
            child: Center(
              child: CircularProgressIndicator(
                strokeWidth: 3.0,
                color: AppColors.primary,
              ),
            ),
          ),
        );
      },
    );
    _loaderRoute = route;
    // Cleared however the route ends, including a system back that dismisses
    // it without going through hideLoaderDialog.
    route.popped.whenComplete(() {
      if (identical(_loaderRoute, route)) _loaderRoute = null;
    });
    navigator.push(route);
  }

  /// Closes the loader this helper opened, if one is open.
  ///
  /// Safe to call when no loader is up, and safe to call twice: it removes a
  /// route it owns, never the page underneath.
  static void hideLoaderDialog() {
    final route = _loaderRoute;
    if (route == null) return;
    _loaderRoute = null;

    final navigator = Nav.key.currentState;
    // `removeRoute` targets this route specifically; `pop` would take
    // whatever is on top, which is the whole defect.
    if (navigator != null && route.isActive) navigator.removeRoute(route);
  }

  @visibleForTesting
  static void resetLoaderForTesting() => _loaderRoute = null;
}

String? validateEmail(String? value) {
  if (value == null || value.trim().isEmpty) {
    return tr('email_required');
  }
  if (!GetUtils.isEmail(value)) {
    return tr('enter_valid_email');
  }
  return null;
}

String? validatePassword(String? value) {
  if (value == null || value.isEmpty) {
    return tr('password_required');
  }
  if (value.length < 6) {
    return tr('password_required_6');
  }
  return null;
}
