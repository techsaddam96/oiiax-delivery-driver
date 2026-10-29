import 'dart:convert';

import 'package:blockatie/utils/password_policy.dart';

/// The registration rules, written once so the form and the server agree.
///
/// Every bound here mirrors services/api_register_drivers.php exactly. They had
/// drifted: the form accepted a 6-character password and a 7-digit phone, both
/// of which the server refuses, so a driver could satisfy the form and still be
/// rejected with wording they had no way to predict.

/// tbl_drivers.dname is varchar(50); the server counts characters.
const int kRegisterNameMaxLength = 50;

/// The server's minimum.
const int kRegisterPasswordMinLength = 10;

/// bcrypt reads only the first 72 **bytes**, which is why the server bounds the
/// byte length rather than the character count — `strlen`, not `mb_strlen`.
const int kRegisterPasswordMaxBytes = 72;

/// Whether the name is acceptable. Trimmed, because the server trims too.
bool isValidRegisterName(String? value) {
  final name = (value ?? '').trim();
  return name.length >= 2 && name.length <= kRegisterNameMaxLength;
}

bool isRegisterNameTooLong(String? value) {
  return (value ?? '').trim().length > kRegisterNameMaxLength;
}

/// The canonical Jordan local form the server stores, or null.
///
/// Mirrors normalizePhone(): strip every non-digit, drop a leading 00962 or
/// 962, then ensure a leading zero. `0791234567` and `+962791234567` both
/// reduce to `0791234567`, which is also what the UNIQUE key protects — so the
/// two spellings are one account, here and there.
String? canonicalRegisterPhone(String? value) {
  var digits = (value ?? '').replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return null;

  if (digits.startsWith('00962')) {
    digits = digits.substring(5);
  } else if (digits.startsWith('962')) {
    digits = digits.substring(3);
  }
  if (!digits.startsWith('0')) {
    digits = '0$digits';
  }
  return digits;
}

/// Why a phone was refused, in the server's own terms.
enum RegisterPhoneProblem { empty, tooShort, tooLong, invalidPrefix }

/// Checks the canonical form against the server's three rules, in the server's
/// order, so the form's complaint and the server's match.
RegisterPhoneProblem? registerPhoneProblem(String? value) {
  final canonical = canonicalRegisterPhone(value);
  if (canonical == null || canonical.isEmpty) {
    return RegisterPhoneProblem.empty;
  }
  if (canonical.length > 10) return RegisterPhoneProblem.tooLong;
  if (canonical.length < 10) return RegisterPhoneProblem.tooShort;
  if (!RegExp(r'^07[789]').hasMatch(canonical)) {
    return RegisterPhoneProblem.invalidPrefix;
  }
  return null;
}

/// Why a password was refused.
enum RegisterPasswordProblem { tooShort, tooLong, weak }

/// Not trimmed: a space is a character the driver chose, and the server hashes
/// what it is given. [weak] is the rest of the shared policy (Password
/// Security V2): an uppercase letter, a lowercase letter and a digit, and no
/// space at either end.
RegisterPasswordProblem? registerPasswordProblem(String? value) {
  final password = value ?? '';
  if (password.length < kRegisterPasswordMinLength) {
    return RegisterPasswordProblem.tooShort;
  }
  // UTF-8 bytes, matching the server. An Arabic password of 40 characters is
  // 80 bytes and must be refused here rather than silently truncated by bcrypt.
  if (utf8.encode(password).length > kRegisterPasswordMaxBytes) {
    return RegisterPasswordProblem.tooLong;
  }
  if (PasswordPolicy.message(password, isArabic: false) != null) {
    return RegisterPasswordProblem.weak;
  }
  return null;
}
