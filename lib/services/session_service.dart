import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'notification_service.dart';
import 'dart:async';
import 'offline_sync_service.dart';
import 'api_service.dart';

/// Esito del controllo di accesso all'app operatori.
enum AccessState {
  /// L'utente ha un ruolo abilitato all'app.
  approved,

  /// Account valido ma senza ruolo abilitato (es. auto-registrato, in attesa
  /// di approvazione da parte di un manager).
  pending,

  /// Non e' stato possibile verificare i permessi (rete assente, sessione scaduta).
  error,
}

/// Legge il ruolo dai custom claims dell'ID token Firebase.
///
/// Il backend assegna il claim `role` quando un manager approva l'operatore
/// (`POST /api/operators/{id}/approve`) o quando genera le credenziali.
class SessionService {
  SessionService._();

  static final SessionService instance = SessionService._();

  String? _tenantId;
  String? _operatorId;
  String? _role;

  String? get tenantId => _tenantId;
  String? get operatorId => _operatorId;
  bool get isCustomer => _role == 'CUSTOMER';
  bool get managementOnly =>
      {'CHIEF_EXECUTIVE', 'CAPO', 'NETWORK_MANAGER', 'ENGINEER', 'VIEWER'}.contains(_role);
  bool get canManage => {'ADMIN', 'SUPER_ADMIN'}.contains(_role);
  bool get canManageAccounts =>
      {'ADMIN', 'SUPER_ADMIN', 'CHIEF_EXECUTIVE', 'CAPO'}.contains(_role);

  /// Ruoli ammessi dal backend su `/api/operator/**`.
  static const Set<String> _appRoles = {
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

  static bool isAppRole(Object? role) {
    if (role == null) return false;
    return _appRoles.contains(role.toString().trim().toUpperCase());
  }

  Future<AccessState> resolveAccess({bool forceRefresh = false}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _tenantId = null;
      _operatorId = null;
      return AccessState.error;
    }

    try {
      var result = await user.getIdTokenResult(forceRefresh);
      _captureScope(result.claims);
      var approved = isAppRole(result.claims?['role']) && _tenantId != null;

      // Il token in cache puo' non avere ancora il claim appena assegnato dal
      // manager: prima di dichiarare "in attesa" chiediamo un token aggiornato.
      if (!approved && !forceRefresh) {
        result = await user.getIdTokenResult(true);
        _captureScope(result.claims);
        approved = isAppRole(result.claims?['role']) && _tenantId != null;
      }

      if (approved) {
        final recentLogin =
            result.authTime != null &&
            DateTime.now().difference(result.authTime!).inSeconds <= 300;
        if (result.claims?['radioDeviceId'] == null && recentLogin) {
          await ApiService.instance.bindDeviceSession(_tenantId!, user.uid);
          result = await FirebaseAuth.instance.currentUser!.getIdTokenResult(
            true,
          );
          _captureScope(result.claims);
          if (!isAppRole(result.claims?['role']) || _tenantId == null) {
            return AccessState.error;
          }
        }
        // Il token FCM non era stato accettato dal backend prima dell'approvazione.
        if (!isCustomer && !managementOnly) {
          unawaited(NotificationService.instance.syncTokenWithBackend());
          unawaited(OfflineSyncService.instance.retryPending());
        }
        return AccessState.approved;
      }
      return AccessState.pending;
    } catch (e) {
      _tenantId = null;
      _operatorId = null;
      debugPrint('Verifica accesso non riuscita: $e');
      return AccessState.error;
    }
  }

  void _captureScope(Map<String, dynamic>? claims) {
    _role = claims?['role']?.toString().trim().toUpperCase();
    final tenant = claims?['tenantId']?.toString().trim();
    final operator = claims?['operatorId']?.toString().trim();
    _tenantId = tenant == null || tenant.isEmpty ? null : tenant;
    _operatorId = operator == null || operator.isEmpty ? null : operator;
  }
}

