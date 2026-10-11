import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gestionale_radio/services/local_operational_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'validated migration commits the pair before removing legacy values',
    () async {
      SharedPreferences.setMockInitialValues({
        'primary': 'old',
        'backup': 'new',
      });
      final records = <String, String?>{};
      var writes = 0;
      final store = LocalOperationalStore(
        useNative: true,
        invoke: (method, args) async {
          if (method == 'read') {
            final key = args['key'] as String;
            return {'found': records.containsKey(key), 'value': records[key]};
          }
          final values = Map<String, String?>.from(args['values'] as Map);
          final preferences = await SharedPreferences.getInstance();
          expect(preferences.getString('primary'), 'old');
          expect(preferences.getString('backup'), 'new');
          records.addAll(values);
          writes++;
          return true;
        },
      );
      expect(await store.read('primary'), 'old');
      await store.writeAll({'primary': 'new', 'backup': 'new'});
      expect(writes, 1);
      expect(await store.read('primary'), 'new');
      expect(
        (await SharedPreferences.getInstance()).containsKey('primary'),
        isFalse,
      );
      expect(
        (await SharedPreferences.getInstance()).containsKey('backup'),
        isFalse,
      );
    },
  );

  test(
    'database failure preserves all legacy data and reaches the caller',
    () async {
      SharedPreferences.setMockInitialValues({'draft': '{"id":"original"}'});
      final store = LocalOperationalStore(
        useNative: true,
        invoke: (method, args) async {
          if (method == 'read') return {'found': false, 'value': null};
          throw StateError('database unavailable');
        },
      );
      await expectLater(
        store.adoptValidated({'draft': '{"id":"original"}'}),
        throwsStateError,
      );
      expect(
        (await SharedPreferences.getInstance()).getString('draft'),
        '{"id":"original"}',
      );
    },
  );

  test(
    'native tombstone prevents legacy resurrection after interrupted cleanup',
    () async {
      SharedPreferences.setMockInitialValues({'draft': 'stale'});
      final store = LocalOperationalStore(
        useNative: true,
        invoke: (method, args) async => {'found': true, 'value': null},
      );
      expect(await store.read('draft'), isNull);
      expect(
        (await SharedPreferences.getInstance()).getString('draft'),
        'stale',
      );
    },
  );

  test('native error never falls back to a stale plaintext record', () async {
    SharedPreferences.setMockInitialValues({'draft': 'stale'});
    final store = LocalOperationalStore(
      useNative: true,
      invoke: (method, args) async => throw StateError('key unavailable'),
    );
    await expectLater(store.read('draft'), throwsStateError);
  });
}
