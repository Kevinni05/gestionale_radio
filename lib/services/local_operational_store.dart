import 'dart:io';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef OperationalStoreCall =
    Future<dynamic> Function(String method, Map<String, dynamic> arguments);

/// Android operational records live in SQLite with authenticated encrypted
/// values and a non-exportable Keystore key. Legacy data is removed only after
/// a successful database commit. Non-Android development retains preferences.
class LocalOperationalStore {
  LocalOperationalStore({bool? useNative, OperationalStoreCall? invoke})
    : _useNative = useNative ?? Platform.isAndroid,
      _invoke = invoke ?? _call;

  static final instance = LocalOperationalStore();
  static const _channel = MethodChannel('radiotech/operational-store');
  final bool _useNative;
  final OperationalStoreCall _invoke;

  static Future<dynamic> _call(String method, Map<String, dynamic> arguments) =>
      _channel.invokeMethod<dynamic>(method, arguments);

  Future<String?> read(String key) async {
    if (_useNative) {
      final result = await _invoke('read', {'key': key});
      if (result is! Map ||
          result['found'] is! bool ||
          result['value'] != null && result['value'] is! String) {
        throw StateError('Archivio operativo non leggibile.');
      }
      if (result['found'] == true) return result['value'] as String?;
    }
    return (await SharedPreferences.getInstance()).getString(key);
  }

  Future<void> write(String key, String value) => writeAll({key: value});
  Future<void> delete(String key) => writeAll({key: null});

  Future<void> adoptValidated(Map<String, String> values) async {
    if (!_useNative) return;
    final preferences = await SharedPreferences.getInstance();
    if (values.keys.any(preferences.containsKey)) await writeAll(values);
  }

  Future<void> writeAll(Map<String, String?> values) async {
    if (values.isEmpty) return;
    final preferences = await SharedPreferences.getInstance();
    if (_useNative) {
      if (await _invoke('write', {'values': values}) != true) {
        throw StateError('Salvataggio operativo non riuscito.');
      }
      // Tombstones in SQLite prevent legacy resurrection if cleanup crashes.
      for (final key in values.keys) {
        if (preferences.containsKey(key) && !await preferences.remove(key)) {
          throw StateError(
            'Migrazione locale incompleta. I dati salvati sono conservati.',
          );
        }
      }
    } else {
      for (final entry in values.entries) {
        final success = entry.value == null
            ? await preferences.remove(entry.key)
            : await preferences.setString(entry.key, entry.value!);
        if (!success) throw StateError('Salvataggio operativo non riuscito.');
      }
    }
  }
}
