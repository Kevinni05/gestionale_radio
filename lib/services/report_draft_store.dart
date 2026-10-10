import 'dart:convert';
import 'dart:async';

import 'protected_local_store.dart';

class ReportDraftStore {
  static Future<void>? _writes;

  Future<void> _write(Future<void> Function() operation) async {
    final previous = _writes;
    final released = Completer<void>.sync();
    _writes = released.future;
    try {
      if (previous != null) await previous;
      await operation();
    } finally {
      if (identical(_writes, released.future)) _writes = null;
      released.complete();
    }
  }
  static String storageKey({
    required String tenantId,
    required String operatorUid,
    required String taskScope,
  }) {
    final scope = '$tenantId|$operatorUid|$taskScope';
    final encoded = base64Url.encode(utf8.encode(scope)).replaceAll('=', '');
    return 'report_draft_$encoded';
  }

  Future<Map<String, dynamic>?> load(String key) async {
    final raw = await ProtectedLocalStore.read(key);
    if (raw == null || raw.isEmpty) return null;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Bozza non valida.');
      }
      return Map<String, dynamic>.from(decoded);
    } catch (_) {
      throw StateError('Bozza non leggibile. Recuperala prima di creare un nuovo invio.');
    }
  }

  Future<void> save(String key, Map<String, dynamic> draft) async {
    final encoded = jsonEncode(draft);
    await _write(() async {
      await ProtectedLocalStore.writeAll({key: encoded});
    });
  }

  Future<void> delete(String key) async {
    await _write(() async {
      await ProtectedLocalStore.removeAll([key]);
    });
  }
}

