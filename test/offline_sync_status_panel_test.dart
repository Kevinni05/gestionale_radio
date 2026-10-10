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

  testWidgets('signed-out and other-tenant identities cannot inspect queued operations', (tester) async {
    final service = OfflineSyncService.instance;
    await service.enqueue('maintenance_report', {
      'actorUid': 'operator-a', 'tenantId': 'tenant-a',
      'idempotencyKey': 'private-report',
      'report': {'description': 'Private tenant A report'},
    });
    for (final identity in [
      (uid: null, tenantId: null),
      (uid: 'operator-a', tenantId: null),
      (uid: 'operator-a', tenantId: 'tenant-b'),
      (uid: 'operator-b', tenantId: 'tenant-a'),
    ]) {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: OfflineSyncStatusPanel(
        key: UniqueKey(), identityProvider: () => identity,
      ))));
      await tester.pumpAndSettle();
      expect(find.text('1 in attesa · 0 da risolvere'), findsNothing);
      expect(find.textContaining('Private tenant A report'), findsNothing);
    }
    expect(await service.pending(), hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('failed sync is visible and can be retried manually', (
    tester,
  ) async {
    final service = OfflineSyncService.instance;
    await service.clear();
    await service.enqueue('maintenance_report', {
      'actorUid': 'operator-a',
      'tenantId': 'tenant-a',
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
      MaterialApp(home: Scaffold(body: OfflineSyncStatusPanel(
        identityProvider: () => (uid: 'operator-a', tenantId: 'tenant-a'),
      ))),
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

  testWidgets('pending sync can be forced manually from the queue dialog', (
    tester,
  ) async {
    final service = OfflineSyncService.instance;
    await service.clear();
    await service.enqueue('task_status_update', {
      'id': 'task-waiting',
      'status': 'ACCEPTED',
      'actorUid': 'operator-a',
      'tenantId': 'tenant-a',
      'idempotencyKey': 'task-waiting-key',
    });
    var attempts = 0;
    await service.start(
      interval: const Duration(hours: 1),
      executor: (_, _) {
        attempts++;
        if (attempts == 1) {
          return Future<void>.error(Exception('temporary'));
        }
        return Future<void>.value();
      },
    );

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: OfflineSyncStatusPanel(
        identityProvider: () => (uid: 'operator-a', tenantId: 'tenant-a'),
      ))),
    );
    await tester.pumpAndSettle();
    expect(find.text('1 in attesa · 0 da risolvere'), findsOneWidget);

    await tester.tap(find.text('1 in attesa · 0 da risolvere'));
    await tester.pumpAndSettle();
    expect(find.text('Sincronizza ora'), findsOneWidget);

    await tester.tap(find.text('Sincronizza ora'));
    await tester.pumpAndSettle();

    expect(attempts, 2);
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
      'actorUid': 'operator-a',
      'tenantId': 'tenant-a',
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
      MaterialApp(home: Scaffold(body: OfflineSyncStatusPanel(
        identityProvider: () => (uid: 'operator-a', tenantId: 'tenant-a'),
      ))),
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
        MaterialApp(home: Scaffold(body: OfflineSyncStatusPanel(
        identityProvider: () => (uid: 'operator-a', tenantId: 'tenant-a'),
      ))),
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

