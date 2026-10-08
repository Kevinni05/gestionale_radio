import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gestionale_radio/services/local_report_attachment_store.dart';
import 'package:gestionale_radio/services/offline_sync_service.dart';
import 'package:gestionale_radio/services/report_submission_state.dart';

void main() {
  test(
    'interrupted report keeps original PDF, timestamp and key for recovery across restart',
    () async {
      SharedPreferences.setMockInitialValues({});
      final directory = await Directory.systemTemp.createTemp(
        'radiotech-report-retry-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final store = LocalReportAttachmentStore(
        supportDirectoryProvider: () async => directory,
      );
      final files = await store.stage(
        requestKey: 'attempt-original',
        bytes: {
          'report.pdf': Uint8List.fromList([1, 2, 3]),
        },
      );
      final queue = OfflineSyncService.instance;
      await queue.enqueue('maintenance_report', {
        'actorUid': 'operator-a',
        'tenantId': 'tenant-a',
        'taskId': 'task-a',
        'idempotencyKey': 'original-key',
        'report': {
          'antennaId': 'asset-a',
          'completedAt': '2026-10-06T00:00:00Z',
          'operatorNotes': 'Original report',
        },
        'stagedAttachments': files,
      });
      final recovered = pendingReportFor(
        await queue.pending(),
        actorUid: 'operator-a',
        tenantId: 'tenant-a',
        taskId: 'task-a',
        antennaId: 'asset-a',
      )!;
      expect(recovered.payload['idempotencyKey'], 'original-key');
      expect(
        (recovered.payload['report'] as Map)['completedAt'],
        '2026-10-06T00:00:00Z',
      );
      final restarted = LocalReportAttachmentStore(
        supportDirectoryProvider: () async => directory,
      );
      expect(
        await (await restarted.resolve(
          Map<String, dynamic>.from(
            (recovered.payload['stagedAttachments'] as List).single as Map,
          ),
        )).readAsBytes(),
        [1, 2, 3],
      );
      expect(
        pendingReportFor(
          await queue.pending(),
          actorUid: 'another-operator',
          tenantId: 'tenant-a',
          taskId: 'task-a',
          antennaId: 'asset-a',
        ),
        isNull,
      );
      expect(
        pendingReportFor(
          await queue.pending(),
          actorUid: 'operator-a',
          tenantId: 'another-tenant',
          taskId: 'task-a',
          antennaId: 'asset-a',
        ),
        isNull,
      );
      await queue.remove(recovered.id);
      await restarted.remove(files);
      expect(await queue.pending(), isEmpty);
    },
  );

  test(
    'concurrent queue writes preserve every report and isolate identical keys by actor',
    () async {
      SharedPreferences.setMockInitialValues({});
      final queue = OfflineSyncService.instance;
      await Future.wait(
        List.generate(
          20,
          (index) => queue.enqueue('maintenance_report', {
            'actorUid': 'operator-$index',
            'tenantId': 'tenant-a',
            'idempotencyKey': 'same-key',
            'report': {'antennaId': 'asset-$index'},
          }),
        ),
      );
      expect(await queue.pending(), hasLength(20));
      await queue.enqueue('maintenance_report', {
        'actorUid': 'operator-0',
        'tenantId': 'tenant-a',
        'idempotencyKey': 'same-key',
      });
      expect(await queue.pending(), hasLength(20));
    },
  );
}
