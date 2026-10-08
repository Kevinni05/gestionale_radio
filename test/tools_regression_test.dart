import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestionale_radio/calculator_screen.dart';
import 'package:gestionale_radio/telco_tools_screen.dart';
import 'package:gestionale_radio/theme/radiotech_theme.dart';

void main() {
  for (final title in [
    'IP / CIDR / VLSM',
    'VLAN',
    '5G / LTE',
    'Collegamento radio',
    'Fibra / PON',
    'Manutenzione stazioni',
    'Energia / DC',
    'Lista di controllo',
    'Report tecnico',
  ]) {
    testWidgets('Telco opens $title without overflow on a small screen', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(theme: RadioTechTheme.dark, home: const TelcoToolsScreen()),
      );
      await tester.pumpAndSettle();
      final tile = find.descendant(
        of: find.byType(ListView).last,
        matching: find.text(title),
      );
      await tester.scrollUntilVisible(
        tile,
        150,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.ensureVisible(tile);
      await tester.pumpAndSettle();
      await tester.tap(tile);
      await tester.pumpAndSettle();
      expect(
        find.byKey(
          ValueKey(
            [
                  'IP / CIDR / VLSM',
                  'VLAN',
                  '5G / LTE',
                  'Collegamento radio',
                  'Fibra / PON',
                  'Manutenzione stazioni',
                  'Energia / DC',
                  'Lista di controllo',
                  'Report tecnico',
                ].indexOf(title) +
                1,
          ),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      for (var i = 0; i < 8; i++) {
        await tester.drag(find.byType(ListView).last, const Offset(0, -400));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    });
  }
  testWidgets(
    'CIDR calculator produces a known subnet and rejects invalid addresses',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(theme: RadioTechTheme.dark, home: const TelcoToolsScreen()),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('IP / CIDR / VLSM'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('CALCOLA SUBNET'));
      await tester.tap(find.text('CALCOLA SUBNET'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Rete: 192.168.1.0'), findsOneWidget);
      expect(find.textContaining('Host utilizzabili: 254'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, '999.1.1.1/24');
      await tester.tap(find.text('CALCOLA SUBNET'));
      await tester.pumpAndSettle();
      expect(find.text('CIDR non valido.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'calculator preserves arithmetic, scientific mode and error recovery',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(theme: RadioTechTheme.dark, home: const CalculatorScreen()),
      );
      for (final key in ['2', '+', '3', '=']) {
        await tester.ensureVisible(find.text(key).last);
        await tester.tap(find.text(key).last);
        await tester.pumpAndSettle();
      }
      expect(find.text('5'), findsNWidgets(2));
      for (final key in ['AC', '1', '÷', '0', '=']) {
        await tester.ensureVisible(find.text(key).last);
        await tester.tap(find.text(key).last);
        await tester.pumpAndSettle();
      }
      expect(find.text('Errore'), findsOneWidget);
      await tester.tap(find.text('AC'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('SCIENTIFICA').first);
      await tester.pumpAndSettle();
      expect(find.text('sin'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
