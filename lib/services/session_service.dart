import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'api_http_client.dart';
import 'api_service.dart';
import 'local_operational_store.dart';
import 'notification_service.dart';
import 'offline_sync_service.dart';

enum AccessState {
  approved,
  approvedOffline,
  pending,
  offline,
  expired,
  suspended,
  deviceRevoked,
  error,
}

/// Restored identity is checked by the API; offline access only permits local work.
class SessionService {
  SessionService({
    FirebaseAuth? auth,
    http.Client? client,
    LocalOperationalStore? store,
    DateTime Function()? now,
    Future<void> Function(String, String)? bindDevice,
    void Function()? onApproved,
    this.offlineGrace = const Duration(hours: 8),
  }) : _injectedAuth = auth,
       _client = client ?? ApiHttpClient.instance,
       _store = store ?? LocalOperationalStore.instance,
       _now = now ?? DateTime.now,
       _bindDevice = bindDevice ?? ApiService.instance.bindDeviceSession,
       _onApproved =
           onApproved ??
           (() {
             unawaited(NotificationService.instance.syncTokenWithBackend());
             unawaited(OfflineSyncService.instance.retryPending());
           });
  static final instance = SessionService();
  final FirebaseAuth? _injectedAuth;
  FirebaseAuth get _auth => _injectedAuth ?? FirebaseAuth.instance;
  final http.Client _client;
  final LocalOperationalStore _store;
  final DateTime Function() _now;
  final Future<void> Function(String, String) _bindDevice;
  final void Function() _onApproved;
  final Duration offlineGrace;
  String? _uid, _tenantId, _operatorId, _role;
  int _revision = 0;
  String? _blockedOfflineUid;

  Stream<String?> get scopeChanges =>
      _auth.idTokenChanges().asyncMap((user) async {
        if (user == null) return null;
        final claims = (await user.getIdTokenResult()).claims;
        return jsonEncode([user.uid, claims?['tenantId'], claims?['role']]);
      }).distinct();

  void invalidateScope() {
    final uid = _auth.currentUser?.uid;
    _revision++;
    _blockedOfflineUid = uid;
    _clear();
    if (uid != null) {
      unawaited(
        _store.delete(_key(uid)).catchError((Object _) {
          debugPrint('Verifica locale sospesa: ripristina la sessione online.');
        }),
      );
    }
  }

  bool get _ownsScope => _uid != null && _auth.currentUser?.uid == _uid;
  String? get tenantId => _ownsScope ? _tenantId : null;
  String? get operatorId => _ownsScope ? _operatorId : null;
  String? get role => _ownsScope ? _role : null;
  bool get isCustomer => _ownsScope && _role == 'CUSTOMER';
  bool get managementOnly =>
      _ownsScope &&
      {
        'CHIEF_EXECUTIVE',
        'CAPO',
        'NETWORK_MANAGER',
        'ENGINEER',
        'VIEWER',
      }.contains(_role);
  bool get canManage => _ownsScope && {'ADMIN', 'SUPER_ADMIN'}.contains(_role);
  bool get canManageAccounts =>
      _ownsScope &&
      {'ADMIN', 'SUPER_ADMIN', 'CHIEF_EXECUTIVE', 'CAPO'}.contains(_role);
  static const _appRoles = {
    'OPERATOR',
    'OPERATORE',
    'ADMIN',
    'SUPER_ADMIN',
    'CUSTOMER',
    'CHIEF_EXECUTIVE',
    'CAPO',
    'NETWORK_MANAGER',
    'ENGINEER',
    'VIEWER',
  };
  static const _deviceRoles = {'OPERATOR', 'OPERATORE', 'CUSTOMER', 'VIEWER'};
  static bool isAppRole(Object? role) =>
      _appRoles.contains(role?.toString().trim().toUpperCase());
  static bool allowsLocalAccess(AccessState state) =>
      state == AccessState.approved || state == AccessState.approvedOffline;
  static String _key(String uid) =>
      'session_validation_${base64Url.encode(utf8.encode(uid))}';
  bool _current(User user, int revision) =>
      _revision == revision && _auth.currentUser?.uid == user.uid;
  void _clear() {
    _uid = _tenantId = _operatorId = _role = null;
  }

  void _capture(String uid, Map<String, dynamic> claims) {
    _uid = uid;
    _tenantId = claims['tenantId']?.toString().trim();
    _operatorId = claims['operatorId']?.toString().trim();
    _role = claims['role']?.toString().trim().toUpperCase();
  }

