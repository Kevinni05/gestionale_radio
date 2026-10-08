import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestionale_radio/theme/radiotech_theme.dart';
import 'package:gestionale_radio/widgets/home_calendar.dart';
import 'package:gestionale_radio/widgets/radiotech_clock.dart';

void main() {
  testWidgets(
    'clock updates seconds, date rollover and resumes without dashboard rebuilds',
    (tester) async {
      var now = DateTime(2026, 10, 6, 23, 59, 59);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: RadioTechClock(now: () => now)),
        ),
      );
      expect(find.text('6 Ottobre 2026 - 23:59:59'), findsOneWidget);
      now = DateTime(2026, 10, 7);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('7 Ottobre 2026 - 00:00:00'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      now = DateTime(2026, 10, 7, 9, 15, 22);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('7 Ottobre 2026 - 00:00:00'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.text('7 Ottobre 2026 - 09:15:22'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('calendar navigates years and leap months and returns to today', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: RadioTechTheme.dark,
        home: Scaffold(
          body: SingleChildScrollView(
            child: HomeCalendar(
              tasks: const [],
              now: DateTime(2028, 1, 31),
              onOpenTask: (_) {},
              onOpenAgenda: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Mese precedente'));
    await tester.pumpAndSettle();
    expect(find.text('Dicembre 2027'), findsOneWidget);
    await tester.tap(find.byTooltip('Mese successivo'));
    await tester.tap(find.byTooltip('Mese successivo'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('calendar-day-2028-2-29')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('calendar-day-2028-2-30')), findsNothing);
    await tester.tap(find.widgetWithText(TextButton, 'Oggi'));
    await tester.pumpAndSettle();
    expect(find.text('Gennaio 2028'), findsOneWidget);
    expect(find.text('31 Gennaio 2028'), findsOneWidget);
  });

  for (final size in [
    const Size(320, 900),
    const Size(740, 360),
    const Size(1024, 900),
  ]) {
    testWidgets(
      'calendar filters real tasks, opens selected activity and fits large text at $size',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        String? opened;
        await tester.pumpWidget(
          MaterialApp(
            theme: RadioTechTheme.dark,
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(1.7)),
              child: Scaffold(
                body: SingleChildScrollView(
                  padding: const EdgeInsets.all(18),
                  child: HomeCalendar(
                    now: DateTime(2026, 10, 6),
                    onOpenTask: (id) => opened = id,
                    onOpenAgenda: () {},
                    tasks: const [
                      {
                        'id': 'active',
                        'title': 'Ripristino collegamento radio',
                        'status': 'IN_PROGRESS',
                        'dueAt': '2026-10-10T12:00:00',
                      },
                      {
                        'id': 'review',
                        'title': 'Rapporto da verificare',
                        'status': 'REPORT_SUBMITTED',
                        'dueAt': '2026-10-10T13:00:00',
                      },
                      {
                        'id': 'undated',
                        'title': 'Sopralluogo senza data',
                        'status': 'ASSIGNED',
                      },
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(
          find.byKey(const ValueKey('calendar-day-2026-10-10')),
        );
        await tester.tap(find.byKey(const ValueKey('calendar-day-2026-10-10')));
        await tester.pumpAndSettle();
        expect(find.text('10 Ottobre 2026'), findsOneWidget);
        expect(find.text('Rapporto da verificare'), findsNothing);
        await tester.ensureVisible(
          find.text('Ripristino collegamento radio').first,
        );
        await tester.tap(find.text('Ripristino collegamento radio').first);
        expect(opened, 'active');
        await tester.ensureVisible(
          find.widgetWithText(ChoiceChip, 'In revisione'),
        );
        await tester.tap(find.widgetWithText(ChoiceChip, 'In revisione'));
        await tester.pumpAndSettle();
        expect(find.text('Rapporto da verificare'), findsOneWidget);
        await tester.ensureVisible(find.byType(TextField));
        await tester.enterText(find.byType(TextField), 'assente');
        await tester.pumpAndSettle();
        expect(
          find.text('Nessuna attività per questo giorno.'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
