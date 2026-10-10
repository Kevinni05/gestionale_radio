import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestionale_radio/services/protected_local_store.dart';

// Native boundary fake only. Actual SQLite/cipher behavior is tested in Kotlin.
void installProtectedLocalMock() {
  final records = <String,String>{};
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('radiotech/local-data'), (call) async {
    final arguments = Map<Object?, Object?>.from(call.arguments as Map);
    switch (call.method) {
      case 'read':
        return records[arguments['key']];
      case 'writeAll':
        final values = Map<String, String>.from(arguments['values'] as Map);
        records.addAll(values);
        return null;
      case 'removeAll':
        for (final key in arguments['keys'] as List) {
          records.remove(key);
        }
        return null;
    }
    throw MissingPluginException();
  });
}

class ProtectedTestRecords {
  Future<String?> getString(String key) => ProtectedLocalStore.read(key);
  Future<void> setString(String key, String value) => ProtectedLocalStore.writeAll({key:value});
  Future<void> remove(String key) => ProtectedLocalStore.removeAll([key]);
}
