import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Home derives visible readiness from OperationalReadinessProvider', () {
    final home = File('lib/views/pages/home/home.dart').readAsStringSync();

    expect(
      home,
      contains('context.watch<OperationalReadinessProvider>().state'),
    );
    expect(home, isNot(contains('trackingStatus')));
    expect(home, contains('خدمة الموقع متوقفة'));
  });

  test(
    'cached positions are display-only and uploads require a current fix',
    () {
      final provider =
          File('lib/provider/order_location.dart').readAsStringSync();
      final lastKnown = provider.indexOf('getLastKnownPosition()');
      final currentFix = provider.indexOf('getCurrentPosition(');
      final upload = provider.indexOf('await updateDriverLocation(');

      expect(lastKnown, greaterThanOrEqualTo(0));
      expect(currentFix, greaterThan(lastKnown));
      expect(upload, greaterThan(currentFix));
      expect(
        provider.substring(lastKnown, currentFix),
        isNot(contains('updateDriverLocation(')),
      );
      expect(
        provider,
        contains('if (!await _ensureLocationReady(generation: generation))'),
      );
    },
  );

  test(
    'native monitor has no background-location permission and clears 7201/7202',
    () {
      final manifest =
          File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      final native =
          File(
            'android/app/src/main/kotlin/com/hero/blockatie/LocationReadinessMonitorService.kt',
          ).readAsStringSync();
      final activity =
          File(
            'android/app/src/main/kotlin/com/hero/blockatie/MainActivity.kt',
          ).readAsStringSync();

      expect(manifest, contains('FOREGROUND_SERVICE_LOCATION'));
      expect(
        manifest,
        isNot(
          contains(
            '<uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION"',
          ),
        ),
      );
      expect(native, contains('const val LOCATION_OFF_NOTIFICATION_ID = 7201'));
      expect(native, contains('const val MONITOR_NOTIFICATION_ID = 7202'));
      expect(native, contains('fun hideAll(context: Context)'));
      expect(native, contains('manager.cancel(MONITOR_NOTIFICATION_ID)'));
      expect(activity, contains('LocationReadinessMonitorService.stop(this)'));
      expect(native, contains('"PERMISSION_DENIED"'));
    },
  );
}
