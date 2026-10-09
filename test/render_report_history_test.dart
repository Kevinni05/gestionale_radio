import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestionale_radio/report_history_screen.dart';
import 'package:gestionale_radio/services/app_navigation.dart';
import 'package:gestionale_radio/services/report_document_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'reports remain readable when the supplementary task request fails',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: OperatorHistoryScreen(
            request: (path, {method = 'GET', body}) async {
              if (path.contains('/tasks')) throw StateError('Server in avvio');
              return [
                {
                  'id': 'report',
                  'taskTitle': 'Intervento da Render',
                  'submittedAt': '2026-10-08T10:00:00Z',
                },
              ];
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('1 interventi registrati'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Intervento da Render'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Intervento da Render'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'standalone reports with empty task IDs are distinct and refresh after submission',
    (tester) async {
      var updated = false;
      await tester.pumpWidget(
        MaterialApp(
          home: OperatorHistoryScreen(
            request: (path, {method = 'GET', body}) async =>
                path.contains('/tasks')
                ? []
                : [
                    {
                      'id': 'first',
                      'taskId': '',
                      'taskTitle': 'Primo rapporto',
                    },
                    if (updated)
                      {
                        'id': 'second',
                        'taskId': '',
                        'taskTitle': 'Secondo rapporto',
                      },
                  ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('1 interventi registrati'), findsOneWidget);
      updated = true;
      AppNavigation.refreshTasks();
      await tester.pumpAndSettle();
      expect(find.text('2 interventi registrati'), findsOneWidget);
      expect(find.text('Primo rapporto'), findsOneWidget);
      expect(find.text('Secondo rapporto'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a failed refresh displays a retry without an unhandled exception',
    (tester) async {
      var fail = false;
      await tester.pumpWidget(
        MaterialApp(
          home: OperatorHistoryScreen(
            request: (path, {method = 'GET', body}) async {
              if (fail) throw StateError('Connessione assente');
              return [];
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      fail = true;
      await tester.tap(find.byTooltip('Aggiorna storico'));
      await tester.pumpAndSettle();
      expect(find.text('Caricamento non riuscito. Riprova'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'a missing historical PDF does not hide another available original',
    () async {
      final missing = 'radiotech-file:${'a' * 64}',
          available = 'radiotech-file:${'b' * 64}';
      final original = Uint8List.fromList('%PDF-1.7 original'.codeUnits);
      final reads = <String>[];
      final pdf = await ReportDocumentService.summary(
        {
          'pdfUrl': missing,
          'attachments': [available],
        },
        readFile: (ref) async {
          reads.add(ref);
          if (ref == missing) {
            throw StateError('Allegato locale non più disponibile');
          }
          return original;
        },
      );
      expect(pdf, orderedEquals(original));
      expect(reads, [missing, available]);
    },
  );

  test(
    'a lost original can be exported as a PDF reconstructed from stored report data',
    () async {
      final pdf = await ReportDocumentService.summary({
        'id': 'old-report',
        'taskTitle': 'Ripristino collegamento',
        'submittedAt': '2026-10-08T10:00:00Z',
        'operatorNotes': 'Intervento registrato',
        'attachments': ['radiotech-file:${'c' * 64}'],
      }, readFile: (_) async => throw StateError('File perso durante deploy'));
      expect(ReportDocumentService.isPdf(pdf), isTrue);
      expect(pdf.length, greaterThan(10000));
    },
  );
}
