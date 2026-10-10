import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Android stores sensitive operational data in transactional SQLite records
/// encrypted with an Android Keystore key. No plaintext fallback is permitted.
class ProtectedLocalStore {
  static const _channel = MethodChannel('radiotech/local-data');
  static Future<void> _operations = Future<void>.value();

  static Future<T> _serialize<T>(Future<T> Function() operation) {
    final result = _operations.then((_) => operation());
    _operations = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  static bool _allowed(String key) =>
      key.startsWith('report_draft_') ||
      key.startsWith('offline_idempotency_') ||
      key == 'offline_sync_queue' ||
      key == 'offline_sync_queue_backup';

  static void _validate(String key) {
    if (!_allowed(key) || key.length > 2048) {
      throw ArgumentError('Chiave dei dati locali non valida.');
    }
  }

  static Future<String?> read(String key) => _serialize(() async {
    _validate(key);
    final stored = await _channel.invokeMethod<String>('read', {'key': key});
    final legacy = await SharedPreferences.getInstance();
    if (stored != null) {
      // A prior interruption may have left a stale plaintext copy. Never use it.
      if (legacy.containsKey(key) && !await legacy.remove(key)) {
        throw StateError('Pulizia dei dati precedenti non riuscita.');
      }
      return stored;
    }
    final raw = legacy.getString(key);
    if (raw == null) return null;
    await _channel.invokeMethod<void>('writeAll', {'values': {key: raw}});
    final verified = await _channel.invokeMethod<String>('read', {'key': key});
    if (verified != raw) {
      throw StateError('Migrazione dei dati locali non verificata.');
    }
    if (!await legacy.remove(key)) {
      throw StateError('Pulizia dei dati precedenti non riuscita.');
    }
    return verified;
  });

  static Future<void> writeAll(Map<String, String> values) => _serialize(() async {
    for (final key in values.keys) { _validate(key); }
    await _channel.invokeMethod<void>('writeAll', {'values': values});
    final legacy = await SharedPreferences.getInstance();
    for (final key in values.keys) {
      if (legacy.containsKey(key) && !await legacy.remove(key)) {
        throw StateError('Pulizia dei dati precedenti non riuscita.');
      }
    }
  });

  static Future<void> removeAll(List<String> keys) => _serialize(() async {
    for (final key in keys) { _validate(key); }
    // Remove plaintext first; an interruption cannot resurrect a deleted draft.
    final legacy = await SharedPreferences.getInstance();
    for (final key in keys) {
      if (legacy.containsKey(key) && !await legacy.remove(key)) {
        throw StateError('Rimozione dei dati precedenti non riuscita.');
      }
    }
    await _channel.invokeMethod<void>('removeAll', {'keys': keys});
  });
}
