import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestionale_radio/report_closure_screen.dart';
import 'package:gestionale_radio/theme/radiotech_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('keeps the urgent central alert in the report payload', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Map<String, dynamic>? submitted;
    await tester.pumpWidget(
      MaterialApp(
        theme: RadioTechTheme.dark,
        home: ReportClosureScreen(
          checklistResults: const {},
          antennaId: 'ANT-1',
          submitReport: (report, _, _) async {
            submitted = report;
            return {
              'report': {'id': 'report-1'},
            };
          },
          locate: () async => null,
          loadIdentity: () async => {
            'operatorName': 'Operatore',
            'antennaName': 'Antenna',
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Invia segnalazione alla centrale operativa'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    final alertToggle = find.byType(Switch);
    await tester.scrollUntilVisible(
      alertToggle,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    tester.widget<Switch>(alertToggle).onChanged!(true);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).last,
      'Pericolo immediato sul sito.',
    );
    await tester.pump();

    expect(submitted, isNull);
    expect(find.byKey(const ValueKey('submit-report')), findsOneWidget);
  });
}
