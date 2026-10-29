import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// The fixed business clock used for driver-facing operational timestamps.
///
/// Offset-bearing API values are absolute instants and are converted to Amman.
/// Legacy offset-less values are established MySQL DATETIME values and are read
/// as Amman wall-clock time unless the caller explicitly documents a UTC legacy
/// contract (for example, driver-tour lifecycle columns).
class JordanTime {
  JordanTime._();

  static const String timezoneId = 'Asia/Amman';

  static bool _initialized = false;
  static tz.Location? _location;

  static tz.Location get location {
    if (!_initialized) {
      tz_data.initializeTimeZones();
      _location = tz.getLocation(timezoneId);
      _initialized = true;
    }
    return _location!;
  }

  static tz.TZDateTime now() => tz.TZDateTime.now(location);

  static tz.TZDateTime toJordan(DateTime value) =>
      tz.TZDateTime.from(value.toUtc(), location);

  static tz.TZDateTime? parse(
    String? value, {
    bool assumeUtcWithoutTimezone = false,
  }) {
    final raw = value?.trim() ?? '';
    if (raw.isEmpty || raw.startsWith('0000-00-00')) return null;
    final normalized = raw.contains(' ') ? raw.replaceFirst(' ', 'T') : raw;
    final parsed = DateTime.tryParse(normalized);
    if (parsed == null) return null;

    if (_hasExplicitTimezone(raw)) {
      return tz.TZDateTime.from(parsed.toUtc(), location);
    }
    if (assumeUtcWithoutTimezone) {
      return tz.TZDateTime.from(
        DateTime.utc(
          parsed.year,
          parsed.month,
          parsed.day,
          parsed.hour,
          parsed.minute,
          parsed.second,
          parsed.millisecond,
          parsed.microsecond,
        ),
        location,
      );
    }
    return tz.TZDateTime(
      location,
      parsed.year,
      parsed.month,
      parsed.day,
      parsed.hour,
      parsed.minute,
      parsed.second,
      parsed.millisecond,
      parsed.microsecond,
    );
  }

  static bool _hasExplicitTimezone(String value) =>
      RegExp(r'(Z|z|[+\-]\d{2}:\d{2}|[+\-]\d{4})$').hasMatch(value.trim());
}
