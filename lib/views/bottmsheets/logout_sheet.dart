import 'dart:ui';

import 'package:blockatie/constants/colors.dart';
import 'package:blockatie/provider/order_location.dart';
import 'package:blockatie/provider/driver_work_session.dart';
import 'package:blockatie/services/auth_services.dart';
import 'package:blockatie/utils/session_redirect.dart';
import 'package:blockatie/views/dialoges/location_permission.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class LogoutBottomSheet extends StatefulWidget {
  const LogoutBottomSheet({super.key});

  @override
  State<LogoutBottomSheet> createState() => _LogoutBottomSheetState();
}

/// Shows the logout confirmation.
///
/// One entry point so the route options travel with the sheet. `enableDrag` is
/// off because Flutter's drag-to-close pops the route directly rather than
/// through `maybePop`, which means the sheet's own `PopScope` cannot stop it —
/// and a swipe during the teardown would take the redirect to Welcome with it.
/// The scrim and the system back button still dismiss it while it is idle.
Future<void> showLogoutSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    isScrollControlled: true,
    useSafeArea: true,
    enableDrag: false,
    builder: (_) => const LogoutBottomSheet(),
  );
}

class _LogoutBottomSheetState extends State<LogoutBottomSheet> {
  bool _isLoggingOut = false;

  Future<void> _logout() async {
    if (_isLoggingOut) return;
    setState(() => _isLoggingOut = true);

    // Captured before the await. Once the session is cleared this State may be
    // gone, and the old code reached for `context` afterwards — so a sheet
    // dismissed mid-logout cleared the credentials and then skipped the
    // navigation, stranding the driver on the Hub with no session.
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    final workSession = Provider.of<DriverWorkSessionProvider?>(
      context,
      listen: false,
    );
    final orderLocation = context.read<OrderLocationProvider>();
    final timing = Stopwatch()..start();

    LogoutResult? logout;
    try {
      // Stop device-level services this screen owns, then hand off to the
      // single session boundary. AuthService.clearSession() invalidates
      // in-flight requests, resets every user-scoped provider and only then
      // erases credentials, so we must not navigate before it completes.
      // This is intentionally non-blocking at the network layer: an offline
      // logout still erases the capability locally and must never look active
      // after a restart. The backend logout endpoint is a second session fence.
      // An active work session already holds a server-confirmed capability in
      // memory. Capture it and dispatch End Work before credentials are
      // erased, without making the sheet wait for another secure-store read.
      // A cold-start capability still takes the conservative awaited fallback
      // so it is never silently abandoned.
      if (workSession?.canStopForLogoutImmediately ?? true) {
        workSession?.stopForLogoutImmediately();
      } else {
        await workSession?.stopForLogout();
      }
      debugPrint(
        'logout.work_session_prepare_ms=${timing.elapsedMilliseconds}',
      );
      orderLocation.stopDriverLocationUpdates();
      LocationService().stopMonitoring();
      debugPrint('logout.gps_stop_ms=${timing.elapsedMilliseconds}');
      logout = await AuthService.clearSession();
      debugPrint('logout.local_boundary_ms=${timing.elapsedMilliseconds}');
    } catch (e) {
      // clearSession already absorbs revoke and topic failures internally, so
      // reaching here means something unexpected. The session may be partly
      // cleared either way, which is why the destination below is decided from
      // the session itself rather than from this outcome.
      debugPrint('Logout failed: ${e.runtimeType}');
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              isArabic
                  ? 'تعذر إكمال تسجيل الخروج. يرجى المحاولة مرة أخرى.'
                  : 'Unable to complete sign out. Please try again.',
            ),
            backgroundColor: const Color(0xffDC2626),
          ),
        );
    } finally {
      // Always released, so the sheet can never be left spinning with both
      // buttons disabled and no way out.
      if (mounted) {
        setState(() => _isLoggingOut = false);
      }
    }

    // No post-wipe session read: AuthService has already crossed the terminal
    // local boundary, including when a keystore delete needs a safe retry.
    // Using the captured navigator means the redirect still happens if the
    // sheet was torn down while the teardown was running.
    if (logout == null) return;

    if (navigator.canPop()) {
      navigator.pop();
    }
    // Shared with the network-layer teardown: if that already sent the
    // driver to Welcome for this session, this is a no-op.
    SessionRedirect.toWelcome();
    logout.recordLoginNavigation();
    // Server FCM revoke and FCM topic cleanup start only after Welcome has been
    // requested. They use captured old-session context and cannot alter a new
    // Flutter session.
    logout.startDetachedCleanup();
  }

  @override
  Widget build(BuildContext context) {
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';

    // While the teardown is running the sheet must stay put: it owns the
    // redirect to Welcome, and a scrim tap or a back gesture used to take it
    // away mid-flight. Idle, both still dismiss it.
    //
    // This covers the barrier and the system back button, which both route
    // through `Navigator.maybePop` and therefore consult `popDisposition`.
    // The drag gesture does not — `BottomSheet.onClosing` calls
    // `Navigator.pop` outright — so `enableDrag: false` is set where this
    // sheet is shown. See `showLogoutSheet`.
    return PopScope(canPop: !_isLoggingOut, child: _sheet(context, isArabic));
  }

  Widget _sheet(BuildContext context, bool isArabic) {
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 5,
                decoration: BoxDecoration(
                  color: const Color(0xffCBD5E1),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 22),
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: const Color(0xffFEF2F2),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(
                  Icons.logout_rounded,
                  color: Color(0xffDC2626),
                  size: 28,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                isArabic ? 'هل تريد تسجيل الخروج؟' : 'Do you want to log out?',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xff0F172A),
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                isArabic
                    ? 'سيتم مسح بيانات الجلسة من هذا الجهاز.'
                    : 'Your session data will be cleared from this device.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xff64748B),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed:
                          _isLoggingOut ? null : () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: BorderSide(color: AppColors.primary),
                        minimumSize: const Size.fromHeight(52),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: Text(
                        isArabic ? 'إلغاء' : 'Cancel',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Semantics(
                      button: true,
                      // Spelled out because the control collapses to a bare
                      // spinner while the teardown runs, which a screen reader
                      // would otherwise announce as an unlabelled button.
                      label:
                          isArabic
                              ? (_isLoggingOut
                                  ? 'جارٍ تسجيل الخروج'
                                  : 'تأكيد تسجيل الخروج')
                              : (_isLoggingOut
                                  ? 'Signing out'
                                  : 'Confirm sign out'),
                      child: ElevatedButton(
                        onPressed: _isLoggingOut ? null : _logout,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xffDC2626),
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: const Color(0xffFCA5A5),
                          minimumSize: const Size.fromHeight(52),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child:
                            _isLoggingOut
                                ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.4,
                                    color: Colors.white,
                                  ),
                                )
                                : Text(
                                  isArabic ? 'تسجيل الخروج' : 'Logout',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
