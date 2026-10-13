import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import 'api_service.dart';

/// Foreground presence is independent of Firebase Auth and FCM registration.
/// One connection per process prevents one phone from hiding another phone.
class OperatorPresenceService with WidgetsBindingObserver {
  OperatorPresenceService._();
  static final instance = OperatorPresenceService._();
  static const _roles = {
    'OPERATOR',
    'OPERATORE',
    'VIEWER',
    'ADMIN',
    'SUPER_ADMIN',
    'CAPO',
    'CHIEF_EXECUTIVE',
    'NETWORK_MANAGER',
    'ENGINEER',
  };
  FirebaseDatabase? _database;
  DatabaseReference? _account;
  String? _scope;
  String? _connectionId;
  StreamSubscription<DatabaseEvent>? _connected;
  bool _initialized = false;
  bool _foreground = false;
  int _revision = 0;
  Future<void> _work = Future.value();

  void initialize() {
    if (_initialized) return;
    _initialized = true;
    _foreground =
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    FirebaseAuth.instance.idTokenChanges().listen((_) => _schedule());
    _schedule();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Inactive can be a temporary camera/system dialog; hidden/paused means
    // the app is no longer visible. Resume reconnects without another login.
    if (state == AppLifecycleState.resumed) {
      _foreground = true;
      _schedule();
    } else if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _foreground = false;
      unawaited(stop());
    }
  }

  void _schedule() {
    _work = _work.then((_) => _refresh()).catchError((Object error) {
      debugPrint('Presenza non disponibile: ${error.runtimeType}');
    });
  }

  Future<void> stop() async {
    _revision++;
    // Closing just this database connection executes the server-side
    // onDisconnect operation, even if an explicit offline write cannot finish.
    await _database?.goOffline();
  }

  Future<void> _refresh() async {
    final user = FirebaseAuth.instance.currentUser;
    if (!_foreground || user == null) {
      await stop();
      return;
    }
    final revision = _revision;
    final identity = await user.getIdTokenResult();
    final tenant = identity.claims?['tenantId']?.toString();
    final role = identity.claims?['role']?.toString().toUpperCase();
    if (tenant == null || tenant.isEmpty || !_roles.contains(role)) {
      await stop();
      return;
    }
    if (!_foreground ||
        FirebaseAuth.instance.currentUser?.uid != user.uid ||
        revision != _revision) {
      return;
    }

    if (_database == null) {
      final response = await http
          .get(Uri.parse('${ApiService.baseUrl}/api/v1/auth/public-config'))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return;
      final config = jsonDecode(response.body) as Map<String, dynamic>;
      final url = config['databaseURL']?.toString() ?? '';
      final uri = Uri.tryParse(url);
      if (uri == null ||
          uri.scheme != 'https' ||
          !(uri.host.endsWith('.firebasedatabase.app') ||
              uri.host.endsWith('.firebaseio.com')) ||
          uri.userInfo.isNotEmpty ||
          uri.hasQuery ||
          uri.hasFragment) {
        return;
      }
      if (!_foreground || revision != _revision) return;
      _database = FirebaseDatabase.instanceFor(
        app: FirebaseAuth.instance.app,
        databaseURL: url,
      );
      await _database!.goOffline();
    }

    final scope = '$tenant/${user.uid}';
    if (_scope != scope) {
      await _database!.goOffline();
      await _connected?.cancel();
      _scope = scope;
      _account = _database!.ref('presence/$scope');
      _connectionId = _account!.child('connections').push().key!;
      _connected = _database!
          .ref('.info/connected')
          .onValue
          .listen(
            (event) {
              if (event.snapshot.value == true && _foreground) {
                final activeScope = _scope;
                _work = _work.then((_) => _publish(activeScope)).catchError((
                  Object error,
                ) {
                  debugPrint(
                    'Connessione presenza non disponibile: ${error.runtimeType}',
                  );
                });
              }
            },
            onError: (Object error) {
              debugPrint(
                'Monitor presenza non disponibile: ${error.runtimeType}',
              );
            },
          );
    }
    if (_foreground &&
        FirebaseAuth.instance.currentUser?.uid == user.uid &&
        revision == _revision) {
      await _database!.goOnline();
    }
  }

  Future<void> _publish(String? scope) async {
    final account = _account;
    final connectionId = _connectionId;
    final revision = _revision;
    if (!_foreground ||
        scope != _scope ||
        account == null ||
        connectionId == null) {
      return;
    }
    // Register cleanup BEFORE announcing online. This also updates lastSeen
    // using the server clock and preserves other devices' connection entries.
    await account
        .onDisconnect()
        .update({
          'connections/$connectionId': null,
          'lastSeen': ServerValue.timestamp,
        })
        .timeout(const Duration(seconds: 5));
    if (!_foreground ||
        scope != _scope ||
        revision != _revision ||
        FirebaseAuth.instance.currentUser?.uid != scope?.split('/').last) {
      return;
    }
    await account
        .child('connections/$connectionId')
        .set(true)
        .timeout(const Duration(seconds: 5));
  }
}
