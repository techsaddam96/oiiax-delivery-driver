/// The rules the withdrawal endpoint enforces, mirrored on the client.
///
/// The backend is authoritative — nothing here decides whether a request
/// succeeds. These exist so the driver is told what is wrong before a round
/// trip, and so the app cannot send a value the server has to reject.
library;

/// Payout methods the backend allows. Anything else is refused server-side
/// with `INVALID_WITHDRAWAL_METHOD`, so the form never offers one.
const List<String> kWithdrawalMethods = ['cash', 'click'];

bool isSupportedWithdrawalMethod(String value) =>
    kWithdrawalMethods.contains(value.trim().toLowerCase());

/// Canonicalises a typed amount, or null if the backend would reject it.
///
/// The same shape the server accepts: a plain decimal with at most two
/// fraction digits. Notably 12.505 is *rejected* rather than rounded — the
/// server used to round it up to 12.51, quietly asking for more than the
/// driver typed.
///
/// Accepts 12, 12.5, 12.50 (and surrounding whitespace). Rejects an empty
/// value, zero, negatives, 0.001, "12,50", 1e9, 0x10, NaN, Infinity, a leading
/// plus and anything with a third decimal.
String? normalizeWithdrawalAmount(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return null;
  if (!RegExp(r'^(?:0|[1-9][0-9]{0,9})(?:\.[0-9]{1,2})?$').hasMatch(value)) {
    return null;
  }

  final cents = _centsFromCanonical(value);
  if (cents <= 0) return null;

  return centsToAmount(cents);
}

/// Whether a typed amount is within what the backend says is available.
///
/// Compared in cents so two values that print the same are never separated by
/// a floating-point tail.
bool isWithinAvailable(String canonicalAmount, double available) {
  return _centsFromCanonical(canonicalAmount) <= (available * 100).round();
}

String centsToAmount(int cents) =>
    '${cents ~/ 100}.${(cents % 100).toString().padLeft(2, '0')}';

int _centsFromCanonical(String canonical) {
  final parts = canonical.split('.');
  final whole = int.tryParse(parts[0]) ?? 0;
  final fraction =
      int.tryParse(parts.length > 1 ? parts[1].padRight(2, '0') : '0') ?? 0;

  return whole * 100 + fraction;
}
