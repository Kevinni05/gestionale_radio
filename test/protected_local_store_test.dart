import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gestionale_radio/services/protected_local_store.dart';
import 'support/protected_local_mock.dart';

void main() {
  const channel = MethodChannel('radiotech/local-data');
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(installProtectedLocalMock);

  test('migration verifies its native copy before removing plaintext', () async {
    SharedPreferences.setMockInitialValues({'report_draft_test':'legacy draft'});
    final records = <String, String>{};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      final args = Map<Object?, Object?>.from(call.arguments as Map);
      if (call.method == 'read') return records[args['key']];
      if (call.method == 'writeAll') { records.addAll(Map<String,String>.from(args['values'] as Map)); return null; }
      throw MissingPluginException();
    });
    expect(await ProtectedLocalStore.read('report_draft_test'), 'legacy draft');
    expect((await SharedPreferences.getInstance()).containsKey('report_draft_test'), isFalse);
    expect(records['report_draft_test'], 'legacy draft');
    // A stale copy left by an interrupted migration cannot replace committed data.
    await (await SharedPreferences.getInstance()).setString('report_draft_test', 'stale');
    expect(await ProtectedLocalStore.read('report_draft_test'), 'legacy draft');
    expect((await SharedPreferences.getInstance()).containsKey('report_draft_test'), isFalse);
  });

  test('native failure retains legacy data and does not fall back to plaintext', () async {
    SharedPreferences.setMockInitialValues({'report_draft_test':'recoverable'});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'read') return null;
      throw PlatformException(code:'LOCAL_DATA_UNAVAILABLE');
    });
    await expectLater(ProtectedLocalStore.read('report_draft_test'), throwsA(isA<PlatformException>()));
    expect((await SharedPreferences.getInstance()).getString('report_draft_test'), 'recoverable');
  });

  test('unverified migration retains its original data', () async {
    SharedPreferences.setMockInitialValues({'report_draft_test':'recoverable'});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (_) async => null);
    await expectLater(ProtectedLocalStore.read('report_draft_test'), throwsStateError);
    expect((await SharedPreferences.getInstance()).getString('report_draft_test'), 'recoverable');
  });

  test('concurrent writes stay ordered and unrelated keys are rejected', () async {
    final records = <String,String>{};
    final received = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      final args = Map<Object?,Object?>.from(call.arguments as Map);
      if (call.method == 'read') return records[args['key']];
      if (call.method == 'writeAll') { final values=Map<String,String>.from(args['values'] as Map); received.add(values.values.single); await Future<void>.delayed(Duration.zero); records.addAll(values); return null; }
      throw MissingPluginException();
    });
    await Future.wait([ProtectedLocalStore.writeAll({'report_draft_test':'first'}), ProtectedLocalStore.writeAll({'report_draft_test':'second'})]);
    expect(received, ['first','second']);
    expect(await ProtectedLocalStore.read('report_draft_test'), 'second');
    await expectLater(ProtectedLocalStore.read('unrelated'), throwsArgumentError);
  });
}
