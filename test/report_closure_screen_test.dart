import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestionale_radio/report_closure_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gestionale_radio/theme/radiotech_theme.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('operator can add and remove a numeric measurement row', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ReportClosureScreen(checklistResults: {}, antennaId: 'ANT-TEST'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Aggiungi misura'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Aggiungi misura'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aggiungi misura'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('measurement-name-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('measurement-value-0')), findsOneWidget);

    await tester.ensureVisible(find.byTooltip('Rimuovi misura'));
    await tester.tap(find.byTooltip('Rimuovi misura'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('measurement-name-0')), findsNothing);
  });

  for (final width in [320.0, 768.0]) {
    testWidgets('report sections and send controls fit large text at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: RadioTechTheme.dark,
          home: const MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(1.6)),
            child: ReportClosureScreen(
              antennaId: 'ANT-TEST',
              checklistResults: {
                'Controllo del collegamento e del trasmettitore con descrizione lunga':
                    true,
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey('submit-report')).hitTestable(),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('report-notes')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(
        find.byKey(const ValueKey('report-notes')),
        'Verificato il collegamento e ripristinato il servizio.',
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      for (final label in [
        'ALLEGATI FOTO',
        'MISURE TECNICHE',
        'PEZZI SOSTITUITI',
        'FIRMA',
      ]) {
        await tester.scrollUntilVisible(
          find.text(label),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    });
  }
}
