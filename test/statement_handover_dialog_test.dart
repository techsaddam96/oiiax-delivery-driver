// The handover code dialog.
//
// What these start from: the dialog submitted whatever was in the field,
// including nothing at all. The server counts every rejected code against a
// five-strike, fifteen-minute lockout, so tapping Confirm on an empty field
// spent a real attempt and answered with "check the code and statement
// status" for a code the driver had never entered. The field was also cleared
// before the request, so one wrong digit cost all six again.

import 'package:blockatie/provider/settlements/statement_handovers_provider.dart';
import 'package:blockatie/services/statement_handover_service.dart';
import 'package:blockatie/views/pages/settlements/statement_handovers_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records every code the dialog actually sends.
class _RecordingProvider extends StatementHandoversProvider {
  _RecordingProvider({this.failWith});

  final String? failWith;
  final List<String> submitted = [];

  @override
  Future<bool> complete(int id, String code) async {
    submitted.add(code);
    if (failWith != null) {
      throw HandoverException(failWith!);
    }
    return true;
  }
}

const _item = CashHandover(59, 'CS-260922-59', 'QA Store', '9.00');

Widget _app(StatementHandoversProvider provider, {bool ar = true}) {
  return MaterialApp(
    locale: ar ? const Locale('ar') : const Locale('en'),
    supportedLocales: const [Locale('en'), Locale('ar')],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(
      body: HandoverEntryDialog(item: _item, provider: provider, ar: ar),
    ),
  );
}

Finder get _confirm => find.widgetWithText(FilledButton, 'تأكيد التسليم');
Finder get _field => find.byType(TextField);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('an incomplete code never reaches the server', () {
    testWidgets('1. confirm is disabled while the field is empty', (
      tester,
    ) async {
      final provider = _RecordingProvider();
      addTearDown(provider.dispose);
      await tester.pumpWidget(_app(provider));

      final button = tester.widget<FilledButton>(_confirm);
      expect(button.onPressed, isNull);
    });

    testWidgets('2. and while it is short', (tester) async {
      final provider = _RecordingProvider();
      addTearDown(provider.dispose);
      await tester.pumpWidget(_app(provider));

      await tester.enterText(_field, '8155');
      await tester.pump();

      expect(tester.widget<FilledButton>(_confirm).onPressed, isNull);
      expect(provider.submitted, isEmpty);
    });

    testWidgets('3. six digits enable it', (tester) async {
      final provider = _RecordingProvider();
      addTearDown(provider.dispose);
      await tester.pumpWidget(_app(provider));

      await tester.enterText(_field, '815594');
      await tester.pump();

      expect(tester.widget<FilledButton>(_confirm).onPressed, isNotNull);
    });

    testWidgets('4. an empty submit spends no attempt', (tester) async {
      final provider = _RecordingProvider();
      addTearDown(provider.dispose);
      await tester.pumpWidget(_app(provider));

      await tester.tap(_confirm, warnIfMissed: false);
      await tester.pump();

      // The lockout counter is a scarce resource; nothing was sent.
      expect(provider.submitted, isEmpty);
    });
  });

  group('what the driver is told', () {
    testWidgets('5. an incomplete code asks for the code, not for a recheck', (
      tester,
    ) async {
      final provider = _RecordingProvider();
      addTearDown(provider.dispose);
      await tester.pumpWidget(_app(provider));

      await tester.enterText(_field, '81');
      // Pressing done on the keyboard is the one way to submit a short code.
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.textContaining('أدخل رمز التسليم'), findsOneWidget);
      expect(
        find.textContaining('تحقق من الرمز وحالة الكشف'),
        findsNothing,
        reason: 'that wording belongs to a code the server actually rejected',
      );
      expect(provider.submitted, isEmpty);
    });
  });

  group('a rejected code', () {
    testWidgets('6. is kept in the field so it can be corrected', (
      tester,
    ) async {
      final provider = _RecordingProvider(failWith: 'HANDOVER_INVALID_CODE');
      addTearDown(provider.dispose);
      await tester.pumpWidget(_app(provider));

      await tester.enterText(_field, '815593');
      await tester.pump();
      await tester.tap(_confirm);
      await tester.pumpAndSettle();

      expect(provider.submitted, ['815593']);
      // Clearing it before the request meant retyping all six digits to fix one.
      expect(tester.widget<TextField>(_field).controller!.text, '815593');
      expect(find.textContaining('تحقق من الرمز وحالة الكشف'), findsOneWidget);
    });

    testWidgets('7. a lockout says so in its own words', (tester) async {
      final provider = _RecordingProvider(failWith: 'HANDOVER_RETRY_LATER');
      addTearDown(provider.dispose);
      await tester.pumpWidget(_app(provider));

      await tester.enterText(_field, '815594');
      await tester.pump();
      await tester.tap(_confirm);
      await tester.pumpAndSettle();

      expect(find.textContaining('محاولات كثيرة'), findsOneWidget);
    });
  });

  group('an accepted code', () {
    testWidgets('8. is sent exactly as typed', (tester) async {
      final provider = _RecordingProvider();
      addTearDown(provider.dispose);
      await tester.pumpWidget(_app(provider));

      await tester.enterText(_field, '815594');
      await tester.pump();
      await tester.tap(_confirm);
      await tester.pumpAndSettle();

      expect(provider.submitted, ['815594']);
    });
  });

  testWidgets('9. non-digits never enter the field', (tester) async {
    final provider = _RecordingProvider();
    addTearDown(provider.dispose);
    await tester.pumpWidget(_app(provider));

    await tester.enterText(_field, '81a5b9');
    await tester.pump();

    expect(tester.widget<TextField>(_field).controller!.text, '8159');
    expect(tester.widget<FilledButton>(_confirm).onPressed, isNull);
  });
}
