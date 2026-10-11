import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gestionale_radio/services/report_draft_store.dart';
import 'package:gestionale_radio/services/urgent_report_signal.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'timeout after server commit and restart replay one stable signal',
    () async {
      final store = ReportDraftStore();
      final key = ReportDraftStore.storageKey(
        tenantId: 'tenant-a',
        operatorUid: 'operator-a',
        taskScope: 'task-a',
      );
      var signal = UrgentReportSignal.prepare(
        description: 'Pericolo sul sito',
        assetId: 'asset-a',
        taskId: 'task-a',
      );
      await store.save(key, {'urgentSignal': signal.toJson()});
      final serverSignals = <String, String>{};
      Future<void> send(UrgentReportSignal value) async {
        serverSignals.putIfAbsent(value.operationId, () => value.description);
        throw StateError('Response lost after commit');
      }

      for (var attempt = 0; attempt < 3; attempt++) {
        final draft = await ReportDraftStore().load(key);
        signal = UrgentReportSignal.fromJson(
          Map<String, dynamic>.from(draft!['urgentSignal'] as Map),
        );
        await expectLater(signal.deliver(send), throwsStateError);
      }
      expect(serverSignals, hasLength(1));
      expect(signal.confirmed, isFalse);
      signal = await signal.deliver((value) async {
        serverSignals.putIfAbsent(value.operationId, () => value.description);
      });
      await store.save(key, {'urgentSignal': signal.toJson()});
      final restored = UrgentReportSignal.fromJson(
        Map<String, dynamic>.from(
          (await store.load(key))!['urgentSignal'] as Map,
        ),
      );
      await restored.deliver(
        (_) async => fail('Confirmed signal must not be sent again'),
      );
      expect(restored.confirmed, isTrue);
      expect(serverSignals, hasLength(1));
    },
  );

  test(
    'overlapping draft saves cannot replace a confirmed receipt with older data',
    () async {
      final signal = UrgentReportSignal.prepare(
        description: 'Urgente',
        assetId: 'a',
      );
      final confirmed = await signal.deliver((_) async {});
      final store = ReportDraftStore();
      await Future.wait([
        store.save('draft', {'urgentSignal': signal.toJson()}),
        ReportDraftStore().save('draft', {'urgentSignal': confirmed.toJson()}),
      ]);
      expect(
        ((await store.load('draft'))!['urgentSignal'] as Map)['confirmed'],
        isTrue,
      );
      expect(jsonEncode(signal.toJson()), contains(signal.operationId));
    },
  );

  test(
    'corrupt persisted draft fails closed instead of allocating another signal',
    () async {
      SharedPreferences.setMockInitialValues({'draft': '{invalid'});
      await expectLater(ReportDraftStore().load('draft'), throwsStateError);
      expect(
        () => UrgentReportSignal.fromJson({'operationId': ''}),
        throwsFormatException,
      );
    },
  );
}
