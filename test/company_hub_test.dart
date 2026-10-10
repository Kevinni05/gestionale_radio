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
  testWidgets('preventive planning shows personal evidence without chat', (
    tester,
  ) async {
    Future<dynamic> request(
      String path, {
      String method = 'GET',
      Map<String, dynamic>? body,
    }) async {
      if (path == '/ai/insights') return insights;
      fail('Unexpected request: $path');
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
    expect(find.text('Pianificazione preventiva'), findsOneWidget);
    expect(find.text('Assistente AI'), findsNothing);
    expect(find.text('Chiedi all’assistente'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('planning shows an explicit error on a small viewport', (
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
      fail('Unexpected request: $path');
    }

    await tester.pumpWidget(
      MaterialApp(
        theme: RadioTechTheme.dark,
        home: AiHubScreen(request: request),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Pianificazione non disponibile. Verifica la rete e riprova.'),
      findsOneWidget,
    );
    expect(find.text('Assistente AI'), findsNothing);
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
      Future<dynamic> request(
        String path, {
        String method = 'GET',
        Map<String, dynamic>? body,
      }) async {
        if (path == '/ai/insights') return insights;
        fail('Unexpected request: $path');
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
      identities.add(nextIdentity);
      await tester.pumpAndSettle();
      expect(find.byType(AiHubScreen), findsNothing);
      expect(find.text('Apri AI'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
