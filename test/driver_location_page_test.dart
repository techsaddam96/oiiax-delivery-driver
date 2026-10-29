import 'package:blockatie/provider/operational_readiness.dart';
import 'package:blockatie/provider/order_location.dart';
import 'package:blockatie/views/pages/driver-location/driver_location.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

class _SilentPlatform implements OperationalPlatformBridge {
  @override
  Stream<bool> get vpnChanges => const Stream<bool>.empty();
  @override
  Stream<void> get locationLaunchRequests => const Stream<void>.empty();
  @override
  Future<bool> consumePendingLocationLaunch() async => false;
  @override
  Future<bool> currentVpnState() async => false;
  @override
  Future<void> hideLocationOffNotification() async {}
  @override
  Future<LocationOffNotificationResult> showLocationOffNotification({
    required bool isArabic,
  }) async => LocationOffNotificationResult.posted;
  @override
  Future<void> startLocationReadinessMonitor({required bool isArabic}) async {}
  @override
  Future<void> stopLocationReadinessMonitor() async {}
}

Future<void> _pumpPage(
  WidgetTester tester, {
  required OperationalReadinessState state,
  LatLng? point,
  DateTime? gpsFix,
  double? accuracy,
  Future<void> Function()? refresh,
  Future<void> Function()? center,
  Locale locale = const Locale('en'),
}) async {
  final readiness = OperationalReadinessProvider(platform: _SilentPlatform());
  readiness.applyTestState(
    serviceEnabled: state != OperationalReadinessState.locationServiceOff,
    permission:
        state == OperationalReadinessState.locationPermissionPermanentlyDenied
            ? LocationPermission.deniedForever
            : state == OperationalReadinessState.locationPermissionDenied
            ? LocationPermission.denied
            : LocationPermission.whileInUse,
    vpnActive: state == OperationalReadinessState.vpnActive,
    locationUnavailable: state == OperationalReadinessState.locationUnavailable,
  );
  final location = OrderLocationProvider();
  location.applyLocationForTest(
    location: point,
    status:
        point == null
            ? DriverLocationTrackingStatus.unavailable
            : DriverLocationTrackingStatus.active,
    gpsFixAt: gpsFix,
    serverSyncAt: gpsFix,
    accuracyMeters: accuracy,
  );
  addTearDown(() {
    readiness.dispose();
    location.dispose();
  });

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<OperationalReadinessProvider>.value(
          value: readiness,
        ),
        ChangeNotifierProvider<OrderLocationProvider>.value(value: location),
      ],
      child: MaterialApp(
        locale: locale,
        supportedLocales: const [Locale('en'), Locale('ar')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: DriverLocationPage(
          refreshOverride: refresh ?? () async {},
          centerOverride: center,
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('shows explicit loading and GPS failure states', (tester) async {
    await _pumpPage(tester, state: OperationalReadinessState.ready);
    expect(find.text('Finding your location'), findsOneWidget);

    await _pumpPage(
      tester,
      state: OperationalReadinessState.locationServiceOff,
    );
    expect(find.text('Location service is off'), findsWidgets);

    await _pumpPage(
      tester,
      state: OperationalReadinessState.locationPermissionDenied,
    );
    expect(find.text('Location permission required'), findsWidgets);

    await _pumpPage(
      tester,
      state: OperationalReadinessState.locationPermissionPermanentlyDenied,
    );
    expect(find.text('Location permission required'), findsWidgets);

    await _pumpPage(
      tester,
      state: OperationalReadinessState.locationUnavailable,
    );
    expect(find.text('Location is unavailable'), findsOneWidget);
  });

  testWidgets('renders current coordinates, accuracy, and last update', (
    tester,
  ) async {
    await _pumpPage(
      tester,
      state: OperationalReadinessState.ready,
      point: const LatLng(31.95395, 35.91064),
      gpsFix: DateTime(2026, 10, 15, 14, 7, 9),
      accuracy: 6.2,
    );
    expect(find.text('31.95395, 35.91064'), findsOneWidget);
    expect(find.text('±6 m'), findsOneWidget);
    expect(find.text('14:07:09'), findsNWidgets(2));
    expect(find.byType(GoogleMap), findsOneWidget);
  });

  testWidgets('refresh and center actions call only supplied actions', (
    tester,
  ) async {
    var refreshCalls = 0;
    var centerCalls = 0;
    await _pumpPage(
      tester,
      state: OperationalReadinessState.ready,
      point: const LatLng(31.95395, 35.91064),
      refresh: () async => refreshCalls++,
      center: () async => centerCalls++,
    );
    expect(refreshCalls, 1); // Initial page refresh.

    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pump();

    await tester.tap(find.text('Refresh'));
    await tester.pump();
    expect(refreshCalls, 2);

    await tester.tap(find.text('Center on me'));
    await tester.pump();
    expect(centerCalls, 1);
  });

  testWidgets('Arabic labels use the expected operational copy', (
    tester,
  ) async {
    await _pumpPage(
      tester,
      state: OperationalReadinessState.locationServiceOff,
      locale: const Locale('ar'),
    );
    expect(find.text('موقعي'), findsOneWidget);
    expect(find.text('خدمة الموقع متوقفة'), findsWidgets);
    expect(find.text('تشغيل الموقع'), findsNothing);
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pump();
    expect(find.text('فتح الإعدادات المناسبة'), findsOneWidget);
  });
}
