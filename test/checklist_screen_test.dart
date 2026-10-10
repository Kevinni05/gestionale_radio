import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestionale_radio/checklist_screen.dart';
import 'package:gestionale_radio/report_closure_screen.dart';
import 'package:gestionale_radio/theme/radiotech_theme.dart';

void main() {
  testWidgets('passes checklist results and task identity to the report', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: RadioTechTheme.dark,
        home: const ChecklistScreen(
          checklistItems: ['Sicurezza area', 'Misure finali'],
          antennaId: 'ANT-1',
          taskId: 'task-1',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sicurezza area'));
    await tester.tap(find.text('Misure finali'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('PROCEDI ALLA FIRMA'));
    await tester.pumpAndSettle();

    final report = tester.widget<ReportClosureScreen>(
      find.byType(ReportClosureScreen),
    );
    expect(report.taskId, 'task-1');
    expect(report.antennaId, 'ANT-1');
    expect(report.checklistResults, {
      'Sicurezza area': true,
      'Misure finali': true,
    });
  });

  testWidgets('keeps the checklist action disabled until all items are done', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ChecklistScreen(
          checklistItems: ['Controllo uno', 'Controllo due'],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('COMPLETA I CONTROLLI'), findsOneWidget);
    expect(find.text('PROCEDI ALLA FIRMA'), findsNothing);
    await tester.tap(find.text('Controllo uno'));
    await tester.pumpAndSettle();
    expect(find.text('COMPLETA I CONTROLLI'), findsOneWidget);
    expect(find.text('PROCEDI ALLA FIRMA'), findsNothing);
  });
}
