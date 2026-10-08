import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gestionale_radio/services/offline_sync_service.dart';
import 'package:gestionale_radio/widgets/offline_sync_status_panel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    OfflineSyncService.instance.stop();
    await OfflineSyncService.instance.clear();
  });

  testWidgets('failed sync is visible and can be retried manually', (
    tester,
  ) async {
    final service = OfflineSyncService.instance;
    await service.clear();
    await service.enqueue('maintenance_report', {
      'idempotencyKey': 'report-conflict',
      'report': {'description': 'operator report'},
    });
    await service.start(
      interval: const Duration(hours: 1),
      executor: (_, _) =>
          Future<void>.error(const SyncConflictException('Payload diverso')),
    );
    await service.start(
      interval: const Duration(hours: 1),
      executor: (_, _) async {},
    );

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: OfflineSyncStatusPanel())),
    );
    await tester.pumpAndSettle();

    expect(find.text('0 in attesa · 1 da risolvere'), findsOneWidget);
    await tester.tap(find.text('0 in attesa · 1 da risolvere'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Payload diverso'), findsOneWidget);

    await tester.tap(find.byTooltip('Riprova'));
    await tester.pumpAndSettle();

    expect(await service.pending(), isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    service.stop();
  });

  testWidgets('failed sync can be removed only after confirmation', (
    tester,
  ) async {
    final service = OfflineSyncService.instance;
    await service.clear();
    await service.enqueue('task_status_update', {
      'id': 'task-failed',
      'status': 'ACCEPTED',
      'idempotencyKey': 'task-failed-key',
    });
    await service.start(
      interval: const Duration(hours: 1),
      executor: (_, _) =>
          Future<void>.error(const PermanentSyncFailure('permanent failure')),
    );
    await service.start(
      interval: const Duration(hours: 1),
      executor: (_, _) async {},
    );

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: OfflineSyncStatusPanel())),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('0 in attesa · 1 da risolvere'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Rimuovi operazione fallita'));
    await tester.pumpAndSettle();

    expect(await service.pending(), hasLength(1));
    await tester.tap(find.text('Rimuovi'));
    await tester.pumpAndSettle();

    expect(await service.pending(), isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    service.stop();
  });

  testWidgets(
    'unrecoverable queue corruption is visible and does not crash startup',
    (tester) async {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString('offline_sync_queue', '{broken-primary');
      await preferences.setString(
        'offline_sync_queue_backup',
        '{broken-backup',
      );

      final service = OfflineSyncService.instance;
      await service.start(
        interval: const Duration(hours: 1),
        executor: (_, _) async {},
      );
      expect(service.queueCorrupted, isTrue);

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: OfflineSyncStatusPanel())),
      );
      await tester.pump();

      expect(
        find.textContaining('La coda offline è danneggiata'),
        findsOneWidget,
      );
      expect(preferences.getString('offline_sync_queue'), '{broken-primary');
      expect(
        preferences.getString('offline_sync_queue_backup'),
        '{broken-backup',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      service.stop();
    },
  );
}
