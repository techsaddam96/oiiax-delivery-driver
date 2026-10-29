import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Why handing off to another app did not work.
///
/// The reason is a value, not a sentence. The old code threw an `Exception`
/// with English prose in it, which meant the only way for a caller to react was
/// to read that prose — and the only way for a user to learn anything was for
/// the exception to reach a screen, which it never did.
enum ExternalActionFailure {
  /// Nothing on the device can open this kind of link — WhatsApp is not
  /// installed, there is no mail client, and so on.
  unsupported,

  /// Something can open it, but the hand-off itself failed. Covers a
  /// `PlatformException` from the platform channel and a `launchUrl` that
  /// returns false.
  launchFailed,

  /// The target could not be turned into a usable link. A caller bug, not a
  /// device problem.
  invalidTarget,
}

/// The outcome of an external hand-off.
///
/// Deliberately not a thrown exception: these calls are made from `onTap`
/// handlers, and an un-awaited Future that throws disappears into the zone
/// with the user never learning that their tap did nothing.
@immutable
class ExternalActionResult {
  const ExternalActionResult.success() : failure = null;

  const ExternalActionResult.failed(ExternalActionFailure reason)
    : failure = reason;

  final ExternalActionFailure? failure;

  bool get isSuccess => failure == null;
}

/// Opens [uri] in another app, reporting the outcome instead of throwing.
///
/// Every failure mode is absorbed here so no caller has to remember to guard:
/// `canLaunchUrl` answering no, `launchUrl` answering false, and the platform
/// channel throwing. The exception text is logged, never returned — the caller
/// owns the wording the user reads.
Future<ExternalActionResult> openExternalUri(
  Uri uri, {
  LaunchMode mode = LaunchMode.externalApplication,
}) async {
  if (uri.scheme.isEmpty) {
    return const ExternalActionResult.failed(
      ExternalActionFailure.invalidTarget,
    );
  }

  try {
    if (!await canLaunchUrl(uri)) {
      return const ExternalActionResult.failed(
        ExternalActionFailure.unsupported,
      );
    }
    final launched = await launchUrl(uri, mode: mode);
    return launched
        ? const ExternalActionResult.success()
        : const ExternalActionResult.failed(ExternalActionFailure.launchFailed);
  } on PlatformException catch (e) {
    // Only the shape of the failure is logged. `e.message` can carry a device
    // path or a package name and must never reach the screen.
    debugPrint('External action failed: PlatformException(${e.code})');
    return const ExternalActionResult.failed(
      ExternalActionFailure.launchFailed,
    );
  } catch (e) {
    debugPrint('External action failed: ${e.runtimeType}');
    return const ExternalActionResult.failed(
      ExternalActionFailure.launchFailed,
    );
  }
}

/// The one sentence shown when a contact option cannot be opened.
///
/// One wording for every failure on purpose: "WhatsApp is not installed" and
/// "the hand-off failed" call for the same thing from the driver — try another
/// way of reaching support — and distinguishing them would only expose how the
/// app is built.
String externalActionFailureMessage(BuildContext context) {
  return Localizations.localeOf(context).languageCode == 'ar'
      ? 'تعذر فتح وسيلة التواصل.'
      : 'Unable to open this contact option.';
}
