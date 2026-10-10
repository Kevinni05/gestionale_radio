import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestionale_radio/services/protected_local_store.dart';

// Native boundary fake only. Actual SQLite/cipher behavior is tested in Kotlin.
void installProtectedLocalMock() {
  final records = <String,String>{};
  const channel = MethodChannel('radiotech/local-data');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMessageHandler(channel.name, (message) {
    final call = channel.codec.decodeMethodCall(message);
    final arguments = Map<Object?, Object?>.from(call.arguments as Map);
    Object? response;
    switch (call.method) {
      case 'read':
        response = records[arguments['key']];
        break;
      case 'writeAll':
        final values = Map<String, String>.from(arguments['values'] as Map);
        records.addAll(values);
        break;
      case 'removeAll':
        for (final key in arguments['keys'] as List) {
          records.remove(key);
        }
        break;
      default:
        return SynchronousFuture(channel.codec.encodeErrorEnvelope(code: 'NOT_IMPLEMENTED'));
    }
    return SynchronousFuture(channel.codec.encodeSuccessEnvelope(response));
  });
}

class ProtectedTestRecords {
  Future<String?> getString(String key) => ProtectedLocalStore.read(key);
  Future<void> setString(String key, String value) => ProtectedLocalStore.writeAll({key:value});
  Future<void> remove(String key) => ProtectedLocalStore.removeAll([key]);
}
