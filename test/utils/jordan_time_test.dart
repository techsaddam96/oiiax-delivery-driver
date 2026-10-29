import 'package:blockatie/utils/time/jordan_time.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('renders UTC instants in the fixed Jordan business timezone', () {
    final standard = JordanTime.parse('2026-10-28T09:00:00Z');
    final boundary = JordanTime.parse('2026-10-28T23:45:00Z');

    expect(standard?.toString(), '2026-10-28 12:00:00.000+0300');
    expect(boundary?.toString(), '2026-10-29 02:45:00.000+0300');
  });

  test('can explicitly retain legacy UTC lifecycle columns', () {
    final value = JordanTime.parse(
      '2026-10-28 09:00:00',
      assumeUtcWithoutTimezone: true,
    );

    expect(value?.hour, 12);
    expect(value?.timeZoneOffset, const Duration(hours: 3));
  });
}
