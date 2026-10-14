import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestionale_radio/services/attendance_clock.dart';

void main() {
  test(
    'queue is cleared only after confirmed transfer to the manager',
    () async {
      final disk = <String, String>{};
      bool online = true, receipt = false;
      List<dynamic> archived = [];
      Future<dynamic> request(
        String path, {
        String method = 'GET',
        Map<String, dynamic>? body,
      }) async {
        if (path.endsWith('/recovery')) {
          if (!receipt) throw const SocketException('offline');
          archived = body!['events'] as List;
          return {'id': 'recovery'};
        }
        if (!online && method == 'PUT') throw const SocketException('offline');
        return {'status': 'OFF_DUTY', 'version': 0};
      }

      final clock = AttendanceClock(
        request: request,
        identity: () => 'a',
        read: (k) async => disk[k],
        write: (k, v) async {
          disk[k] = v;
        },
      );
      await clock.load();
      online = false;
      await clock.punch('START');
      await expectLater(
        clock.transferToManager(),
        throwsA(isA<SocketException>()),
      );
      expect(clock.queue.length, 1);
      receipt = true;
      online = true;
      await clock.transferToManager();
      expect(archived.length, 1);
      expect(clock.queue, isEmpty);
      expect(clock.displayState!['status'], 'OFF_DUTY');
    },
  );

  test(
    'offline punches survive reload and replay exactly once with original IDs',
    () async {
      final disk = <String, String>{};
      var online = true;
      var server = <String, dynamic>{
        'status': 'OFF_DUTY',
        'version': 0,
        'workMinutes': 0,
        'restMinutes': 0,
      };
      final operations = <String>{};
      Future<dynamic> request(
        String path, {
        String method = 'GET',
        Map<String, dynamic>? body,
      }) async {
        if (!online) throw const SocketException('offline');
        if (method == 'PUT' && operations.add(body!['operationId'] as String)) {
          expect(body['expectedVersion'], server['version']);
          server = {
            ...server,
            'version': (server['version'] as int) + 1,
            'status': body['action'] == 'START' ? 'ACTIVE' : 'OFF_DUTY',
          };
        }
        return server;
      }

      AttendanceClock make() => AttendanceClock(
        request: request,
        identity: () => 'tenant:uid',
        read: (key) async => disk[key],
        write: (key, value) async {
          disk[key] = value;
        },
      );
      final clock = make();
      await clock.load();
      online = false;
      await clock.punch('START');
      await clock.punch('END');
      expect(clock.queue.length, 2);
      expect(clock.displayState!['status'], 'OFF_DUTY');
      expect(operations, isEmpty);
      final ids = clock.queue.map((r) => r['operationId']).toList();
      final restored = make();
      await restored.load();
      expect(restored.queue.map((r) => r['operationId']), ids);
      online = true;
      await restored.sync();
      expect(restored.queue, isEmpty);
      expect(server['version'], 2);
      expect(operations.length, 2);
      expect((jsonDecode(disk['tenant:uid']!) as Map)['queue'], isEmpty);
    },
  );
  test(
    'lost response retries identical operation and version conflicts keep the queue',
    () async {
      final disk = <String, String>{};
      var version = 0;
      var lose = true;
      final operations = <String>{};
      Future<dynamic> request(
        String path, {
        String method = 'GET',
        Map<String, dynamic>? body,
      }) async {
        if (method == 'PUT') {
          if (operations.add(body!['operationId'] as String)) version++;
          if (lose) {
            lose = false;
            throw const SocketException('lost response');
          }
        }
        return {
          'status': version == 0 ? 'OFF_DUTY' : 'ACTIVE',
          'version': version,
        };
      }

      final clock = AttendanceClock(
        request: request,
        identity: () => 'a',
        read: (k) async => disk[k],
        write: (k, v) async {
          disk[k] = v;
        },
      );
      await clock.load();
      await clock.punch('START');
      expect(clock.queue.length, 1);
      await clock.sync();
      expect(version, 1);
      expect(clock.queue, isEmpty);
      final conflict = AttendanceClock(
        request: (path, {method = 'GET', body}) async {
          if (method == 'PUT') throw StateError('Conflict');
          return {'status': 'OFF_DUTY', 'version': 0};
        },
        identity: () => 'b',
        read: (k) async => disk[k],
        write: (k, v) async {
          disk[k] = v;
        },
      );
      await conflict.load();
      await conflict.punch('START');
      expect(conflict.queue.length, 1);
      expect(conflict.syncError, contains('Conflict'));
      await expectLater(conflict.punch('END'), throwsStateError);
    },
  );
  test(
    'changing identity cannot replay or write another users queued actions',
    () async {
      var identity = 'a';
      var writes = 0;
      var puts = 0;
      final clock = AttendanceClock(
        request: (path, {method = 'GET', body}) async {
          if (method == 'PUT') puts++;
          return {'status': 'OFF_DUTY', 'version': 0};
        },
        identity: () => identity,
        read: (_) async => null,
        write: (_, _) async {
          writes++;
        },
      );
      await clock.load();
      identity = 'b';
      await expectLater(clock.punch('START'), throwsStateError);
      expect(puts, 0);
      expect(writes, 1);
    },
  );
}
