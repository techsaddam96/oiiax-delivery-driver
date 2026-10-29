import 'dart:async';

import 'package:blockatie/models/driver_tour.dart';
import 'package:blockatie/provider/driver_tours.dart';
import 'package:blockatie/services/driver_tour_service.dart';
import 'package:blockatie/services/user_session_state.dart';
import 'package:blockatie/views/pages/tours/driver_tours_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _ToursFake implements DriverToursRepository {
  _ToursFake({this.state = DriverTourState.ready, this.commandGate});

  DriverTourState state;
  final Completer<void>? commandGate;
  int currentCalls = 0;
  int detailCalls = 0;
  int commandCalls = 0;
  String? receivedReason;
  DriverTourException? commandError;

  @override
  Future<List<DriverTour>> current() async {
    currentCalls++;
    return [
      DriverTour(
        id: 91,
        state: state,
        stateVersion: state == DriverTourState.ready ? 3 : 4,
        plannedStopCount: 2,
        requiresExplicitStart: state == DriverTourState.ready,
      ),
    ];
  }

  @override
  Future<DriverTourDetails> details(int tourId) async {
    detailCalls++;
    return _details(state);
  }

  @override
  Future<DriverTourCommandResult> command({
    required String action,
    required int tourId,
    required int expectedStateVersion,
    String? reason,
  }) async {
    commandCalls++;
    receivedReason = reason;
    if (commandGate != null) await commandGate!.future;
    if (commandError != null) throw commandError!;
    state = switch (action) {
      'start' || 'resume' => DriverTourState.active,
      'interrupt' => DriverTourState.interrupted,
      'complete' => DriverTourState.completed,
      _ => state,
    };
    return DriverTourCommandResult(
      tourId: tourId,
      state: state,
      idempotent: false,
    );
  }
}

DriverTourDetails _details(DriverTourState state) => DriverTourDetails(
  tour: DriverTour(
    id: 91,
    state: state,
    stateVersion: state == DriverTourState.ready ? 3 : 4,
    plannedStopCount: 2,
    requiresExplicitStart: state == DriverTourState.ready,
  ),
  summary: DriverTourSummary(
    plannedStopCount: 2,
    snapshotStopCount: 2,
    outcomeStopCount: state == DriverTourState.active ? 0 : 0,
    remainingStopCount: 2,
    canComplete: false,
  ),
  stops: const [
    DriverTourStop(
      id: 11,
      shipmentId: 901,
      order: 1,
      state: DriverTourStopState.pending,
      driverHasAccepted: false,
    ),
  ],
);

Widget _app(
  DriverToursProvider provider, {
  Locale locale = const Locale('en'),
}) => ChangeNotifierProvider.value(
  value: provider,
  child: MaterialApp(
    locale: locale,
    supportedLocales: const [Locale('en'), Locale('ar')],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: const DriverToursPage(),
  ),
);

void main() {
  test(
    'provider never changes state locally while a lifecycle command is pending',
    () async {
      final gate = Completer<void>();
      final fake = _ToursFake(commandGate: gate);
      final provider = DriverToursProvider(repository: fake);
      addTearDown(provider.dispose);

      await provider.refresh();
      final before = provider.details!;
      final pending = provider.command(action: 'start', tour: before.tour);

      expect(provider.isCommandBusy(91), isTrue);
      expect(provider.details!.tour.state, DriverTourState.ready);
      expect(fake.commandCalls, 1);

      gate.complete();
      await pending;

      expect(provider.isCommandBusy(91), isFalse);
      expect(provider.details!.tour.state, DriverTourState.active);
      expect(fake.currentCalls, greaterThanOrEqualTo(2));
      expect(fake.detailCalls, greaterThanOrEqualTo(2));
    },
  );

  test(
    'provider blocks a duplicate lifecycle request while one is active',
    () async {
      final gate = Completer<void>();
      final fake = _ToursFake(commandGate: gate);
      final provider = DriverToursProvider(repository: fake);
      addTearDown(provider.dispose);
      await provider.refresh();

      final first = provider.command(
        action: 'start',
        tour: provider.details!.tour,
      );
      await expectLater(
        provider.command(action: 'start', tour: provider.details!.tour),
        throwsA(
          isA<DriverTourException>().having(
            (error) => error.code,
            'code',
            'TOUR_COMMAND_IN_PROGRESS',
          ),
        ),
      );
      expect(fake.commandCalls, 1);
      gate.complete();
      await first;
    },
  );

  test(
    'a stale conflict reloads details and leaves no success state',
    () async {
      final fake =
          _ToursFake()
            ..commandError = const DriverTourException(
              kind: DriverTourFailureKind.conflict,
              code: 'TOUR_COMMAND_REJECTED',
              statusCode: 409,
            );
      final provider = DriverToursProvider(repository: fake);
      addTearDown(provider.dispose);
      await provider.refresh();
      final originalDetails = fake.detailCalls;

      await expectLater(
        provider.command(action: 'start', tour: provider.details!.tour),
        throwsA(isA<DriverTourException>()),
      );
      expect(fake.detailCalls, originalDetails + 1);
      expect(provider.details!.tour.state, DriverTourState.ready);
    },
  );

  test('a session boundary clears all tour state', () async {
    final provider = DriverToursProvider(repository: _ToursFake());
    addTearDown(provider.dispose);
    await provider.refresh();
    expect(provider.details, isNotNull);

    UserSessionState.reset(SessionResetReason.accountChanged);

    expect(provider.details, isNull);
    expect(provider.tours, isEmpty);
    expect(provider.selectedTourId, isNull);
  });

  testWidgets(
    'English tour UI is privacy-safe and exposes only valid READY action',
    (tester) async {
      final provider = DriverToursProvider(repository: _ToursFake());
      addTearDown(provider.dispose);
      await tester.pumpWidget(_app(provider));
      await tester.pumpAndSettle();

      expect(find.text('My tour'), findsOneWidget);
      expect(find.text('Start tour'), findsOneWidget);
      expect(find.text('Shipment #901'), findsOneWidget);
      expect(find.text('Private recipient'), findsNothing);
      expect(find.text('Open shipment'), findsNothing);
    },
  );

  testWidgets('Arabic UI keeps RTL copy and interruption requires a reason', (
    tester,
  ) async {
    final fake = _ToursFake(state: DriverTourState.active);
    final provider = DriverToursProvider(repository: fake);
    addTearDown(provider.dispose);
    await tester.pumpWidget(_app(provider, locale: const Locale('ar')));
    await tester.pumpAndSettle();

    expect(find.text('جولتي'), findsOneWidget);
    await tester.tap(find.text('إيقاف مؤقت'));
    await tester.pumpAndSettle();
    expect(find.text('السبب'), findsOneWidget);
    await tester.tap(find.text('إيقاف مؤقت').last);
    await tester.pump();
    expect(find.text('أدخل سبباً صالحاً من 1 إلى 255 حرفاً.'), findsOneWidget);
    expect(fake.commandCalls, 0);

    await tester.enterText(find.byType(TextField), 'تعذر الوصول إلى الموقع');
    await tester.tap(find.text('إيقاف مؤقت').last);
    await tester.pumpAndSettle();
    expect(fake.commandCalls, 1);
    expect(fake.receivedReason, 'تعذر الوصول إلى الموقع');
  });
}