  Future<AccessState> resolveAccess({bool forceRefresh = false}) async {
    final user = _auth.currentUser;
    final revision = ++_revision;
    if (user == null) {
      _clear();
      return AccessState.expired;
    }
    try {
      var identity = await user
          .getIdTokenResult(forceRefresh)
          .timeout(const Duration(seconds: 15));
      if (!_current(user, revision)) return AccessState.expired;
      var claims = identity.claims ?? <String, dynamic>{};
      if (!isAppRole(claims['role']) ||
          (claims['tenantId']?.toString().trim() ?? '').isEmpty) {
        if (!forceRefresh) {
          identity = await user
              .getIdTokenResult(true)
              .timeout(const Duration(seconds: 15));
          claims = identity.claims ?? <String, dynamic>{};
        }
        if (!_current(user, revision)) return AccessState.expired;
        if (!isAppRole(claims['role']) ||
            (claims['tenantId']?.toString().trim() ?? '').isEmpty) {
          _clear();
          await _store.delete(_key(user.uid));
          return AccessState.pending;
        }
      }
      final token = identity.token;
      if (token == null || token.isEmpty) {
        _clear();
        return AccessState.expired;
      }
      final response = await _client
          .get(
            Uri.parse(ApiService.apiV1Url('/auth/me')),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 15));
      if (!_current(user, revision)) return AccessState.expired;
      if (response.statusCode == 401 || response.statusCode == 403) {
        _clear();
        await _store.delete(_key(user.uid));
        if (response.statusCode == 401) return AccessState.expired;
        String message = '';
        try {
          message =
              (jsonDecode(response.body) as Map)['message']
                  ?.toString()
                  .toLowerCase() ??
              '';
        } catch (_) {}
        return message.contains('dispositivo')
            ? AccessState.deviceRevoked
            : AccessState.suspended;
      }
      if (response.statusCode >= 500 ||
          response.statusCode == 429 ||
          response.statusCode == 408) {
        return _offline(user, revision, expectedClaims: claims);
      }
      if (response.statusCode != 200) {
        _clear();
        return AccessState.error;
      }
      final raw = jsonDecode(response.body);
      final data = raw is Map && raw['data'] is Map
          ? raw['data'] as Map
          : raw as Map;
      if (data['uid'] != user.uid || data['claims'] is! Map) {
        _clear();
        return AccessState.error;
      }
      claims = Map<String, dynamic>.from(data['claims'] as Map);
      if (!isAppRole(claims['role']) ||
          (claims['tenantId']?.toString().trim() ?? '').isEmpty) {
        _clear();
        await _store.delete(_key(user.uid));
        return AccessState.pending;
      }
      final role = claims['role']?.toString().trim().toUpperCase();
      final age = identity.authTime == null
          ? null
          : _now().difference(identity.authTime!);
      if (claims['radioDeviceId'] == null &&
          age != null &&
          age >= Duration.zero &&
          age <= const Duration(minutes: 5) &&
          _deviceRoles.contains(role)) {
        await _bindDevice(claims['tenantId'].toString(), user.uid);
        if (!_current(user, revision)) return AccessState.expired;
      }
      await _store.write(
        _key(user.uid),
        jsonEncode({
          'uid': user.uid,
          'claims': {
            'tenantId': claims['tenantId'],
            'role': claims['role'],
            'operatorId': claims['operatorId'],
          },
          'validatedAt': _now().toUtc().toIso8601String(),
        }),
      );
      if (!_current(user, revision)) return AccessState.expired;
      _capture(user.uid, claims);
      _blockedOfflineUid = null;
      if (!isCustomer && !managementOnly) _onApproved();
      return AccessState.approved;
    } on FirebaseAuthException catch (error) {
      if (!_current(user, revision)) return AccessState.expired;
      if (error.code == 'network-request-failed') {
        return _offline(user, revision);
      }
      _clear();
      await _store.delete(_key(user.uid));
      return error.code == 'user-disabled'
          ? AccessState.suspended
          : AccessState.expired;
    } on SocketException {
      return _offline(user, revision);
    } on TimeoutException {
      return _offline(user, revision);
    } on http.ClientException {
      return _offline(user, revision);
    } catch (error) {
      if (_current(user, revision)) _clear();
      debugPrint('Verifica accesso non riuscita: ${error.runtimeType}');
      return AccessState.error;
    }
  }

  Future<AccessState> _offline(
    User user,
    int revision, {
    Map<String, dynamic>? expectedClaims,
  }) async {
    if (!_current(user, revision)) return AccessState.expired;
    if (_blockedOfflineUid == user.uid) return AccessState.offline;
    try {
      final raw = await _store.read(_key(user.uid));
      if (!_current(user, revision)) return AccessState.expired;
      if (raw != null) {
        final record = jsonDecode(raw) as Map;
        final age = _now().difference(
          DateTime.parse(record['validatedAt'] as String),
        );
        final claims = Map<String, dynamic>.from(record['claims'] as Map);
        if (record['uid'] == user.uid &&
            (expectedClaims == null ||
                expectedClaims['tenantId'] == claims['tenantId'] &&
                    expectedClaims['role'] == claims['role']) &&
            age >= Duration.zero &&
            age < offlineGrace &&
            isAppRole(claims['role']) &&
            (claims['tenantId']?.toString().trim() ?? '').isNotEmpty) {
          _capture(user.uid, claims);
          return AccessState.approvedOffline;
        }
      }
    } catch (_) {
      /* Preserve unreadable records for recovery. */
    }
    if (_current(user, revision)) _clear();
    return AccessState.offline;
  }
}
