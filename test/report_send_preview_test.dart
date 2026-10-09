import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gestionale_radio/report_closure_screen.dart';
import 'package:gestionale_radio/services/maintenance_report_pdf.dart';
import 'package:gestionale_radio/theme/radiotech_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final pixel = Uint8List.fromList(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgYGD4DwABBAEAX+XDSwAAAABJRU5ErkJggg==',
    ),
  );
  test(
    'professional PDF includes branding, photographic pages and signature',
    () async {
      final bytes = await MaintenanceReportPdf.build(
        antennaId: 'ANT-TEST',
        antennaName: 'Ponte radio Sanarica',
        operatorName: 'Operatore di collaudo',
        submittedAt: DateTime(2026, 10, 6, 18, 30, 25),
        taskId: 'task-test',
        notes: 'Ripristinato il collegamento. Verificate continuità e potenza.',
        checklist: {'Cablaggio e alimentazione': true, 'Ventilazione': false},
        measurements: {'Potenza RF (W)': 250},
        materials: [
          {'name': 'Fusibile 5A', 'quantity': 1},
        ],
        photos: [ReportPhoto('Foto impianto.png', pixel)],
        signature: pixel,
      );
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
      expect(bytes.length, greaterThan(10000));
      await Directory('artifacts').create(recursive: true);
      await File('artifacts/qa-professional-report.pdf').writeAsBytes(bytes);
    },
  );
  for (final fail in [false, true]) {
    testWidgets(
      'report send ${fail ? 'failure unlocks retry' : 'success shows acknowledgement and closes'} with reduced motion',
      (tester) async {
        tester.view.physicalSize = const Size(320, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var calls = 0;
        final pending = Completer<dynamic>();
        await tester.pumpWidget(
          MaterialApp(
            theme: RadioTechTheme.dark,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                disableAnimations: true,
                textScaler: const TextScaler.linear(1.6),
              ),
              child: child!,
            ),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ReportClosureScreen(
                        checklistResults: const {},
                        antennaId: 'ANT-TEST',
                        resumeReport: () async => null,
                        locate: () async => null,
                        loadIdentity: () async => {
                          'antennaName': 'Ponte radio Sanarica',
                          'operatorName': 'Operatore di collaudo',
                        },
                        loadInventory: () async => [
                          {
                            'id': 'inventory-001',
                            'sku': 'RF-001',
                            'name': 'Connettore N',
                            'quantity': 37,
                          },
                          {
                            'id': 'inventory-002',
                            'sku': 'RF-002',
                            'name': 'Cavo coassiale',
                            'quantity': 3,
                          },
                        ],
                        submitReport: (report, files, bytes) async {
                          calls++;
                          expect(report['materialsUsed'], [
                            {
                              'inventoryId': 'inventory-002',
                              'sku': 'RF-002',
                              'name': 'Cavo coassiale',
                              'quantity': 1,
                            },
                          ]);
                          expect(
                            bytes.keys.any((n) => n.endsWith('.pdf')),
                            true,
                          );
                          return pending.future;
                        },
                      ),
                    ),
                  ),
                  child: const Text('Apri report'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Apri report'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('report-material-search')),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.enterText(
          find.byKey(const ValueKey('report-material-search')),
          'RF-002',
        );
        await tester.pumpAndSettle();
        expect(find.text('Antennino'), findsNothing);
        expect(find.text('Fusibile 5A'), findsNothing);
        await tester.ensureVisible(
          find.byKey(const ValueKey('material-increase-inventory-002')),
        );
        await tester.tap(
          find.byKey(const ValueKey('material-increase-inventory-002')),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('report-notes')),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.enterText(
          find.byKey(const ValueKey('report-notes')),
          'Ripristinato e verificato il collegamento.',
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('submit-report')));
        await tester.runAsync(() async {
          for (var i = 0; i < 100 && calls == 0; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 50));
          }
        });
        await tester.pump();
        expect(calls, 1);
        // A second tap while uploading must never duplicate the submission.
        await tester.tap(find.byKey(const ValueKey('submit-report')));
        await tester.pump();
        expect(calls, 1);
        if (fail) {
          pending.completeError(StateError('Permesso insufficiente'));
        } else {
          pending.complete({
            'report': {
              'id': 'report-test',
              'submittedAt': '2026-10-06T16:30:25Z',
            },
            'verificationUrl':
                'https://example.test/reports/verify/report-test',
          });
        }
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (fail) {
          expect(
            find.byKey(const ValueKey('report-send-success')),
            findsNothing,
          );
          expect(find.textContaining('Permesso insufficiente'), findsWidgets);
          final button = tester.widget<ElevatedButton>(
            find.byKey(const ValueKey('submit-report')),
          );
          expect(button.onPressed, isNotNull);
        } else {
          expect(
            find.byKey(const ValueKey('report-send-success')).hitTestable(),
            findsOneWidget,
          );
          expect(find.text('Report inviato'), findsOneWidget);
          expect(find.text('Riferimento: report-test'), findsOneWidget);
          await tester.tap(find.byKey(const ValueKey('close-report-success')));
          await tester.pumpAndSettle();
          expect(find.text('Apri report'), findsOneWidget);
          expect(find.byType(ReportClosureScreen), findsNothing);
        }
      },
    );
  }
}
