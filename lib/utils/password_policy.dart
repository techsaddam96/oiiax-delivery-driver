import 'dart:convert';

/// Password Security V2: the same rules the server enforces
/// (services/helpers/password_security.php). The server stays the authority;
/// this only explains a refusal before the round trip.
class PasswordPolicy {
  static const int minLength = 10;

  /// bcrypt ignores everything after 72 bytes.
  static const int maxBytes = 72;

  /// Null when the password is acceptable, otherwise the explanation.
  static String? message(String? value, {required bool isArabic}) {
    final password = value ?? '';
    final acceptable = password.runes.length >= minLength &&
        utf8.encode(password).length <= maxBytes &&
        password == password.trim() &&
        RegExp(r'[A-Z]').hasMatch(password) &&
        RegExp(r'[a-z]').hasMatch(password) &&
        RegExp(r'\d').hasMatch(password);
    return acceptable ? null : rules(isArabic: isArabic);
  }

  /// The rules in one sentence, as the server words them.
  static String rules({required bool isArabic}) => isArabic
      ? 'استخدم من 10 إلى 72 حرفاً تتضمن حرفاً كبيراً وحرفاً صغيراً ورقماً، بدون مسافات في البداية أو النهاية.'
      : 'Use 10 to 72 characters with an uppercase letter, a lowercase letter and a number, without spaces at the start or end.';
}
