import 'dart:async';
import 'dart:convert';

import 'local_operational_store.dart';

/// Durable, account-scoped deduplication. Opening and showing are separate:
/// a foreground banner must remain actionable on its first tap.
class NotificationDeliveryGuard {
  NotificationDeliveryGuard({LocalOperationalStore? store})
    : _store = store ?? LocalOperationalStore.instance;

  final LocalOperationalStore _store;
  Future<void>? _access;
  static const maxReceipts = 200;

  static bool belongsTo(
    Map<String, dynamic> data, {
    required String uid,
    required String tenantId,
  }) =>
      uid.isNotEmpty &&
      tenantId.isNotEmpty &&
      data['tenantId'] == tenantId &&
      data['recipientUid'] == uid &&
      data['notificationId'] is String &&
      (data['notificationId'] as String).trim().isNotEmpty;

  Future<bool> accept(
    Map<String, dynamic> data, {
    required String uid,
    required String tenantId,
    required String channel,
  }) async {
    if (!belongsTo(data, uid: uid, tenantId: tenantId)) return false;
    final previous = _access;
    final released = Completer<void>.sync();
    _access = released.future;
    try {
      if (previous != null) await previous;
      final key =
          'notification_receipts_${base64Url.encode(utf8.encode('$tenantId:$uid:$channel'))}';
      final raw = await _store.read(key);
      final decoded = raw == null ? <dynamic>[] : jsonDecode(raw);
      if (decoded is! List || decoded.any((id) => id is! String)) {
        throw StateError('Ricevute notifiche non leggibili.');
      }
      final ids = decoded.cast<String>().toList();
      final id = data['notificationId'] as String;
      if (ids.contains(id)) return false;
      ids.add(id);
      if (ids.length > maxReceipts) {
        ids.removeRange(0, ids.length - maxReceipts);
      }
      await _store.write(key, jsonEncode(ids));
      return true;
    } finally {
      if (identical(_access, released.future)) _access = null;
      released.complete();
    }
  }
}
