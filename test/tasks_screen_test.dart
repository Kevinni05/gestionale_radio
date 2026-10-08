import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestionale_radio/tasks_screen.dart';
import 'package:gestionale_radio/theme/radiotech_theme.dart';

void main() {
  testWidgets(
    'notification targets remain visible when the report is under review',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: RadioTechTheme.dark,
          home: TasksScreen(
            highlightTaskId: 'review',
            loadTasks: () async => [
              {
                'id': 'active',
                'title': 'Intervento attivo',
                'status': 'ASSIGNED',
              },
              {
                'id': 'review',
                'title': 'Report dalla notifica',
                'status': 'REPORT_SUBMITTED',
              },
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Report dalla notifica'), findsOneWidget);
      final targetCard = find.ancestor(
        of: find.text('Report dalla notifica'),
        matching: find.byType(Card),
      );
      expect(
        tester.widget<Card>(targetCard).shape,
        isA<RoundedRectangleBorder>(),
      );
      expect(
        tester.getTopLeft(find.text('Report dalla notifica')).dy,
        lessThan(tester.getTopLeft(find.text('Intervento attivo')).dy),
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'searches assignments and switches to reports under review on small screens',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: RadioTechTheme.dark,
          home: TasksScreen(
            loadTasks: () async => [
              {
                'id': 't1',
                'title': 'Backhaul Bari',
                'status': 'ASSIGNED',
                'priority': 'HIGH',
              },
              {
                'id': 't2',
                'title': 'Verifica Lecce',
                'status': 'REPORT_SUBMITTED',
              },
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Backhaul Bari'), findsOneWidget);
      expect(find.text('Verifica Lecce'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.enterText(find.byType(TextField), 'assente');
      await tester.pump();
      expect(find.text('Nessun incarico per questo filtro.'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '');
      await tester.tap(find.widgetWithText(ChoiceChip, 'In revisione'));
      await tester.pumpAndSettle();
      expect(find.text('Verifica Lecce'), findsOneWidget);
      expect(find.text('Accetta incarico'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('a failed request exposes retry and recovers', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: TasksScreen(
          loadTasks: () async {
            if (calls++ == 0) throw Exception('network unavailable');
            return [];
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Riprova'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('Nessun incarico per questo filtro.'), findsOneWidget);
  });
}
