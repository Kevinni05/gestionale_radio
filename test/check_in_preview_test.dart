import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestionale_radio/features/tasks/check_in_preview.dart';

void main() {
  testWidgets(
    'preview explains distance and poor GPS; cancellation never confirms',
    (tester) async {
      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await confirmCheckIn(
                    context,
                    antenna: 'Impianto QA',
                    accuracy: 150,
                    distance: 820,
                  );
                },
                child: const Text('Check-in'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Check-in'));
      await tester.pumpAndSettle();
      expect(find.text('Distanza dall’impianto: 820 m'), findsOneWidget);
      expect(find.text('Accuratezza GPS: circa 150 m'), findsOneWidget);
      expect(find.textContaining('Il segnale è impreciso'), findsOneWidget);
      await tester.tap(find.text('Annulla e riprova'));
      await tester.pumpAndSettle();
      expect(result, false);
      await tester.tap(find.text('Check-in'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Invia posizione'));
      await tester.pumpAndSettle();
      expect(result, true);
    },
  );
}
