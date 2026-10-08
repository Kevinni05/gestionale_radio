import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestionale_radio/incidents_screen.dart';

void main() {
  testWidgets('advances an incident using the deterministic next state', (
    tester,
  ) async {
    final incidents = <Map<String, dynamic>>[
      {
        'id': 'incident-1',
        'title': 'Backhaul non disponibile',
        'severity': 'HIGH',
        'status': 'DETECTED',
      },
    ];
    String? transitionedTo;

    await tester.pumpWidget(
      MaterialApp(
        home: IncidentsScreen(
          loadIncidents: () async => incidents,
          transitionIncident: (id, status) async {
            expect(id, 'incident-1');
            transitionedTo = status;
            incidents.first['status'] = status;
            return incidents.first;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Backhaul non disponibile'), findsOneWidget);
    expect(find.text('Stato: DETECTED'), findsOneWidget);
    await tester.tap(find.text('Prendi in carico'));
    await tester.pumpAndSettle();

    expect(transitionedTo, 'ACKNOWLEDGED');
    expect(find.text('Stato: Preso in carico'), findsOneWidget);
    expect(find.text('Imposta stato: assegnato'), findsOneWidget);
  });

  testWidgets('creates an incident from validated form input', (tester) async {
    Map<String, dynamic>? createdPayload;
    var incidents = <Map<String, dynamic>>[];

    await tester.pumpWidget(
      MaterialApp(
        home: IncidentsScreen(
          loadIncidents: () async => incidents,
          createIncident: (payload) async {
            createdPayload = payload;
            incidents = [
              {'id': 'incident-new', ...payload, 'status': 'DETECTED'},
            ];
            return incidents.single;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nuovo incident'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '  Power alarm  ');
    await tester.tap(find.text('Crea'));
    await tester.pumpAndSettle();

    expect(createdPayload?['title'], 'Power alarm');
    expect(createdPayload?['severity'], 'MEDIUM');
    expect(find.text('Power alarm'), findsOneWidget);
  });

  testWidgets(
    'requires root cause and resolution before resolving an incident',
    (tester) async {
      final incident = <String, dynamic>{
        'id': 'incident-resolve',
        'title': 'Power failure',
        'severity': 'CRITICAL',
        'status': 'MITIGATED',
      };
      String? rootCause;
      String? resolution;
      final transitions = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: IncidentsScreen(
            loadIncidents: () async => [incident],
            transitionIncidentWithDetails: (id, status, cause, fix) async {
              expect(id, 'incident-resolve');
              transitions.add(status);
              if (status == 'RESOLVED') {
                rootCause = cause;
                resolution = fix;
              }
              incident['status'] = status;
              return incident;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(OutlinedButton, 'Risolvi'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField).at(0),
        'Rectifier failed',
      );
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'Replaced rectifier',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Risolvi'));
      await tester.pumpAndSettle();

      expect(rootCause, 'Rectifier failed');
      expect(resolution, 'Replaced rectifier');
      expect(transitions, ['RESOLVED']);
      expect(find.text('Stato: Risolto'), findsOneWidget);
      expect(find.text('Apri analisi conclusiva'), findsOneWidget);
      await tester.tap(
        find.widgetWithText(OutlinedButton, 'Apri analisi conclusiva'),
      );
      await tester.pumpAndSettle();
      expect(transitions, ['RESOLVED', 'POST_MORTEM']);
      expect(find.text('Stato: Analisi conclusiva'), findsOneWidget);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Chiudi incidente'));
      await tester.pumpAndSettle();
      expect(transitions, ['RESOLVED', 'POST_MORTEM', 'CLOSED']);
      expect(find.text('Stato: Chiuso'), findsOneWidget);
    },
  );
}
