import 'package:blockatie/models/shipment.dart';
import 'package:blockatie/utils/money.dart';
import 'package:blockatie/utils/text_direction.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

/// Shared presentation for the two settlement screens.
///
/// Both screens used to carry their own `_money`, `_date` and error mapping,
/// which is how they drifted away from the rest of the app: amounts printed
/// `JOD 250.00` in Arabic and an unparseable date printed itself.
String settlementCopy(BuildContext context, String en, String ar) =>
    isArabicLocale(context) ? ar : en;

/// Every amount on these screens, in the app's one convention:
/// `JOD 250.00` in English, `250.00 دينار أردني` in Arabic.
String settlementMoney(BuildContext context, double value) =>
    formatMoney(context, value);

/// `dd/MM/yyyy` in Western digits, or null when the value cannot be trusted.
///
/// Zero dates, unparseable strings and anything before 1900 become null rather
/// than printing themselves — a raw `0000-00-00 00:00:00` used to reach the
/// line tile verbatim. A naive MySQL timestamp stays naive, so nothing shifts
/// by a timezone it never had.
String? settlementDateOrNull(String value) {
  final parsed = Shipment.safeDateTime(value);
  if (parsed == null) return null;

  return DateFormat('dd/MM/yyyy', 'en').format(parsed);
}

/// The same date, with an em dash standing in for "not available".
String settlementDate(String value) => settlementDateOrNull(value) ?? '—';

/// A period, kept in reading order in both languages.
///
/// The two dates are wrapped in a single left-to-right isolate in Arabic:
/// without it the neutral separator lets the paragraph swap them, so a period
/// reads end-first.
String settlementPeriod(BuildContext context, String from, String to) {
  final start = settlementDateOrNull(from);
  final end = settlementDateOrNull(to);
  if (start == null && end == null) return '—';
  if (start == null) return end!;
  if (end == null) return start;

  final range = '$start — $end';
  return isArabicLocale(context) ? isolateLtr(range) : range;
}

/// Identifiers — settlement and shipment references — read the same way in
/// both languages, so they are isolated rather than reordered by an Arabic
/// paragraph. Anything that is not identifier-shaped is left alone.
String settlementReference(BuildContext context, String value) =>
    isArabicLocale(context) ? isolateIdentifier(value) : value;

/// How one settlement status is presented.
class SettlementStatusStyle {
  const SettlementStatusStyle({
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;
}

/// Mapped from the status value, never from words inside it.
///
/// The five the API exposes each get their own colour: every one used to be
/// green, so an approved-but-unpaid settlement looked settled. `draft` and
/// `cancelled` are hidden by the API and are not given a presentation here.
SettlementStatusStyle settlementStatusStyle(BuildContext context, String status) {
  return switch (status) {
    'paid' => SettlementStatusStyle(
      label: settlementCopy(context, 'Paid', 'تمت التسوية'),
      background: const Color(0xffE8F7EF),
      foreground: const Color(0xff168757),
    ),
    'partial' => SettlementStatusStyle(
      label: settlementCopy(context, 'Partial', 'جزئية'),
      background: const Color(0xffFEF4E4),
      foreground: const Color(0xff9A6206),
    ),
    'sent' => SettlementStatusStyle(
      label: settlementCopy(context, 'Sent', 'تم الإرسال'),
      background: const Color(0xffE7F1FE),
      foreground: const Color(0xff1B5FAD),
    ),
    'pdf_generated' => SettlementStatusStyle(
      label: settlementCopy(context, 'Ready', 'جاهزة'),
      background: const Color(0xffE7F1FE),
      foreground: const Color(0xff1B5FAD),
    ),
    'approved' => SettlementStatusStyle(
      label: settlementCopy(context, 'Approved', 'معتمدة'),
      background: const Color(0xffEEF1F6),
      foreground: const Color(0xff44546A),
    ),
    _ => SettlementStatusStyle(
      label: settlementCopy(context, 'Not available', 'غير متوفر'),
      background: const Color(0xffEEF1F6),
      foreground: const Color(0xff64748B),
    ),
  };
}

/// App-owned wording for each failure the service reports.
///
/// Resolved from the stable code: the endpoints send bilingual prose, but the
/// app writes its own so a server fault is never reported as a network one.
String settlementErrorCopy(BuildContext context, String? code) {
  return switch (code) {
    'UNAUTHORIZED' || 'AUTH_REQUIRED' => settlementCopy(
      context,
      'Session expired. Please sign in again.',
      'انتهت الجلسة. يرجى تسجيل الدخول مرة أخرى.',
    ),
    'FORBIDDEN' => settlementCopy(
      context,
      'You cannot access this settlement.',
      'لا يمكنك الوصول إلى هذه التسوية.',
    ),
    'NOT_FOUND' => settlementCopy(
      context,
      'Settlement not found.',
      'لم يتم العثور على التسوية.',
    ),
    'NETWORK' => settlementCopy(
      context,
      'Unable to connect. Please check your connection and try again.',
      'تعذر الاتصال. يرجى التحقق من الشبكة والمحاولة مرة أخرى.',
    ),
    'INVALID_REQUEST' || 'INVALID_RESPONSE' || 'SERVER_ERROR' => settlementCopy(
      context,
      'Unable to load settlement information. Please try again.',
      'تعذر تحميل معلومات التسوية. يرجى المحاولة مرة أخرى.',
    ),
    _ => settlementCopy(
      context,
      'Unable to load settlement information. Please try again.',
      'تعذر تحميل معلومات التسوية. يرجى المحاولة مرة أخرى.',
    ),
  };
}

/// Why the settlement document could not be shown.
String settlementPdfErrorCopy(BuildContext context, String? code) {
  if (code == 'PDF_NOT_AVAILABLE' || code == 'NOT_FOUND') {
    return settlementCopy(
      context,
      'The settlement document is not available yet.',
      'مستند التسوية غير متوفر بعد.',
    );
  }
  if (code == 'UNAUTHORIZED' || code == 'FORBIDDEN') {
    return settlementCopy(
      context,
      'Session expired. Please sign in again.',
      'انتهت الجلسة. يرجى تسجيل الدخول مرة أخرى.',
    );
  }

  return settlementCopy(
    context,
    'Unable to open settlement document.',
    'تعذر فتح مستند التسوية.',
  );
}
