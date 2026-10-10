import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gestionale_radio/services/protected_local_store.dart';

// Native boundary fake only. Actual SQLite/cipher behavior is tested in Kotlin.
void installProtectedLocalMock() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('radiotech/local-data'), (call) async {
    final prefs = await SharedPreferences.getInstance();
    final arguments = Map<Object?, Object?>.from(call.arguments as Map);
    switch (call.method) {
      case 'read':
        return prefs.getString('test_native_${arguments['key']}');
      case 'writeAll':
        final values = Map<String, String>.from(arguments['values'] as Map);
        for (final entry in values.entries) {
          await prefs.setString('test_native_${entry.key}', entry.value);
        }
        return null;
      case 'removeAll':
        for (final key in arguments['keys'] as List) {
          await prefs.remove('test_native_$key');
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
