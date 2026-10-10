import 'dart:convert';

import 'protected_local_store.dart';

class ReportDraftStore {
  static Future<void> _writes = Future<void>.value();

  Future<void> _write(Future<void> Function() operation) {
    final result = _writes.then((_) => operation());
    // A failed save must reach its caller without poisoning subsequent writes.
    _writes = result.catchError((Object _) {});
    return result;
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

