/// Defensive JSON helpers for the Driver Chat contract.
///
/// The backend is consistent, but PHP + mysqli can hand back an integer as a
/// string depending on driver settings, and optional columns arrive as null.
/// Every parse below tolerates both rather than throwing on a shape the server
/// is legitimately allowed to produce. Fields that are genuinely required use
/// [chatRequiredPositiveInt], which throws, so a malformed row fails loudly
/// instead of becoming a silently broken object.
library;

import 'package:blockatie/utils/time/jordan_time.dart';

Map<String, dynamic> chatJsonMap(
  dynamic value, {
  String fieldName = 'data',
  bool allowNull = false,
}) {
  if (value == null && allowNull) {
    return <String, dynamic>{};
  }
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  throw FormatException('Invalid chat contract field: $fieldName');
}

List<dynamic> chatJsonList(dynamic value, {required String fieldName}) {
  if (value == null) {
    return const <dynamic>[];
  }
  if (value is List) {
    return value;
  }
  throw FormatException('Invalid chat contract field: $fieldName');
}

String chatString(dynamic value, {String fallback = ''}) {
  if (value == null) {
    return fallback;
  }
  return value.toString().trim();
}

/// Null when the value is absent or blank, so callers can distinguish
/// "not provided" from "empty string".
String? chatNullableString(dynamic value) {
  final normalized = chatString(value);
  return normalized.isEmpty ? null : normalized;
}

int? chatInt(dynamic value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(chatString(value));
}

int chatRequiredPositiveInt(dynamic value, {required String fieldName}) {
  final parsed = chatInt(value);
  if (parsed == null || parsed <= 0) {
    throw FormatException('Invalid chat contract field: $fieldName');
  }
  return parsed;
}

/// Counts must never render as negative, whatever the server sends.
int chatNonNegativeInt(dynamic value, {int fallback = 0}) {
  final parsed = chatInt(value) ?? fallback;
  return parsed < 0 ? 0 : parsed;
}

bool chatBool(dynamic value, {bool fallback = false}) {
  if (value is bool) {
    return value;
  }
  if (value is num) {
    return value != 0;
  }
  switch (chatString(value).toLowerCase()) {
    case '1':
    case 'true':
    case 'yes':
      return true;
    case '0':
    case 'false':
    case 'no':
      return false;
    default:
      return fallback;
  }
}

/// The API sends both `created_at` (Amman-local, as stored) and
/// `created_at_utc` (ISO-8601 Z). Callers prefer the UTC form; this accepts
/// either and always returns an Asia/Amman DateTime for rendering.
DateTime? chatDateTime(dynamic value) {
  final normalized = chatString(value);
  if (normalized.isEmpty) {
    return null;
  }
  return JordanTime.parse(normalized);
}
