import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:gestionale_radio/services/operator_presence_service.dart';
import 'session_access_test.dart' show AccessUser;

class PresenceAuth extends Fake implements FirebaseAuth {
  @override
  User? currentUser = AccessUser('user-a', {
    'tenantId': 'company-a',
    'role': 'OPERATOR',
  });
  final changes = StreamController<User?>.broadcast();
  @override
  Stream<User?> idTokenChanges() => changes.stream;
}

class PresenceSnapshot extends Fake implements DataSnapshot {
  PresenceSnapshot(this.value);
  @override
  final Object? value;
}

class PresenceEvent extends Fake implements DatabaseEvent {
  PresenceEvent(bool value) : snapshot = PresenceSnapshot(value);
  @override
  final DataSnapshot snapshot;
}

class PresenceDisconnect extends Fake implements OnDisconnect {
  PresenceDisconnect(this.database);
  final PresenceDatabase database;
  @override
  Future<void> update(Map<String, Object?> values) async {
    database.events.add('cleanup');
    database.cleanup.add(values);
  }
}

class PresenceReference extends Fake implements DatabaseReference {
  PresenceReference(this.database, this.path);
  final PresenceDatabase database;
  @override
  final String path;
  @override
  String? get key => path.split('/').last;
  @override
  DatabaseReference child(String path) =>
      PresenceReference(database, '${this.path}/$path');
  @override
  DatabaseReference push() => child('phone-${++database.sequence}');
  @override
  Stream<DatabaseEvent> get onValue => database.connected.stream;
  @override
  OnDisconnect onDisconnect() => PresenceDisconnect(database);
  @override
  Future<void> set(Object? value) async {
    database.events.add('publish');
    database.published.add((path: path, value: value));
  }
}

class PresenceDatabase extends Fake implements FirebaseDatabase {
  final connected = StreamController<DatabaseEvent>.broadcast();
  final events = <String>[];
  final cleanup = <Map<String, Object?>>[];
  final published = <({String path, Object? value})>[];
  var sequence = 0, offline = 0;
  bool online = false;
  @override
  DatabaseReference ref([String? path]) => PresenceReference(this, path ?? '');
  @override
  Future<void> goOnline() async {
    if (!online) {
      online = true;
      connected.add(PresenceEvent(true));
    }
  }

  @override
  Future<void> goOffline() async {
    offline++;
    online = false;
    connected.add(PresenceEvent(false));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PresenceAuth auth;
  late PresenceDatabase database;
  late OperatorPresenceService service;
  setUp(() {
    auth = PresenceAuth();
    database = PresenceDatabase();
    service = OperatorPresenceService(
      auth: auth,
      databaseFactory: (_) => database,
      client: MockClient(
        (_) async => http.Response(
          '{"databaseURL":"https://qa.europe-west1.firebasedatabase.app"}',
          200,
        ),
      ),
    );
  });
  tearDown(() async {
    await service.dispose();
    await auth.changes.close();
    await database.connected.close();
  });
  Future<void> connect() async {
    service.initialize();
    service.didChangeAppLifecycleState(AppLifecycleState.resumed);
    service.setAccessAllowed(true);
    await service.settle();
    await Future<void>.delayed(Duration.zero);
    await service.settle();
  }

  test(
    'authorized foreground publishes only after server disconnect cleanup and background has its own state',
    () async {
      await connect();
      expect(database.events.first, 'cleanup');
      expect((database.published.last.value as Map)['state'], 'foreground');
      expect(
        (database.published.last.value as Map)['updatedAt'],
        ServerValue.timestamp,
      );
      service.didChangeAppLifecycleState(AppLifecycleState.paused);
      await service.settle();
      expect((database.published.last.value as Map)['state'], 'background');
      expect(database.online, isTrue);
      service.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await service.settle();
      expect((database.published.last.value as Map)['state'], 'foreground');
      expect(database.cleanup.single['lastSeen'], ServerValue.timestamp);
    },
  );
  test(
    'revocation closes the connection and resume cannot silently reauthorize presence',
    () async {
      await connect();
      service.setAccessAllowed(false);
      await service.settle();
      final published = database.published.length;
      service.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await service.settle();
      expect(database.online, isFalse);
      expect(database.published.length, published);
    },
  );
  test(
    'another account gets an independent device path after the previous connection is closed',
    () async {
      await connect();
      auth.currentUser = AccessUser('user-b', {
        'tenantId': 'company-b',
        'role': 'OPERATOR',
      });
      auth.changes.add(auth.currentUser);
      await Future<void>.delayed(Duration.zero);
      await service.settle();
      await Future<void>.delayed(Duration.zero);
      await service.settle();
      expect(
        database.published.last.path,
        startsWith('presence/company-b/user-b/'),
      );
      expect(database.cleanup, hasLength(2));
    },
  );
}
