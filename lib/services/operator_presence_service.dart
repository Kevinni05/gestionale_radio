import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import 'api_service.dart';

/// Lifecycle/connection evidence is independent of FCM and availability.
/// One connection per process prevents one phone from hiding another phone.
class OperatorPresenceService with WidgetsBindingObserver {
  OperatorPresenceService({
    FirebaseAuth? auth,
    http.Client? client,
    FirebaseDatabase Function(String)? databaseFactory,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _client = client ?? http.Client() {
    _databaseFactory =
        databaseFactory ??
        ((url) =>
            FirebaseDatabase.instanceFor(app: _auth.app, databaseURL: url));
  }
  static final instance = OperatorPresenceService();
  final FirebaseAuth _auth;
  final http.Client _client;
  late final FirebaseDatabase Function(String) _databaseFactory;
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
  bool _accessAllowed = false;
  bool _isConnected = false;
  bool _cleanupRegistered = false;
  Timer? _heartbeat;
  StreamSubscription<User?>? _identityChanges;
  int _revision = 0;
  Future<void> _work = Future.value();

  void initialize() {
    if (_initialized) return;
    _initialized = true;
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    _identityChanges = _auth.idTokenChanges().listen((_) => _schedule());
    _schedule();
    _heartbeat = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_accessAllowed && _database != null) _schedule();
    });
  }

  void setAccessAllowed(bool allowed) {
    if (_accessAllowed == allowed) return;
    _accessAllowed = allowed;
    _revision++;
    if (allowed) {
      _schedule();
    } else {
      unawaited(stop());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Inactive can be a temporary camera/system dialog; hidden/paused means
    // the app is no longer visible. Resume reconnects without another login.
    if (state == AppLifecycleState.resumed) {
      _foreground = true;
      _revision++;
      _schedule();
    } else if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      _foreground = false;
      _revision++;
      _schedule();
    } else if (state == AppLifecycleState.detached) {
      _accessAllowed = false;
      _heartbeat?.cancel();
      unawaited(stop());
    }
  }

  void _schedule() {
    _work = _work.then((_) => _refresh()).catchError((Object error) {
      debugPrint('Presenza non disponibile: ${error.runtimeType}');
    });
  }

  Future<void> stop() async {
    _accessAllowed = false;
    _revision++;
    _isConnected = false;
    _cleanupRegistered = false;
    // Closing just this database connection executes the server-side
    // onDisconnect operation, even if an explicit offline write cannot finish.
    await _database?.goOffline();
  }

  Future<void> _refresh() async {
    final user = _auth.currentUser;
    if (!_accessAllowed || user == null) {
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
    if (!_accessAllowed ||
        _auth.currentUser?.uid != user.uid ||
        revision != _revision) {
      return;
    }

    if (_database == null) {
      final response = await _client
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
      if (!_accessAllowed || revision != _revision) return;
      _database = _databaseFactory(url);
      await _database!.goOffline();
    }

    final scope = '$tenant/${user.uid}';
    if (_scope != scope) {
      _cleanupRegistered = false;
      _isConnected = false;
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
              _isConnected = event.snapshot.value == true;
              if (!_isConnected) _cleanupRegistered = false;
              if (_isConnected && _accessAllowed) {
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
    if (_accessAllowed &&
        _auth.currentUser?.uid == user.uid &&
        revision == _revision) {
      await _database!.goOnline();
      if (_isConnected) await _publish(_scope);
    }
  }

  Future<void> _publish(String? scope) async {
    final account = _account;
    final connectionId = _connectionId;
    final revision = _revision;
    if (!_accessAllowed ||
        scope != _scope ||
        account == null ||
        connectionId == null) {
      return;
    }
    // Register cleanup BEFORE announcing online. This also updates lastSeen
    // using the server clock and preserves other devices' connection entries.
    if (!_cleanupRegistered) {
      await account
          .onDisconnect()
          .update({
            'connections/$connectionId': null,
            'lastSeen': ServerValue.timestamp,
          })
          .timeout(const Duration(seconds: 5));
      _cleanupRegistered = true;
    }
    if (!_accessAllowed ||
        scope != _scope ||
        revision != _revision ||
        _auth.currentUser?.uid != scope?.split('/').last) {
      return;
    }
    await account
        .child('connections/$connectionId')
        .set({
          'state': _foreground ? 'foreground' : 'background',
          'updatedAt': ServerValue.timestamp,
        })
        .timeout(const Duration(seconds: 5));
  }

  Future<void> dispose() async {
    _heartbeat?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    await _identityChanges?.cancel();
    await _connected?.cancel();
    await stop();
  }

  Future<void> settle() async {
    Future<void> pending;
    do {
      pending = _work;
      await pending;
    } while (!identical(pending, _work));
  }
}
