import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestionale_radio/agenda_screen.dart';
import 'package:gestionale_radio/tasks_screen.dart';
import 'package:gestionale_radio/theme/radiotech_theme.dart';

void main() {
  final now = DateTime(2026, 10, 5, 10);
  Future<List<Map<String, dynamic>>> load() async => [
    {
      'id': 'today',
      'title': 'Ispezione Bari',
      'status': 'ASSIGNED',
      'dueAt': DateTime(2026, 10, 5, 11).toIso8601String(),
    },
    {
      'id': 'week',
      'title': 'Ispezione Lecce',
      'status': 'ASSIGNED',
      'dueAt': DateTime(2026, 10, 7, 11).toIso8601String(),
    },
    {
      'id': 'overdue',
      'title': 'Intervento scaduto',
      'status': 'IN_PROGRESS',
      'dueAt': DateTime(2026, 10, 4, 11).toIso8601String(),
    },
    {
      'id': 'undated',
      'title': 'Pianificazione da definire',
      'status': 'ASSIGNED',
    },
    {
      'id': 'approved',
      'title': 'Intervento approvato',
      'status': 'APPROVED',
      'dueAt': DateTime(2026, 10, 5, 11).toIso8601String(),
    },
    {
      'id': 'review',
      'title': 'Intervento in revisione',
      'status': 'REPORT_SUBMITTED',
      'dueAt': DateTime(2026, 10, 5, 11).toIso8601String(),
    },
  ];
  testWidgets(
    'agenda filters dates and opens the assignment on a narrow screen',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: RadioTechTheme.dark,
          home: AgendaScreen(loadTasks: load, now: now),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Ispezione Bari'), findsOneWidget);
      expect(find.text('Intervento approvato'), findsNothing);
      expect(find.text('Intervento in revisione'), findsNothing);
      await tester.tap(find.widgetWithText(ChoiceChip, '7 giorni'));
      await tester.pumpAndSettle();
      expect(find.text('2 incarichi per questo filtro'), findsOneWidget);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Scaduti'));
      await tester.pumpAndSettle();
      expect(find.text('Intervento scaduto'), findsOneWidget);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Senza data'));
      await tester.pumpAndSettle();
      expect(find.text('Pianificazione da definire'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'assente');
      await tester.pump();
      expect(
        find.text('Nessun incarico previsto per questo filtro.'),
        findsOneWidget,
      );
      await tester.enterText(find.byType(TextField), '');
      await tester.pump();
      await tester.ensureVisible(find.text('Apri incarico'));
      await tester.tap(find.text('Apri incarico'));
      await tester.pumpAndSettle();
      expect(find.byType(TasksScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'agenda recovers after a network error and supports larger text',
    (tester) async {
      var calls = 0;
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: RadioTechTheme.dark,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
          home: AgendaScreen(
            now: now,
            loadTasks: () async {
              if (calls++ == 0) throw Exception('offline');
              return load();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Riprova'));
      await tester.pumpAndSettle();
      expect(find.text('Ispezione Bari'), findsOneWidget);
      expect(calls, 2);
      expect(tester.takeException(), isNull);
    },
  );
}
