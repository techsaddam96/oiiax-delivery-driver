import 'package:blockatie/utils/text_direction.dart';
import 'package:flutter/widgets.dart';

/// One presentation for every amount the driver sees.
///
/// Currency first in English, amount first in Arabic, two decimals always —
/// the order that reads naturally in each language, and the one the shipment
/// screens already use. It lives here because the financial screens had drifted
/// apart from them and from each other: the Wallet printed `12.50 JOD` in both
/// languages while Home printed `JOD 12` for the very same field.
///
/// The value itself is never altered, rounded or abbreviated.
String formatMoney(BuildContext context, double value) {
  final amount = formatAmount(value);
  // A leading minus is bidi-neutral. Left alone it is reordered to the far end
  // of the number inside an Arabic paragraph, turning a debit into something
  // that reads like a credit. An isolate keeps the sign with its digits.
  // Positive amounts are deliberately left untouched, so the rendered string
  // stays byte-identical to the one the shipment screens produce.
  final body = amount.startsWith('-') ? isolateIdentifier(amount) : amount;
  return isArabicLocale(context) ? '$body دينار أردني' : 'JOD $body';
}

/// The number alone, always two decimals, `.00` included.
///
/// Trailing zeros carry meaning on a financial screen: `JOD 12` and
/// `JOD 12.00` are the same balance, but only one of them looks like a balance.
String formatAmount(double value) {
  // A non-finite value is a parsing accident, never a real balance. Rendering
  // `NaN دينار أردني` would be worse than rendering a zero the caller's error
  // state is already responsible for hiding.
  if (!value.isFinite) return '0.00';
  // `(-0.0).toStringAsFixed(2)` is `-0.00`, which reads as a debit of nothing.
  if (value == 0) return '0.00';
  return value.toStringAsFixed(2);
}

/// The currency on its own, for places that show a unit next to a field rather
/// than a formatted amount.
String currencyUnit(BuildContext context) =>
    isArabicLocale(context) ? 'دينار أردني' : 'JOD';

/// The single UI language source. `Localizations.localeOf` follows the widget
/// tree, so it can never disagree with the direction the page is laid out in.
bool isArabicLocale(BuildContext context) =>
    Localizations.localeOf(context).languageCode == 'ar';
