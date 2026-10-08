import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestionale_radio/pro_suite_screen.dart';

void main() {
  testWidgets(
    'Pro catalog retries after failure and long records fit large text on a phone',
    (tester) async {
      tester.view.physicalSize = const Size(320, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      bool fail = true;
      Future<dynamic> load(String path) async {
        if (fail) throw StateError('Rete assente');
        if (path == 'catalog') {
          return [
            {
              'id': 'clients',
              'title': 'Clienti e contatti',
              'writable': true,
              'fields': [
                {
                  'key': 'name',
                  'label': 'Ragione sociale',
                  'type': 'text',
                  'required': true,
                },
              ],
              'actions': [],
            },
          ];
        }
        return {
          'records': [
            {
              'id': 'c1',
              'name':
                  'Azienda con denominazione molto lunga e descrizione operativa estesa',
              'version': 1,
              'status': 'ACTIVE',
              'summary': {'Disponibile': 4},
            },
          ],
          'partial': false,
        };
      }

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.7)),
            child: ProSuiteScreen(loadResource: load),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Rete assente'), findsOneWidget);
      fail = false;
      await tester.tap(find.byIcon(Icons.refresh));
      await tester.pumpAndSettle();
      expect(find.textContaining('Azienda con denominazione'), findsOneWidget);
      expect(find.text('Disponibile: 4'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
