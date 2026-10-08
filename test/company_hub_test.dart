import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestionale_radio/ai_hub_screen.dart';
import 'package:gestionale_radio/workforce_screen.dart';
import 'package:gestionale_radio/theme/radiotech_theme.dart';
import 'package:gestionale_radio/services/session_route_guard.dart';

void main() {
  final insights = <String, dynamic>{
    'scope': 'PERSONAL',
    'assetsObserved': 1,
    'highRiskAssets': 1,
    'activeTasks': 1,
    'overdueTasks': 0,
    'notice': 'Indicatori, non probabilità di guasto.',
    'risks': [
      {
        'assetId': 'a1',
        'name': 'Ponte Bari',
        'score': 70,
        'level': 'HIGH',
        'dataQuality': 'LIMITED',
        'reasons': ['Asset offline'],
        'recommendation': 'Confermare con il responsabile',
        'estimatedMaintenanceAt': null,
      },
    ],
  };
  testWidgets(
    'AI shows personal evidence and chat sends only opted-in context',
    (tester) async {
      Map<String, dynamic>? submitted;
      Future<dynamic> request(
        String path, {
        String method = 'GET',
        Map<String, dynamic>? body,
      }) async {
        if (path == '/ai/insights') return insights;
        if (path == '/ai/status') {
          return {'enabled': true, 'model': 'test-local'};
        }
        submitted = body;
        return {'answer': 'Risposta aziendale verificabile'};
      }

      await tester.pumpWidget(
        MaterialApp(
          theme: RadioTechTheme.dark,
          home: AiHubScreen(request: request),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Ponte Bari'), findsOneWidget);
      expect(
        find.text('Storico insufficiente per stimare una data.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Assistente AI'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.widgetWithText(TextField, 'Chiedi all’assistente'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Chiedi all’assistente'),
        'Prepara un briefing',
      );
      await tester.ensureVisible(find.text('Invia messaggio'));
      await tester.tap(find.text('Invia messaggio'));
      await tester.pumpAndSettle();
      expect(submitted?['includeOperationalContext'], false);
      expect(submitted?['message'], 'Prepara un briefing');
      expect(find.text('Risposta aziendale verificabile'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('chat stays usable when analysis fails and small viewport fits', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Future<dynamic> request(
      String path, {
      String method = 'GET',
      Map<String, dynamic>? body,
    }) async {
      if (path == '/ai/insights') {
        throw StateError('analisi temporaneamente assente');
      }
      return {'enabled': true, 'model': 'local'};
    }

    await tester.pumpWidget(
      MaterialApp(
        theme: RadioTechTheme.dark,
        home: AiHubScreen(request: request),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Analisi non disponibile. Puoi comunque usare la chat.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Assistente AI'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Invia messaggio'));
    expect(
      tester
          .widget<ElevatedButton>(
            find.widgetWithText(ElevatedButton, 'Invia messaggio'),
          )
          .onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'worker shifts use optimistic version and never load other peoples data',
    (tester) async {
      final paths = <String>[];
      Map<String, dynamic>? operation;
      String state = 'OFF_DUTY';
      int version = 0;
      Future<dynamic> request(
        String path, {
        String method = 'GET',
        Map<String, dynamic>? body,
      }) async {
        paths.add(path);
        if (path == '/workforce/signals') return <dynamic>[];
        if (method == 'PUT') {
          operation = body;
          state = 'ACTIVE';
          version++;
        }
        return {
          'status': state,
          'version': version,
          'readiness': 'READY',
          'workMinutes': 0,
          'restMinutes': 0,
        };
      }

      await tester.pumpWidget(
        MaterialApp(
          theme: RadioTechTheme.dark,
          home: WorkforceScreen(request: request, canManage: false),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Inizia turno'));
      await tester.pumpAndSettle();
      expect(operation?['action'], 'START');
      expect(operation?['expectedVersion'], 0);
      expect(operation?['operationId'].toString().length, 24);
      expect(paths, isNot(contains('/workforce/shifts')));
      expect(find.text('Inizia pausa'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  for (final nextIdentity in <String?>[null, 'another-account']) {
    testWidgets('account change to $nextIdentity disposes private chat', (
      tester,
    ) async {
      final identities = StreamController<String?>();
      addTearDown(identities.close);
      final reply = Completer<dynamic>();
      Future<dynamic> request(
        String path, {
        String method = 'GET',
        Map<String, dynamic>? body,
      }) async {
        if (path == '/ai/insights') return insights;
        if (path == '/ai/status') return {'enabled': true, 'model': 'local'};
        return reply.future;
      }

      await tester.pumpWidget(
        MaterialApp(
          theme: RadioTechTheme.dark,
          home: SessionRouteGuard(
            identities: identities.stream,
            initialIdentity: 'original-account',
            child: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => AiHubScreen(request: request),
                    ),
                  ),
                  child: const Text('Apri AI'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Apri AI'));
      await tester.pumpAndSettle();
      identities.add('original-account');
      await tester.pumpAndSettle();
      expect(find.byType(AiHubScreen), findsOneWidget);
      await tester.tap(find.text('Assistente AI'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.widgetWithText(TextField, 'Chiedi all’assistente'),
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Chiedi all’assistente'),
        'Informazioni riservate',
      );
      await tester.ensureVisible(find.text('Invia messaggio'));
      await tester.tap(find.text('Invia messaggio'));
      await tester.pump();
      identities.add(nextIdentity);
      await tester.pumpAndSettle();
      expect(find.byType(AiHubScreen), findsNothing);
      reply.complete({'answer': 'Risposta della sessione precedente'});
      await tester.pumpAndSettle();
      expect(find.text('Risposta della sessione precedente'), findsNothing);
      expect(find.text('Apri AI'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
