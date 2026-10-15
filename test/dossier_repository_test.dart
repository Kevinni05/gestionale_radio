import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestionale_radio/services/dossier_repository.dart';

void main() {
  final now = DateTime.utc(2026, 10, 15);
  Map<String, dynamic> snapshot() => {
    'antennaId': 'a',
    'name': 'Antenna A',
    'version': 1,
    'validUntil': now.add(const Duration(hours: 24)).toIso8601String(),
    'documents': [
      {'fileId': 'file-a'},
    ],
    'photos': [
      {'fileId': 'file-a'},
    ],
  };
  test(
    'complete download deduplicates originals and retains annotations',
    () async {
      final storage = <String, String>{};
      var reads = 0;
      final repo = DossierRepository(
        owner: () => 'account-a',
        now: () => now,
        read: (key) async => storage[key],
        write: (key, value) async {
          storage[key] = value;
        },
        remove: (key) async {
          storage.remove(key);
        },
        request: (path, {method = 'GET', body}) async {
          if (path.endsWith('/dossier')) return snapshot();
          reads++;
          return {
            'name': 'original.pdf',
            'base64': base64Encode([1, 2, 3]),
          };
        },
      );
      await repo.download('a');
      expect(reads, 1);
      final cached = await repo.offline('a');
      expect(cached!['name'], 'Antenna A');
      expect(
        ((cached['_offlineFiles'] as Map)['file-a'] as Map)['base64'],
        base64Encode([1, 2, 3]),
      );
    },
  );
  test('failed download preserves previous complete pack', () async {
    final storage = <String, String>{'dossier_account-a_a': 'previous'};
    final repo = DossierRepository(
      owner: () => 'account-a',
      now: () => now,
      read: (key) async => storage[key],
      write: (key, value) async {
        storage[key] = value;
      },
      remove: (key) async {
        storage.remove(key);
      },
      request: (path, {method = 'GET', body}) async {
        if (path.endsWith('/dossier')) return snapshot();
        throw StateError('Network lost');
      },
    );
    await expectLater(repo.download('a'), throwsStateError);
    expect(storage['dossier_account-a_a'], 'previous');
  });
  test('expired pack is deleted and cannot be opened', () async {
    final storage = <String, String>{
      'dossier_account-a_a': jsonEncode({
        'owner': 'account-a',
        'validUntil': now
            .subtract(const Duration(seconds: 1))
            .toIso8601String(),
        'data': snapshot(),
        'files': {},
      }),
    };
    final repo = DossierRepository(
      owner: () => 'account-a',
      now: () => now,
      read: (key) async => storage[key],
      write: (key, value) async {
        storage[key] = value;
      },
      remove: (key) async {
        storage.remove(key);
      },
    );
    expect(await repo.offline('a'), isNull);
    expect(storage, isEmpty);
  });
  test(
    'identity switch during fetch never writes another accounts data',
    () async {
      var owner = 'account-a';
      var writes = 0;
      final repo = DossierRepository(
        owner: () => owner,
        now: () => now,
        write: (key, value) async {
          writes++;
        },
        request: (path, {method = 'GET', body}) async {
          owner = 'account-b';
          return snapshot();
        },
      );
      await expectLater(repo.download('a'), throwsStateError);
      expect(writes, 0);
    },
  );
  test(
    'expiry during attachment download preserves the previous pack',
    () async {
      var clock = now;
      final storage = <String, String>{'dossier_account-a_a': 'previous'};
      final repo = DossierRepository(
        owner: () => 'account-a',
        now: () => clock,
        read: (key) async => storage[key],
        write: (key, value) async {
          storage[key] = value;
        },
        remove: (key) async {
          storage.remove(key);
        },
        request: (path, {method = 'GET', body}) async {
          if (path.endsWith('/dossier')) return snapshot();
          clock = now.add(const Duration(hours: 24));
          return {
            'name': 'original.pdf',
            'base64': base64Encode([1, 2, 3]),
          };
        },
      );
      await expectLater(repo.download('a'), throwsStateError);
      expect(storage['dossier_account-a_a'], 'previous');
    },
  );
  test('offline metadata and originals use the capped pack expiry', () async {
    var clock = now;
    final storage = <String, String>{};
    final repo = DossierRepository(
      owner: () => 'account-a',
      now: () => clock,
      read: (key) async => storage[key],
      write: (key, value) async {
        storage[key] = value;
      },
      remove: (key) async {
        storage.remove(key);
      },
      request: (path, {method = 'GET', body}) async {
        if (path.endsWith('/dossier')) {
          return snapshot()
            ..['validUntil'] = now
                .add(const Duration(days: 7))
                .toIso8601String();
        }
        return {
          'name': 'original.pdf',
          'base64': base64Encode([1, 2, 3]),
        };
      },
    );
    await repo.download('a');
    final cached = (await repo.offline('a'))!;
    expect(
      DateTime.parse(cached['validUntil'] as String),
      now.add(const Duration(hours: 24)),
    );
    clock = now.add(const Duration(hours: 24));
    await expectLater(repo.file('a', 'file-a', cached), throwsStateError);
    expect(await repo.offline('a'), isNull);
    expect(storage, isEmpty);
  });
  for (final logout in [false, true]) {
    final action = logout ? 'logout' : 'switch';
    test('identity $action during final write removes the pack', () async {
      var owner = 'account-a';
      var signedIn = true;
      final storage = <String, String>{};
      final repo = DossierRepository(
        owner: () {
          if (!signedIn) {
            throw StateError('Sessione operatore richiesta.');
          }
          return owner;
        },
        now: () => now,
        read: (key) async => storage[key],
        write: (key, value) async {
          storage[key] = value;
          if (logout) {
            signedIn = false;
          } else {
            owner = 'account-b';
          }
        },
        remove: (key) async {
          storage.remove(key);
        },
        request: (path, {method = 'GET', body}) async {
          if (path.endsWith('/dossier')) return snapshot();
          return {
            'name': 'original.pdf',
            'base64': base64Encode([1, 2, 3]),
          };
        },
      );
      await expectLater(repo.download('a'), throwsStateError);
      expect(storage, isEmpty);
    });
  }
}
