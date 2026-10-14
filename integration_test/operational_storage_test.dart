import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:gestionale_radio/services/local_operational_store.dart';
import 'package:gestionale_radio/services/offline_sync_service.dart';
import 'package:gestionale_radio/services/notification_delivery_guard.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Android SQLite and Keystore preserve identity-bound records across adapters',
    (tester) async {
      final store = LocalOperationalStore(useNative: true);
      await store.write('notification_device_owner', 'qa-operator');
      expect(
        await LocalOperationalStore(
          useNative: true,
        ).read('notification_device_owner'),
        'qa-operator',
      );
      await store.delete('notification_device_owner');
      await store.write(
        'session_validation_qa',
        '{"uid":"qa-user","validatedAt":"2026-10-13T12:00:00Z"}',
      );
      expect(
        await LocalOperationalStore(
          useNative: true,
        ).read('session_validation_qa'),
        contains('qa-user'),
      );
      await store.delete('session_validation_qa');
      const key = 'report_receipt_qa_device_recovery';
      await store.write(key, 'Synthetic QA record');
      expect(
        await LocalOperationalStore(useNative: true).read(key),
        'Synthetic QA record',
      );
      await store.writeAll({
        'report_draft_qa_copy_a': 'same-revision',
        'report_draft_qa_copy_b': 'same-revision',
      });
      expect(
        await store.read('report_draft_qa_copy_a'),
        await store.read('report_draft_qa_copy_b'),
      );
      await store.delete(key);
      expect(await store.read(key), isNull);
      final guard = NotificationDeliveryGuard(store: store);
      final data = {
        'notificationId': 'qa-notice-${DateTime.now().microsecondsSinceEpoch}',
        'tenantId': 'qa-company',
        'recipientUid': 'qa-user',
      };
      expect(
        await guard.accept(
          data,
          uid: 'qa-user',
          tenantId: 'qa-company',
          channel: 'show',
        ),
        isTrue,
      );
      expect(
        await NotificationDeliveryGuard(
          store: store,
        ).accept(data, uid: 'qa-user', tenantId: 'qa-company', channel: 'show'),
        isFalse,
      );
      expect(
        await guard.accept(
          data,
          uid: 'another-user',
          tenantId: 'qa-company',
          channel: 'open',
        ),
        isFalse,
      );
      final queue = OfflineSyncService.instance;
      await queue.clear();
      await queue.enqueue('task_status_update', {
        'actorUid': 'qa-user',
        'tenantId': 'qa-company',
        'idempotencyKey': 'qa-stable-key',
      });
      await queue.start(
        executor: (_, _) async {
          throw const SyncDeferredException();
        },
        interval: const Duration(days: 1),
      );
      queue.stop();
      expect((await queue.pending()).single.retryCount, 0);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(child: Text('Archivio operativo Android verificato')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Archivio operativo Android verificato'),
        findsOneWidget,
      );
      await queue.clear();
      await store.writeAll({
        'report_draft_qa_copy_a': null,
        'report_draft_qa_copy_b': null,
      });
    },
  );
}
