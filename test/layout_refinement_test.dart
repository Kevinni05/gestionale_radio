import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestionale_radio/theme/radiotech_theme.dart';
import 'package:gestionale_radio/theme/radiotech_glass.dart';
import 'package:gestionale_radio/widgets/calendar_notes.dart';
import 'package:gestionale_radio/report_history_screen.dart';
import 'package:gestionale_radio/services/report_document_service.dart';
import 'package:gestionale_radio/pro_suite_screen.dart';

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'calendar notes and enterprise controls remain inside cards at scale $scale',
      (tester) async {
        tester.view.physicalSize = const Size(320, 850);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        Widget app(Widget child) => MaterialApp(
          theme: RadioTechTheme.dark,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: child,
        );
        await tester.pumpWidget(
          app(
            Scaffold(
              body: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  CalendarNotes(
                    request: (path, {method = 'GET', body}) async => [],
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final card = tester.getRect(find.byType(RadioTechGlass));
        final field = tester.getRect(find.byType(TextField));
        expect(field.left, greaterThanOrEqualTo(card.left + 15));
        expect(field.right, lessThanOrEqualTo(card.right - 15));
        expect(tester.takeException(), isNull);
        for (var i = 0; i < 4; i++) {
          await tester.drag(find.byType(ListView).first, const Offset(0, -280));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(
          app(
            ProSuiteScreen(
              loadResource: (path) async => path == 'catalog'
                  ? [
                      {
                        'id': 'plans',
                        'title':
                            'Pianificazione interventi sul collegamento della sede principale',
                        'writable': true,
                        'fields': [
                          {'key': 'name', 'label': 'Nome', 'type': 'text'},
                          {
                            'key': 'notes',
                            'label': 'Note operative',
                            'type': 'text',
                          },
                        ],
                        'actions': ['GENERATE', 'ARCHIVE'],
                      },
                    ]
                  : {
                      'records': [
                        {
                          'id': 'p1',
                          'name':
                              'Manutenzione programmata di tutti gli apparati nella sala della sede aziendale',
                          'status': 'ACTIVE',
                          'version': 1,
                          'notes':
                              'Descrizione dettagliata delle operazioni e dei controlli da effettuare sul posto.',
                        },
                      ],
                    },
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (var i = 0; i < 5; i++) {
          await tester.drag(find.byType(ListView).first, const Offset(0, -250));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      },
    );
  }
  testWidgets(
    'history groups a completed task and downloads only its summary PDF',
    (tester) async {
      tester.view.physicalSize = const Size(320, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final pdf = Uint8List.fromList('%PDF-1.4 sample'.codeUnits);
      Uint8List? saved;
      String? filename;
      await tester.pumpWidget(
        MaterialApp(
          theme: RadioTechTheme.dark,
          home: OperatorHistoryScreen(
            request: (path, {method = 'GET', body}) async =>
                path.endsWith('/reports')
                ? [
                    {
                      'id': 'r1',
                      'taskId': 't1',
                      'status': 'APPROVED',
                      'submittedAt': '2026-10-07T10:00:00Z',
                      'operatorNotes': 'Lavoro effettuato',
                      'attachments': ['photo.jpg', 'report.pdf'],
                    },
                  ]
                : [
                    {
                      'id': 't1',
                      'title':
                          'Compito assegnato con un titolo lungo per verificare l’allineamento dei contenuti',
                      'status': 'COMPLETED',
                      'completedAt': '2026-10-07T10:00:00Z',
                    },
                  ],
            loadPdf: (record) async => pdf,
            savePdf: (bytes, name) async {
              saved = bytes;
              filename = name;
              return true;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('1 interventi registrati'), findsOneWidget);
      expect(find.textContaining('Visualizza allegato'), findsNothing);
      final button = find.byKey(const ValueKey('download-t1'));
      await tester.scrollUntilVisible(
        button,
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(saved, orderedEquals(pdf));
      expect(filename, endsWith('.pdf'));
      expect(find.text('PDF salvato nella posizione scelta.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  test(
    'summary selects original PDF bytes and never packages image attachments',
    () async {
      final image = 'radiotech-file:${'a' * 64}',
          pdf = 'radiotech-file:${'b' * 64}';
      final reads = <String>[];
      final bytes = Uint8List.fromList('%PDF-1.7 original'.codeUnits);
      final result = await ReportDocumentService.summary(
        {
          'taskId': 't1',
          'attachments': [image, pdf],
        },
        readFile: (ref) async {
          reads.add(ref);
          return ref == pdf ? bytes : Uint8List.fromList([1, 2, 3]);
        },
      );
      expect(result, orderedEquals(bytes));
      expect(reads, [pdf]);
    },
  );
  test(
    'Android PDF save opens document picker and cancellation stays a cancellation',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(ReportDocumentService.channel, (
            call,
          ) async {
            calls.add(call);
            return false;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(ReportDocumentService.channel, null),
      );
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final pdf = Uint8List.fromList('%PDF-1.4 test'.codeUnits);
      expect(await ReportDocumentService.save(pdf, 'Report.pdf'), isFalse);
      expect(calls.single.method, 'savePdf');
      expect(calls.single.arguments['bytes'], orderedEquals(pdf));
      expect(calls.single.arguments['filename'], 'Report.pdf');
    },
  );
  test(
    'report secondary text has accessible contrast on the field surface',
    () {
      final text = RadioTechTheme.muted.computeLuminance(),
          background = const Color(0xFF20212B).computeLuminance();
      expect((text + .05) / (background + .05), greaterThanOrEqualTo(4.5));
    },
  );
}
