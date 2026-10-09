import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gestionale_radio/services/api_service.dart';
import 'package:gestionale_radio/services/offline_sync_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'a deferred account does not consume retries or delete its queued work',
    () async {
      final service = OfflineSyncService.instance;
      await service.clear();
      await service.enqueue('task_status_update', {
        'actorUid': 'another-user',
        'tenantId': 'tenant-a',
        'id': 'task-a',
      });
      await service.start(
        executor: (_, _) async {
          throw const SyncDeferredException();
        },
        interval: const Duration(days: 1),
      );
      addTearDown(service.stop);
      for (var attempt = 0; attempt < 10; attempt++) {
        await service.retryPending(force: true);
      }
      final item = (await service.pending()).single;
      expect(item.retryCount, 0);
      expect(item.failed, isFalse);
      expect(item.payload['actorUid'], 'another-user');
    },
  );

  test('enqueue stores pending sync actions for later retry', () async {
    final service = OfflineSyncService.instance;

    await service.clear();
    await service.enqueue('task_status_update', {
      'id': 'task-123',
      'status': 'IN_PROGRESS',
    });

    final pending = await service.pending();

    expect(pending, hasLength(1));
    expect(pending.first.action, 'task_status_update');
    expect(pending.first.payload['id'], 'task-123');
  });

  test('remove clears a specific queued action', () async {
    final service = OfflineSyncService.instance;

    await service.clear();
    await service.enqueue('maintenance_report', {
      'taskId': 'task-456',
      'report': {'description': 'offline'},
    });

    final pendingBefore = await service.pending();
    await service.remove(pendingBefore.first.id);

    expect(await service.pending(), isEmpty);
  });

  test('enqueue deduplicates actions with the same idempotency key', () async {
    final service = OfflineSyncService.instance;

    await service.clear();
    await service.enqueue('maintenance_report', {
      'idempotencyKey': 'request-123',
      'taskId': 'task-456',
      'report': {'description': 'offline'},
    });
    await service.enqueue('maintenance_report', {
      'idempotencyKey': 'request-123',
      'taskId': 'task-456',
      'report': {'description': 'offline'},
    });

    final pending = await service.pending();
    expect(pending, hasLength(1));
    expect(pending.single.payload['idempotencyKey'], 'request-123');
  });

  test(
    'persistent idempotency keys survive repeated lookups and are scope-specific',
    () async {
      final service = OfflineSyncService.instance;

      final first = await service.persistentIdempotencyKey('report_task-a');
      final retry = await service.persistentIdempotencyKey('report_task-a');
      final otherTask = await service.persistentIdempotencyKey('report_task-b');

      expect(retry, first);
      expect(otherTask, isNot(first));
      await service.clearPersistentIdempotencyKey('report_task-a');
      expect(
        await service.persistentIdempotencyKey('report_task-a'),
        isNot(first),
      );
    },
  );

  test('queued report preserves staged attachment references', () async {
    final service = OfflineSyncService.instance;
    await service.clear();
    await service.enqueue('maintenance_report', {
      'idempotencyKey': 'report-request',
      'stagedAttachments': [
        {'name': 'photo.jpg', 'path': '/app-support/pending/photo.jpg'},
      ],
    });

    final queued = await service.pending();

    expect(queued.single.payload['stagedAttachments'], [
      {'name': 'photo.jpg', 'path': '/app-support/pending/photo.jpg'},
    ]);
  });

  test('generic status update cannot complete a task without GPS', () async {
    await expectLater(
      ApiService.instance.updateTaskStatus('task-123', 'COMPLETED'),
      throwsArgumentError,
    );
  });

  test('failed retry remains queued and increments its retry count', () async {
    final service = OfflineSyncService.instance;
    await service.clear();
    await service.enqueue('task_status_update', {
      'id': 'task-123',
      'status': 'ACCEPTED',
      'idempotencyKey': 'request-456',
    });
    await service.start(
      interval: const Duration(hours: 1),
      executor: (_, _) => Future<void>.error(Exception('temporary failure')),
    );

    final pending = await service.pending();
    expect(pending, hasLength(1));
    expect(pending.single.retryCount, 1);
    expect(pending.single.payload['idempotencyKey'], 'request-456');
    await service.start(
      interval: const Duration(hours: 1),
      executor: (_, _) async {},
    );
    expect(await service.pending(), hasLength(1));
    await service.retryPending(force: true);
    expect(await service.pending(), isEmpty);
  });

  test(
    'queue recovers from a corrupted JSON payload using the last valid backup',
    () async {
      final service = OfflineSyncService.instance;
      await service.clear();
      await service.enqueue('task_status_update', {
        'id': 'task-recoverable',
        'status': 'EN_ROUTE',
        'idempotencyKey': 'request-recoverable',
      });

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('offline_sync_queue', '{not-valid-json');

      final pending = await service.pending();
      expect(pending, hasLength(1));
      expect(pending.single.payload['id'], 'task-recoverable');
      expect(pending.single.action, 'task_status_update');
    },
  );

  test(
    'newer backup revision wins and repairs a stale primary queue',
    () async {
      final service = OfflineSyncService.instance;
      await service.clear();
      final prefs = await SharedPreferences.getInstance();
      final primary = {
        'version': 2,
        'revision': 3,
        'items': [
          {
            'id': 'old_action',
            'action': 'task_status_update',
            'payload': {'id': 'old-task'},
            'createdAt': '2026-10-08T10:00:00Z',
            'retryCount': 0,
            'nextAttemptAt': null,
            'lastError': null,
            'failed': false,
          },
        ],
      };
      final backup = {
        'version': 2,
        'revision': 4,
        'items': [
          {
            'id': 'new_action',
            'action': 'task_status_update',
            'payload': {'id': 'new-task'},
            'createdAt': '2026-10-08T10:01:00Z',
            'retryCount': 0,
            'nextAttemptAt': null,
            'lastError': null,
            'failed': false,
          },
        ],
      };
      await prefs.setString('offline_sync_queue', jsonEncode(primary));
      await prefs.setString('offline_sync_queue_backup', jsonEncode(backup));

      final pending = await service.pending();

      expect(pending.single.id, 'new_action');
      expect(pending.single.payload['id'], 'new-task');
      expect(
        prefs.getString('offline_sync_queue'),
        prefs.getString('offline_sync_queue_backup'),
      );
    },
  );

  test(
    'malformed newer queue slot falls back to the last valid revision',
    () async {
      final service = OfflineSyncService.instance;
      await service.clear();
      final prefs = await SharedPreferences.getInstance();
      final validBackup = {
        'version': 2,
        'revision': 7,
        'items': [
          {
            'id': 'recover-me',
            'action': 'maintenance_report',
            'payload': {'idempotencyKey': 'recover-key'},
            'createdAt': '2026-10-08T10:00:00Z',
            'retryCount': 1,
            'nextAttemptAt': null,
            'lastError': 'temporary',
            'failed': false,
          },
        ],
      };
      final malformedPrimary = {
        'version': 2,
        'revision': 8,
        'items': [
          {
            'id': '',
            'action': 'maintenance_report',
            'payload': {},
            'createdAt': 'not-a-date',
            'retryCount': -1,
          },
        ],
      };
      await prefs.setString(
        'offline_sync_queue',
        jsonEncode(malformedPrimary),
      );
      await prefs.setString(
        'offline_sync_queue_backup',
        jsonEncode(validBackup),
      );

      final pending = await service.pending();

      expect(pending.single.id, 'recover-me');
      expect(pending.single.retryCount, 1);
      expect(service.queueCorrupted, isFalse);
    },
  );

  test('queue persistence uses a versioned revision envelope', () async {
    final service = OfflineSyncService.instance;
    await service.clear();
    await service.enqueue('task_status_update', {
      'id': 'task-envelope',
      'status': 'ACCEPTED',
    });

    final prefs = await SharedPreferences.getInstance();
    final primary =
        jsonDecode(prefs.getString('offline_sync_queue')!) as Map;
    final backup =
        jsonDecode(prefs.getString('offline_sync_queue_backup')!) as Map;

    expect(primary['version'], 2);
    expect(primary['revision'], isA<int>());
    expect(primary['revision'], greaterThan(0));
    expect(primary, backup);
    expect((primary['items'] as List), hasLength(1));
  });

  test(
    'queue corruption without a valid backup is surfaced without deletion',
    () async {
      final service = OfflineSyncService.instance;
      final prefs = await SharedPreferences.getInstance();
      const primary = '{corrupted-primary';
      const backup = '{corrupted-backup';
      await prefs.setString('offline_sync_queue', primary);
      await prefs.setString('offline_sync_queue_backup', backup);

      await expectLater(service.pending(), throwsStateError);

      expect(prefs.getString('offline_sync_queue'), primary);
      expect(prefs.getString('offline_sync_queue_backup'), backup);
    },
  );

  test(
    'corrupt primary queue without a backup is not replaced by an empty queue',
    () async {
      final service = OfflineSyncService.instance;
      final prefs = await SharedPreferences.getInstance();
      const primary = '{corrupted-primary-without-backup';
      await prefs.setString('offline_sync_queue', primary);
      await prefs.remove('offline_sync_queue_backup');

      await expectLater(service.pending(), throwsStateError);

      expect(prefs.getString('offline_sync_queue'), primary);
      expect(prefs.getString('offline_sync_queue_backup'), isNull);
    },
  );

  test('retry delays grow exponentially and remain bounded', () {
    expect(
      OfflineSyncService.retryDelayForAttempt(1),
      const Duration(seconds: 30),
    );
    expect(
      OfflineSyncService.retryDelayForAttempt(2),
      const Duration(seconds: 60),
    );
    expect(
      OfflineSyncService.retryDelayForAttempt(99),
      const Duration(hours: 1),
    );
  });

  test(
    'automatic retries stop at the limit without deleting the action',
    () async {
      final service = OfflineSyncService.instance;
      await service.clear();
      await service.enqueue('task_status_update', {
        'id': 'task-retry-limit',
        'status': 'ACCEPTED',
      });
      var attempts = 0;
      await service.start(
        interval: const Duration(hours: 1),
        executor: (_, _) {
          attempts++;
          return Future<void>.error(Exception('offline'));
        },
      );
      for (
        var retry = 1;
        retry < OfflineSyncService.maxRetryAttempts;
        retry++
      ) {
        await service.retryPending(force: true);
      }

      final queued = await service.pending();
      expect(attempts, OfflineSyncService.maxRetryAttempts);
      expect(queued.single.failed, isTrue);
      expect(queued.single.retryCount, OfflineSyncService.maxRetryAttempts);
      expect(queued.single.payload['id'], 'task-retry-limit');
      await service.retryPending(force: true);
      expect(attempts, OfflineSyncService.maxRetryAttempts);
    },
  );

  test('conflicts are retained until an explicit manual retry', () async {
    final service = OfflineSyncService.instance;
    await service.clear();
    await service.enqueue('maintenance_report', {
      'idempotencyKey': 'conflicted-report',
      'report': {'description': 'conflict'},
    });
    await service.start(
      interval: const Duration(hours: 1),
      executor: (_, _) =>
          Future<void>.error(const SyncConflictException('payload conflict')),
    );

    final failed = await service.failedActions();
    expect(failed, hasLength(1));
    expect(failed.single.retryCount, 0);
    expect(failed.single.lastError, 'payload conflict');

    var recoveryAttempts = 0;
    await service.start(
      interval: const Duration(hours: 1),
      executor: (_, _) async => recoveryAttempts++,
    );
    await service.retryFailed(failed.single.id);

    expect(recoveryAttempts, 1);
    expect(await service.pending(), isEmpty);
  });

  test(
    'discarding a failed report releases its task idempotency key',
    () async {
      final service = OfflineSyncService.instance;
      await service.clear();
      final originalKey = await service.persistentIdempotencyKey(
        'report_task-a',
      );
      await service.enqueue('maintenance_report', {
        'taskId': 'task-a',
        'idempotencyKey': originalKey,
        'report': {'description': 'failed report'},
        'stagedAttachments': [],
      });
      await service.start(
        interval: const Duration(hours: 1),
        executor: (_, _) =>
            Future<void>.error(const PermanentSyncFailure('invalid report')),
      );
      final failed = (await service.failedActions()).single;

      await ApiService.instance.discardFailedSyncAction(failed.id);

      expect(await service.pending(), isEmpty);
      expect(
        await service.persistentIdempotencyKey('report_task-a'),
        isNot(originalKey),
      );
      service.stop();
    },
  );

  test('concurrent retry triggers execute an action only once', () async {
    final service = OfflineSyncService.instance;
    await service.clear();
    await service.enqueue('task_status_update', {
      'id': 'task-789',
      'status': 'ACCEPTED',
      'idempotencyKey': 'request-concurrent',
    });

    final completion = Completer<void>();
    var attempts = 0;
    final startupRetry = service.start(
      interval: const Duration(hours: 1),
      executor: (_, _) {
        attempts++;
        return completion.future;
      },
    );
    await Future<void>.delayed(Duration.zero);
    await service.retryPending();
    completion.complete();
    await startupRetry;

    expect(attempts, 1);
    expect(await service.pending(), isEmpty);
  });
}
