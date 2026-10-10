import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/protected_local_mock.dart';

import 'package:gestionale_radio/services/offline_sync_service.dart';
import 'package:gestionale_radio/widgets/offline_sync_status_panel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    OfflineSyncService.instance.stop();
    debugPrint('Queue widget cleanup: begin');
    await OfflineSyncService.instance.clear();
    debugPrint('Queue widget cleanup: complete');
  });

  testWidgets('signed-out and other-tenant identities cannot inspect queued operations', (tester) async {
    final service = OfflineSyncService.instance;
    debugPrint('Queue identity test: preparing records');
    await tester.runAsync(() => service.enqueue('maintenance_report', {
      'actorUid': 'operator-a', 'tenantId': 'tenant-a',
      'idempotencyKey': 'private-report',
      'report': {'description': 'Private tenant A report'},
    }));
    debugPrint('Queue identity test: records prepared');
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
      debugPrint('Queue identity test: identity rendered');
      expect(find.text('1 in attesa · 0 da risolvere'), findsNothing);
      expect(find.textContaining('Private tenant A report'), findsNothing);
    }
    expect(await tester.runAsync(() => service.pending()), hasLength(1));
    debugPrint('Queue identity test: records preserved');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('unavailable native data is preserved and surfaced with a retry action', (tester) async {
    const channel = MethodChannel('radiotech/local-data');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler(
      channel.name,
      (_) => SynchronousFuture(channel.codec.encodeErrorEnvelope(code: 'LOCAL_DATA_UNAVAILABLE')),
    );
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: OfflineSyncStatusPanel(
      identityProvider: () => (uid: 'operator-a', tenantId: 'tenant-a'),
    ))));
    await tester.pumpAndSettle();
    expect(find.textContaining('non reinstallare'), findsOneWidget);
    expect(find.text('Riprova l’accesso ai dati'), findsOneWidget);
    expect(tester.takeException(), isNull);
    installProtectedLocalMock();
    await tester.tap(find.text('Riprova l’accesso ai dati'));
    await tester.pumpAndSettle();
    expect(find.textContaining('non reinstallare'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('failed sync is visible and can be retried manually', (
    tester,
  ) async {
    final service = OfflineSyncService.instance;
    await tester.runAsync(() => service.clear());
    await tester.runAsync(() => service.enqueue('maintenance_report', {
      'actorUid': 'operator-a',
      'tenantId': 'tenant-a',
      'idempotencyKey': 'report-conflict',
      'report': {'description': 'operator report'},
    }));
    await tester.runAsync(() => service.start(
      interval: const Duration(hours: 1),
      executor: (_, _) =>
          Future<void>.error(const SyncConflictException('Payload diverso')),
    ));
    await tester.runAsync(() => service.start(
      interval: const Duration(hours: 1),
      executor: (_, _) async {},
    ));

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

    expect(await tester.runAsync(() => service.pending()), isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    service.stop();
  });

  testWidgets('pending sync can be forced manually from the queue dialog', (
    tester,
  ) async {
    final service = OfflineSyncService.instance;
    await tester.runAsync(() => service.clear());
    await tester.runAsync(() => service.enqueue('task_status_update', {
      'id': 'task-waiting',
      'status': 'ACCEPTED',
      'actorUid': 'operator-a',
      'tenantId': 'tenant-a',
      'idempotencyKey': 'task-waiting-key',
    }));
    var attempts = 0;
    await tester.runAsync(() => service.start(
      interval: const Duration(hours: 1),
      executor: (_, _) {
        attempts++;
        if (attempts == 1) {
          return Future<void>.error(Exception('temporary'));
        }
        return Future<void>.value();
      },
    ));

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
    expect(await tester.runAsync(() => service.pending()), isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    service.stop();
  });

  testWidgets('failed sync can be removed only after confirmation', (
    tester,
  ) async {
    final service = OfflineSyncService.instance;
    await tester.runAsync(() => service.clear());
    await tester.runAsync(() => service.enqueue('task_status_update', {
      'id': 'task-failed',
      'status': 'ACCEPTED',
      'actorUid': 'operator-a',
      'tenantId': 'tenant-a',
      'idempotencyKey': 'task-failed-key',
    }));
    await tester.runAsync(() => service.start(
      interval: const Duration(hours: 1),
      executor: (_, _) =>
          Future<void>.error(const PermanentSyncFailure('permanent failure')),
    ));
    await tester.runAsync(() => service.start(
      interval: const Duration(hours: 1),
      executor: (_, _) async {},
    ));

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

    expect(await tester.runAsync(() => service.pending()), hasLength(1));
    await tester.tap(find.text('Rimuovi'));
    await tester.pumpAndSettle();

    expect(await tester.runAsync(() => service.pending()), isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    service.stop();
  });

  testWidgets(
    'unrecoverable queue corruption is visible and does not crash startup',
    (tester) async {
      final preferences = ProtectedTestRecords();
      await tester.runAsync(() => preferences.setString('offline_sync_queue', '{broken-primary'));
      await tester.runAsync(() => preferences.setString(
        'offline_sync_queue_backup',
        '{broken-backup',
      ));

      final service = OfflineSyncService.instance;
      await tester.runAsync(() => service.start(
        interval: const Duration(hours: 1),
        executor: (_, _) async {},
      ));
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
      expect(await tester.runAsync(() => preferences.getString('offline_sync_queue')), '{broken-primary');
      expect(
        await tester.runAsync(() => preferences.getString('offline_sync_queue_backup')),
        '{broken-backup',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      service.stop();
    },
  );
}

