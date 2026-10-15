import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestionale_radio/antenna_dossier_screen.dart';
import 'package:gestionale_radio/services/dossier_repository.dart';

void main() {
  testWidgets(
    'mobile dossier shows identity and immutable revision comparison',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = DossierRepository(
        owner: () => 'qa',
        request: (path, {method = 'GET', body}) async => {
          'name': 'Ponte radio Lecce',
          'antennaId': 'a',
          'version': 2,
          'fetchedAt': '2026-10-15T00:00:00Z',
          'canManage': false,
          'identity': {'model': 'Radio X'},
          'history': [],
          'configuration': [
            {
              'label': 'Prima',
              'values': {'potenza': '10'},
              'reason': 'Installazione',
              'createdAt': '2026-10-01T00:00:00Z',
            },
            {
              'label': 'Dopo',
              'values': {'potenza': '12'},
              'reason': 'Verifica',
              'createdAt': '2026-10-02T00:00:00Z',
            },
          ],
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: AntennaDossierScreen(antennaId: 'a', repository: repo),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Ponte radio Lecce'), findsOneWidget);
      expect(find.text('Radio X'), findsOneWidget);
      await tester.ensureVisible(find.text('Configurazioni'));
      await tester.tap(find.text('Configurazioni'));
      await tester.pumpAndSettle();
      expect(find.text('10 → 12'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
