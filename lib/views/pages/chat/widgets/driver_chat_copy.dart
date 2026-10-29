import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

/// Builds a [DateFormat] that is safe for the requested locale.
///
/// intl only carries symbol data for locales that were initialized, and this
/// app never calls `initializeDateFormatting`. Asking for a locale it does not
/// know throws, which would take down the whole message list, so an unknown
/// locale falls back to intl's default rather than failing.
DateFormat chatSafeDateFormat(
  String localeName,
  DateFormat Function(String? locale) build,
) {
  return build(DateFormat.localeExists(localeName) ? localeName : null);
}

/// Bilingual copy for the chat screens.
///
/// The Driver app keeps its strings next to the widget that shows them rather
/// than in a key file, so chat follows the same convention as the settlements
/// and hub screens.
String chatCopy(BuildContext context, String en, String ar) =>
    Localizations.localeOf(context).languageCode == 'ar' ? ar : en;

/// Turns a provider's safe error key into something a driver can read.
///
/// The keys come from the chat exception layer; anything unrecognised falls
/// back to a generic message so a raw code never reaches the screen.
String chatErrorText(BuildContext context, String? key) {
  switch (key) {
    case 'chat_rate_limited':
      return chatCopy(
        context,
        'Too many messages. Please wait a moment.',
        'رسائل كثيرة. يرجى الانتظار قليلاً.',
      );
    case 'chat_access_denied':
      return chatCopy(
        context,
        'You no longer have access to this conversation.',
        'لم يعد لديك صلاحية الوصول إلى هذه المحادثة.',
      );
    case 'chat_authentication_required':
      return chatCopy(
        context,
        'Your session has expired. Please sign in again.',
        'انتهت جلستك. يرجى تسجيل الدخول مرة أخرى.',
      );
    case 'chat_network_error':
      return chatCopy(
        context,
        'No connection. Check your network and try again.',
        'لا يوجد اتصال. تحقق من الشبكة وحاول مرة أخرى.',
      );
    case 'chat_message_required':
      return chatCopy(
        context,
        'Write a message first.',
        'اكتب رسالة أولاً.',
      );
    case 'chat_message_too_long':
      return chatCopy(
        context,
        'This message is too long.',
        'هذه الرسالة طويلة جداً.',
      );
    default:
      return chatCopy(
        context,
        'Message could not be sent.',
        'تعذر إرسال الرسالة.',
      );
  }
}
