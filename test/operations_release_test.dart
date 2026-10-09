import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestionale_radio/services/api_connection_status.dart';
import 'package:gestionale_radio/services/android_update_service.dart';
import 'package:gestionale_radio/widgets/api_connection_badge.dart';
import 'package:gestionale_radio/report_history_screen.dart';

void main() {
  testWidgets(
    'connection badge follows the service and stops probing in background',
    (tester) async {
      var online = true, probes = 0;
      final controller = ApiConnectionController(
        probe: () async {
          probes++;
          return online;
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ApiConnectionBadge(controller: controller)),
        ),
      );
      await tester.pump();
      expect(find.text('ONLINE'), findsOneWidget);
      online = false;
      await controller.check();
      await tester.pump();
      expect(find.text('SERVIZIO OFFLINE'), findsOneWidget);
      controller.pause();
      final paused = probes;
      await tester.pump(const Duration(minutes: 2));
      expect(probes, paused);
      controller.resume();
      await tester.pump();
      expect(probes, greaterThan(paused));
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
  test(
    'a completed background probe cannot replace the resumed connection state',
    () async {
      final old = Completer<bool>();
      var calls = 0;
      final controller = ApiConnectionController(
        probe: () {
          calls++;
          return calls == 1 ? old.future : Future.value(true);
        },
      );
      controller.resume();
      controller.pause();
      controller.resume();
      await Future<void>.delayed(Duration.zero);
      expect(controller.status, ApiConnectionStatus.online);
      old.complete(false);
      await Future<void>.delayed(Duration.zero);
      expect(controller.status, ApiConnectionStatus.online);
      controller.dispose();
    },
  );
  testWidgets(
    'history loads another cursor page and keeps rows when a later read fails',
    (tester) async {
      var fail = false;
      final reads = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: OperatorHistoryScreen(
            request: (path, {method = 'GET', body}) async {
              if (path.contains('/tasks')) {
                return {'items': [], 'nextCursor': null};
              }
              reads.add(path);
              if (fail) throw StateError('Temporary failure');
              final second =
                  Uri.parse(path).queryParameters['cursor'] == 'next';
              return {
                'items': [
                  {
                    'id': second ? 'second' : 'first',
                    'taskId': '',
                    'taskTitle': second ? 'Secondo rapporto' : 'Primo rapporto',
                  },
                ],
                'nextCursor': 'next',
              };
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('history-load-more')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const ValueKey('history-load-more')));
      await tester.pumpAndSettle();
      expect(find.text('2 interventi registrati'), findsOneWidget);
      expect(reads.last, contains('cursor=next'));
      fail = true;
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('history-load-more')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const ValueKey('history-load-more')));
      await tester.pumpAndSettle();
      expect(find.text('Secondo rapporto'), findsOneWidget);
      expect(
        find.text('Altri interventi non disponibili. Riprova.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
  Map manifest({String? certificate, String? url}) => {
    'available': true,
    'applicationId': 'com.example.gestionale_radio',
    'versionName': '1.5.1',
    'versionCode': 2022,
    'signingSha256': certificate ?? 'a' * 64,
    'sha256': 'b' * 64,
    'downloadUrl':
        url ??
        'https://github.com/Kevinni05/gestionale_radio/releases/download/v1.5.1-2022/RadioTech-1.5.1-2022.apk',
  };
  Future<Map> installed() async => {
    'versionName': '1.5.0',
    'versionCode': 2021,
    'signingSha256': ['a' * 64],
  };
  test(
    'update channel allows only newer releases with the installed certificate',
    () async {
      final match = await AndroidUpdateService(
        installedApp: installed,
        manifest: () async => manifest(),
      ).check();
      expect(match.url, isNotNull);
      final mismatch = await AndroidUpdateService(
        installedApp: installed,
        manifest: () async => manifest(certificate: 'c' * 64),
      ).check();
      expect(mismatch.url, isNull);
      expect(mismatch.message, contains('firma diversa'));
      final prepared = await AndroidUpdateService(
        installedApp: installed,
        manifest: () async => {'available': false},
      ).check();
      expect(prepared.url, isNull);
    },
  );
  test('update URLs with a foreign host or query are rejected', () async {
    for (final url in [
      'https://example.com/app.apk',
      'https://github.com/Kevinni05/gestionale_radio/releases/download/v1.5.1/RadioTech-1.5.1.apk?redirect=evil',
    ]) {
      await expectLater(
        AndroidUpdateService(
          installedApp: installed,
          manifest: () async => manifest(url: url),
        ).check(),
        throwsFormatException,
      );
    }
  });
}
