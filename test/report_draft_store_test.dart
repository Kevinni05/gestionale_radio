import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gestionale_radio/services/report_draft_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'draft survives store recreation and is isolated by tenant/operator/task',
    () async {
      final key = ReportDraftStore.storageKey(
        tenantId: 'tenant-a',
        operatorUid: 'operator-a',
        taskScope: 'task-1',
      );
      final store = ReportDraftStore();
      await store.save(key, {
        'notes': 'Power reading recorded',
        'parts': {'Connector N': 2},
        'measurements': [
          {'name': 'Rx power (dBm)', 'value': '-72.5'},
        ],
        'signaturePoints': [
          {'x': 12.0, 'y': 14.0, 'type': 'tap', 'pressure': 1.0},
        ],
      });

      final restartedStore = ReportDraftStore();
      final restored = await restartedStore.load(key);

      expect(restored?['notes'], 'Power reading recorded');
      expect(restored?['parts'], {'Connector N': 2});
      expect(restored?['measurements'], [
        {'name': 'Rx power (dBm)', 'value': '-72.5'},
      ]);
      expect(
        ReportDraftStore.storageKey(
          tenantId: 'tenant-b',
          operatorUid: 'operator-a',
          taskScope: 'task-1',
        ),
        isNot(key),
      );
      expect(
        ReportDraftStore.storageKey(
          tenantId: 'tenant-a',
          operatorUid: 'operator-b',
          taskScope: 'task-1',
        ),
        isNot(key),
      );

      await restartedStore.delete(key);
      expect(await restartedStore.load(key), isNull);
    },
  );
}
