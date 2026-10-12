import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:gestionale_radio/services/local_operational_store.dart';
import 'package:gestionale_radio/services/offline_sync_service.dart';
import 'package:gestionale_radio/services/notification_delivery_guard.dart';

/// Standalone QA entry point: no Firebase initialization and no real account data.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('radiotech/updates');
  final identity = await channel.invokeMapMethod<String, dynamic>(
    'installedApp',
  );
  if (identity?['applicationId'] != 'com.example.gestionale_radio.qa') {
    throw StateError('Isolated QA application required.');
  }
  final directory = await getApplicationSupportDirectory();
  final result = File('${directory.path}/qa-upgrade-result.json');
  final phase = await channel.invokeMethod<String>('qaRecoveryPhase');
  final code = (identity!['versionCode'] as num).toInt();
  var success = false;
  String? error;
  try {
    final store = LocalOperationalStore(useNative: true);
    final queue = OfflineSyncService.instance;
    const draft = 'report_draft_qa_upgrade';
    const receipt = 'report_receipt_qa_upgrade';
    const marker = 'report_receipt_qa_upgrade_version';
    final notice = <String, dynamic>{
      'notificationId': 'qa-upgrade-notification',
      'tenantId': 'qa-upgrade-tenant',
      'recipientUid': 'qa-upgrade-user',
    };
    final guard = NotificationDeliveryGuard(store: store);
    if (phase == 'seed') {
      await queue.clear();
      await store.writeAll({
        draft: 'synthetic-draft',
        receipt: 'synthetic-receipt',
        marker: '$code',
      });
      await queue.enqueue('task_status_update', {
        'actorUid': 'qa-upgrade-user',
        'tenantId': 'qa-upgrade-tenant',
        'idempotencyKey': 'qa-upgrade-stable-operation',
      });
      await guard.accept(
        notice,
        uid: 'qa-upgrade-user',
        tenantId: 'qa-upgrade-tenant',
        channel: 'show',
      );
    } else if (phase == 'restart' || phase == 'upgrade') {
      if (await store.read(draft) != 'synthetic-draft' ||
          await store.read(receipt) != 'synthetic-receipt') {
        throw StateError('Draft or receipt lost.');
      }
      final pending = await queue.pending();
      if (pending.length != 1 ||
          pending.single.payload['idempotencyKey'] !=
              'qa-upgrade-stable-operation' ||
          pending.single.retryCount != 0) {
        throw StateError('Pending operation changed.');
      }
      if (await guard.accept(
        notice,
        uid: 'qa-upgrade-user',
        tenantId: 'qa-upgrade-tenant',
        channel: 'show',
      )) {
        throw StateError('Notification deduplication lost.');
      }
      final previous = int.parse((await store.read(marker))!);
      if (phase == 'upgrade' && code <= previous) {
        throw StateError('Higher versionCode required.');
      }
      if (phase == 'upgrade') {
        await queue.clear();
        await store.writeAll({draft: null, receipt: null, marker: null});
      }
    } else {
      throw StateError('Unknown QA phase.');
    }
    success = true;
  } catch (failure) {
    error = failure.toString();
  }
  await result.writeAsString(
    jsonEncode({
      'phase': phase,
      'versionCode': code,
      'success': success,
      'error': ?error,
    }),
    flush: true,
  );
  runApp(
    MaterialApp(
      home: Scaffold(
        body: Center(child: Text('QA $phase: ${success ? "PASS" : "FAIL"}')),
      ),
    ),
  );
}
