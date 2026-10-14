import 'dart:async';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gestionale_radio/services/session_service.dart';

class AccessIdentity extends Fake implements IdTokenResult {
  AccessIdentity(this.claims, this.authTime);
  @override
  final Map<String, dynamic> claims;
  @override
  final DateTime? authTime;
  @override
  String get token => 'synthetic-identity';
}

class AccessUser extends Fake implements User {
  AccessUser(this.uid, this.claims);
  @override
  final String uid;
  Map<String, dynamic> claims;
  DateTime? authenticatedAt;
  Object? error;
  @override
  Future<IdTokenResult> getIdTokenResult([bool forceRefresh = false]) async {
    if (error != null) throw error!;
    return AccessIdentity(claims, authenticatedAt);
  }
}

class AccessAuth extends Fake implements FirebaseAuth {
  @override
  User? currentUser;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final claims = <String, dynamic>{
    'tenantId': 'company-a',
    'operatorId': 'op-a',
    'role': 'OPERATOR',
  };
  late AccessUser user;
  late AccessAuth auth;
  late DateTime now;
  late SessionService session;
  late List<http.Request> requests;
  var status = 200;
  var body = '';
  var bound = 0;
  Future<http.Response> Function(http.Request)? respond;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    now = DateTime.utc(2026, 10, 13, 12);
    user = AccessUser('user-a', Map.of(claims));
    auth = AccessAuth()..currentUser = user;
    requests = [];
    status = 200;
    body = '';
    bound = 0;
    respond = null;
    session = SessionService(
      auth: auth,
      now: () => now,
      bindDevice: (_, _) async {
        bound++;
      },
      onApproved: () {},
      client: MockClient((request) async {
        requests.add(request);
        if (respond != null) return respond!(request);
        return http.Response(
          body.isNotEmpty
              ? body
              : jsonEncode({
                  'data': {'uid': auth.currentUser?.uid, 'claims': user.claims},
                }),
          status,
        );
      }),
    );
  });

  test(
    'restored session is validated online without reactivation QR',
    () async {
      expect(await session.resolveAccess(), AccessState.approved);
      expect(requests.single.url.path, '/api/v1/auth/me');
      expect(bound, 0);
      expect(session.tenantId, 'company-a');
    },
  );
  test(
    'a newly authenticated technician binds a device, elevated identity retains its protected login',
    () async {
      user.authenticatedAt = now;
      expect(await session.resolveAccess(), AccessState.approved);
      expect(bound, 1);
      user.claims = {...claims, 'role': 'ENGINEER'};
      expect(
        await session.resolveAccess(forceRefresh: true),
        AccessState.approved,
      );
      expect(bound, 1);
      expect(session.managementOnly, isTrue);
    },
  );
  test(
    'offline grace survives service restart, expires and rejects a backwards clock',
    () async {
      expect(await session.resolveAccess(), AccessState.approved);
      user.error = FirebaseAuthException(code: 'network-request-failed');
      final restored = SessionService(
        auth: auth,
        now: () => now,
        client: MockClient((_) async => http.Response('{}', 503)),
        onApproved: () {},
      );
      now = now.add(const Duration(hours: 7));
      expect(await restored.resolveAccess(), AccessState.approvedOffline);
      now = now.add(const Duration(hours: 1));
      expect(await restored.resolveAccess(), AccessState.offline);
      expect(restored.tenantId, isNull);
      now = DateTime.utc(2026, 10, 13, 11);
      expect(await restored.resolveAccess(), AccessState.offline);
    },
  );
  test(
    'account switch clears visible scope immediately and never reuses another account offline grant',
    () async {
      expect(await session.resolveAccess(), AccessState.approved);
      auth.currentUser = AccessUser('user-b', {
        ...claims,
        'tenantId': 'company-b',
      })..error = FirebaseAuthException(code: 'network-request-failed');
      expect(session.tenantId, isNull);
      expect(await session.resolveAccess(), AccessState.offline);
    },
  );
  test(
    'the device revocation 401 contract is distinguished from token expiry',
    () async {
      expect(await session.resolveAccess(), AccessState.approved);
      status = 401;
      body = '{"message":"Dispositivo revocato: accedi nuovamente."}';
      expect(await session.resolveAccess(), AccessState.deviceRevoked);
      expect(session.tenantId, isNull);
      status = 200;
      user.error = FirebaseAuthException(code: 'network-request-failed');
      expect(await session.resolveAccess(), AccessState.offline);
    },
  );
  test(
    'explicit server denials erase the offline grant instead of permitting fallback',
    () async {
      expect(await session.resolveAccess(), AccessState.approved);
      status = 403;
      body = '{"message":"Dispositivo revocato."}';
      expect(await session.resolveAccess(), AccessState.deviceRevoked);
      expect(session.tenantId, isNull);
      user.error = FirebaseAuthException(code: 'network-request-failed');
      expect(await session.resolveAccess(), AccessState.offline);
    },
  );
  test(
    'expired and suspended sessions have distinct recovery states',
    () async {
      status = 401;
      expect(await session.resolveAccess(), AccessState.expired);
      user.error = FirebaseAuthException(code: 'user-disabled');
      expect(await session.resolveAccess(), AccessState.suspended);
    },
  );
  test(
    'tenant or role changes cannot reuse the previous offline authorization',
    () async {
      expect(await session.resolveAccess(), AccessState.approved);
      user.claims = {...claims, 'tenantId': 'company-b'};
      status = 503;
      expect(await session.resolveAccess(), AccessState.offline);
    },
  );
  test(
    'late validation response cannot publish a scope after identity replacement',
    () async {
      final response = Completer<http.Response>();
      respond = (_) => response.future;
      final validation = session.resolveAccess();
      await Future<void>.delayed(Duration.zero);
      auth.currentUser = AccessUser('user-b', {
        ...claims,
        'tenantId': 'company-b',
      });
      response.complete(
        http.Response(jsonEncode({'uid': 'user-a', 'claims': claims}), 200),
      );
      expect(await validation, AccessState.expired);
      expect(session.tenantId, isNull);
    },
  );
}
