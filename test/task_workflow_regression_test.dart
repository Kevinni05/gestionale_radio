import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestionale_radio/tasks_screen.dart';
import 'package:gestionale_radio/models/task_summary.dart';
import 'package:gestionale_radio/services/app_navigation.dart';
import 'package:gestionale_radio/theme/radiotech_theme.dart';

void main() {
  testWidgets(
    'assignment proceeds through GPS check-in to its report and refreshes after submission',
    (tester) async {
      tester.view.physicalSize = const Size(430, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var status = 'ASSIGNED';
      final changes = <String>[];
      String? reportTask;
      await tester.pumpWidget(
        MaterialApp(
          theme: RadioTechTheme.dark,
          home: TasksScreen(
            loadTasks: () async => [
              {
                'id': 'assigned',
                'title': 'Ripristino collegamento',
                'status': status,
                'antennaId': 'asset',
              },
            ],
            changeStatus: (id, next) async {
              expect(id, 'assigned');
              changes.add(next);
              status = next;
            },
            checkIn: (id) async {
              expect(id, 'assigned');
              changes.add('CHECKED_IN');
              status = 'CHECKED_IN';
            },
            reportBuilder: (task) {
              reportTask = task.id;
              expect(task.antennaId, 'asset');
              return const Scaffold(body: Text('Test rapporto'));
            },
          ),
        ),
      );

      await tester.pumpAndSettle();
      for (final label in [
        'Accetta incarico',
        'Check-in GPS',
      ]) {
        await tester.ensureVisible(find.text(label));
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      expect(changes, ['ACCEPTED', 'CHECKED_IN', 'IN_PROGRESS']);
      await tester.ensureVisible(find.text('Compila rapporto'));
      await tester.tap(find.text('Compila rapporto'));
      await tester.pumpAndSettle();
      expect(reportTask, 'assigned');
      expect(find.text('Test rapporto'), findsOneWidget);
      status = 'REPORT_SUBMITTED';
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();
      expect(find.text('Compila rapporto'), findsNothing);
      await tester.tap(find.widgetWithText(ChoiceChip, 'In revisione'));
      await tester.pumpAndSettle();
      expect(find.text('Ripristino collegamento'), findsOneWidget);
    },
  );

  testWidgets('opens the checklist before the default intervention report', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: RadioTechTheme.dark,
        home: TasksScreen(
          loadTasks: () async => [
            {
              'id': 'checklist-task',
              'title': 'Intervento con controlli',
              'status': 'IN_PROGRESS',
              'antennaId': 'ANT-1',
              'metadata': {'checklist': 'Sicurezza\nMisure finali'},
            },
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    final reportButton = find.widgetWithText(
      ElevatedButton,
      'Compila rapporto',
    );
    await tester.scrollUntilVisible(
      reportButton,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(reportButton);
    await tester.pumpAndSettle();

    expect(find.text('CHECKLIST OPERATIVA'), findsOneWidget);
    expect(find.text('Sicurezza'), findsOneWidget);
    expect(find.text('Misure finali'), findsOneWidget);
    expect(find.text('PROCEDI ALLA FIRMA'), findsNothing);

    await tester.tap(find.text('Sicurezza'));
    await tester.tap(find.text('Misure finali'));
    await tester.pumpAndSettle();
    expect(find.text('PROCEDI ALLA FIRMA'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a notification refreshes an already open assignment list', (
    tester,
  ) async {
    var assigned = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: RadioTechTheme.dark,
        home: TasksScreen(
          loadTasks: () async => assigned
              ? [
                  {
                    'id': 'new',
                    'title': 'Nuovo incarico ricevuto',
                    'status': 'ASSIGNED',
                  },
                ]
              : [],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Nessun incarico per questo filtro.'), findsOneWidget);
    assigned = true;
    AppNavigation.refreshTasks();
    await tester.pumpAndSettle();
    expect(find.text('Nuovo incarico ricevuto'), findsOneWidget);
    expect(find.text('Accetta incarico'), findsOneWidget);
  });

  for (final width in [320.0, 430.0, 1024.0]) {
    testWidgets(
      'completed work remains actionable with aligned metrics and large text at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: RadioTechTheme.dark,
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
              child: TasksScreen(
                loadTasks: () async => [
                  {
                    'id': 'finished',
                    'title': 'Intervento completato da documentare',
                    'status': 'COMPLETATO',
                  },
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Rapporto da inviare'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('Compila rapporto'),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Compila rapporto'));
        await tester.pumpAndSettle();
        expect(find.text('Compila rapporto').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        final cards = find.byType(Card);
        final sizes = List.generate(3, (i) => tester.getSize(cards.at(i)));
        expect(sizes[0], sizes[1]);
        expect(sizes[1], sizes[2]);
      },
    );
  }

  test(
    'legacy statuses retain their execution actions and completed work awaits a report',
    () {
      expect(TaskSummary({'status': 'in corso'}).nextAction, 'REPORT');
      expect(TaskSummary({'status': 'ACCETTATO'}).nextAction, 'CHECKED_IN');
      final completed = TaskSummary({'status': 'COMPLETED'});
      expect(completed.archived, isFalse);
      expect(completed.nextAction, 'REPORT');
    },
  );
}
