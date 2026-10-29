import 'package:blockatie/utils/external_action.dart';
import 'package:flutter/material.dart';

/// Hands off to the apps the driver contacts support with.
///
/// Every method reports its outcome as an [ExternalActionResult] instead of
/// throwing. These are called from `onTap`, and the previous versions threw
/// when `canLaunchUrl` answered no — into an un-awaited Future, so the throw
/// vanished into the zone and a driver without WhatsApp installed saw the tile
/// do nothing at all.
class SupportProvider extends ChangeNotifier {
  /// Opens a WhatsApp conversation with [phoneNumber], optionally prefilled.
  ///
  /// The number is reduced to digits because `wa.me` rejects spaces, dashes
  /// and a leading `+`.
  Future<ExternalActionResult> openWhatsApp({
    required String phoneNumber,
    String? message,
  }) {
    final digits = phoneNumber.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) {
      return Future.value(
        const ExternalActionResult.failed(ExternalActionFailure.invalidTarget),
      );
    }

    final uri = Uri.https('wa.me', '/$digits', {
      if (message != null && message.isNotEmpty) 'text': message,
    });

    return openExternalUri(uri);
  }

  Future<ExternalActionResult> openEmail(String email) {
    final address = email.trim();
    if (address.isEmpty) {
      return Future.value(
        const ExternalActionResult.failed(ExternalActionFailure.invalidTarget),
      );
    }

    return openExternalUri(Uri(scheme: 'mailto', path: address));
  }

  Future<ExternalActionResult> openFacebook({required String pageId}) async {
    final app = await openExternalUri(Uri.parse('fb://page/$pageId'));
    if (app.isSuccess) {
      return app;
    }
    return openExternalUri(Uri.https('www.facebook.com', '/$pageId'));
  }

  Future<ExternalActionResult> openInstagram({required String username}) async {
    final app = await openExternalUri(
      Uri.parse('instagram://user?username=$username'),
    );
    if (app.isSuccess) {
      return app;
    }
    return openExternalUri(Uri.https('instagram.com', '/$username'));
  }

  Future<ExternalActionResult> openLinkedIn({required String profileUrl}) {
    return openExternalUri(Uri.parse(profileUrl));
  }

  Future<ExternalActionResult> openTwitter({required String username}) async {
    final app = await openExternalUri(
      Uri.parse('twitter://user?screen_name=$username'),
    );
    if (app.isSuccess) {
      return app;
    }
    return openExternalUri(Uri.https('twitter.com', '/$username'));
  }
}
