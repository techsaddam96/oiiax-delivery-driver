import 'dart:async';
import 'package:blockatie/provider/settlements/statement_handovers_provider.dart';
import 'package:blockatie/services/statement_handover_service.dart';
import 'package:blockatie/services/user_session_state.dart';
import 'package:blockatie/views/pages/settlements/statement_handovers_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const item = CashHandover(59, 'CS-TEST-59', 'Test merchant', '9.00');
class FakeHandoverService extends StatementHandoverService {
  int calls = 0;
  final response = Completer<void>();
  Completer<HandoverPage>? pendingList;
  @override
  Future<HandoverPage> fetch(int page) => pendingList?.future ?? Future.value(const HandoverPage([item], false));
  @override
  Future<void> complete(int id, String code) { calls++; return response.future; }
}

void main() {
  test('no optimistic success; duplicate submit blocked; confirmed row removed', () async {
    final service = FakeHandoverService();
    final p = StatementHandoversProvider(service: service);
    addTearDown(p.dispose);
    await p.load();
    final done = p.complete(59, '654321');
    expect(p.items.length, 1);
    expect(p.submitting, isTrue);
    await expectLater(p.complete(59, '654321'), throwsA(isA<HandoverException>()));
    expect(service.calls, 1);
    service.response.complete();
    await done;
    expect(p.items, isEmpty);
    expect(p.submitting, isFalse);
  });
  test('failed code leaves row intact and unlocks submit', () async {
    final service = FakeHandoverService();
    final p = StatementHandoversProvider(service: service);
    addTearDown(p.dispose);
    await p.load();
    final done = p.complete(59, '000000');
    final expectation = expectLater(done, throwsA(isA<HandoverException>()));
    service.response.completeError(const HandoverException('HANDOVER_INVALID_CODE'));
    await expectation;
    expect(p.items.length, 1);
    expect(p.submitting, isFalse);
  });
  test('late completion after account switch cannot signal success', () async {
    final service = FakeHandoverService();
    final p = StatementHandoversProvider(service: service);
    addTearDown(p.dispose);
    await p.load();
    final done = p.complete(59, '654321');
    final expectation = expectLater(done, throwsA(isA<SessionChanged>()));
    UserSessionState.reset(SessionResetReason.accountChanged);
    service.response.complete();
    await expectation;
    expect(p.items, isEmpty);
  });
  test('late list cannot restore a paid row', () async {
    final service = FakeHandoverService();
    final p = StatementHandoversProvider(service: service);
    addTearDown(p.dispose);
    await p.load();
    service.pendingList = Completer<HandoverPage>();
    final list = p.load();
    final done = p.complete(59, '654321');
    service.response.complete();
    await done;
    service.pendingList!.complete(const HandoverPage([item], false));
    await list;
    expect(p.items, isEmpty);
    expect(p.loading, isFalse);
  });
  testWidgets('manual input, duplicate clicks guarded and success only after confirmation', (tester) async {
    final service = FakeHandoverService();
    final p = StatementHandoversProvider(service: service);
    addTearDown(p.dispose);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (context) => TextButton(
      onPressed: () => showDialog<void>(context: context, builder: (_) => HandoverEntryDialog(item: item, provider: p, ar: false)),
      child: const Text('Open'))))));
    await tester.tap(find.text('Open')); await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField), '654321');
    await tester.tap(find.text('Confirm handover')); await tester.pump();
    await tester.tap(find.text('Confirm handover')); await tester.pump();
    expect(service.calls, 1);
    expect(find.byType(AlertDialog), findsOneWidget);
    // The code stays put while the request is in flight, so a rejection costs
    // the driver no retype. That rule is owned behaviourally by
    // statement_handover_dialog_test.dart test 6; clearing it here was the old
    // behaviour, replaced when the empty-submit lockout was fixed.
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, '654321');
    service.response.complete(); await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });
  testWidgets('account switch clears entered code and disables confirmation', (tester) async {
    final p = StatementHandoversProvider(service: FakeHandoverService());
    addTearDown(p.dispose);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: HandoverEntryDialog(item: item, provider: p, ar: true))));
    await tester.enterText(find.byType(TextField), '654321');
    UserSessionState.reset(SessionResetReason.accountChanged); await tester.pump();
    expect(find.byType(TextField), findsNothing);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
  });
}
