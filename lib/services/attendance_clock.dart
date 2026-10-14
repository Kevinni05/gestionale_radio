import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../ai_hub_screen.dart' show CompanyRequest;
import 'auth_service.dart';
import 'company_api.dart';
import 'session_service.dart';

/// Durable, identity-scoped queue. A lost response retains the same operation ID.
/// Conflicts stop replay and remain visible; queued records are never shown as confirmed.
class AttendanceClock {
  AttendanceClock({
    CompanyRequest? request,
    this._identity,
    this._read,
    this._write,
  }) : _request = request ?? CompanyApi.instance.request;
  final CompanyRequest _request;
  final String Function()? _identity;
  final Future<String?> Function(String)? _read;
  final Future<void> Function(String, String)? _write;
  final _storage = const FlutterSecureStorage();
  Map<String, dynamic>? state;
  List<Map<String, dynamic>> queue = [];
  String? _scope;
  String? syncError;
  bool _busy = false;
  String get scope {
    if (_identity != null) return _identity();
    final uid = AuthService.instance.currentUid;
    final tenant = SessionService.instance.tenantId;
    if (uid == null || tenant == null) {
      throw StateError('Sessione non disponibile.');
    }
    return 'radiotech-attendance-v1:$tenant:$uid';
  }

  void _checkScope(String saved) {
    if (scope != saved) {
      throw StateError('Account cambiato: riapri Presenze e turni.');
    }
  }

  Future<void> _save() async {
    final captured = _scope!;
    _checkScope(captured);
    final encoded = jsonEncode({'state': state, 'queue': queue});
    if (_write != null) {
      await _write(captured, encoded);
    } else {
      await _storage.write(key: captured, value: encoded);
    }
    _checkScope(captured);
  }

  Future<void> load() async {
    final captured = scope;
    _scope = captured;
    final raw = _read != null
        ? await _read(captured)
        : await _storage.read(key: captured);
    _checkScope(captured);
    if (raw != null) {
      final data = jsonDecode(raw) as Map;
      state = data['state'] == null
          ? null
          : Map<String, dynamic>.from(data['state'] as Map);
      queue = (data['queue'] as List)
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList();
    }
    await sync();
  }

  static bool transport(Object e) =>
      e is SocketException ||
      e is TimeoutException ||
      e is http.ClientException;
  Future<void> sync() async {
    if (_busy) return;
    _busy = true;
    final captured = _scope!;
    syncError = null;
    try {
      _checkScope(captured);
      while (queue.isNotEmpty) {
        final result = await _request(
          '/workforce/me/shift',
          method: 'PUT',
          body: queue.first,
        );
        _checkScope(captured);
        state = Map<String, dynamic>.from(result as Map);
        queue.removeAt(0);
        await _save();
      }
      final result = await _request('/workforce/me/shift');
      _checkScope(captured);
      state = Map<String, dynamic>.from(result as Map);
      await _save();
    } catch (e) {
      syncError = transport(e)
          ? 'Rete non disponibile. Timbrature conservate sul dispositivo.'
          : e.toString();
      if (state == null) rethrow;
    } finally {
      _busy = false;
    }
  }

  Map<String, dynamic>? get displayState {
    try {
      if (_scope != scope) return null;
    } catch (_) {
      return null;
    }
    if (state == null) return null;
    final result = Map<String, dynamic>.from(state!);
    for (final row in queue) {
      result['status'] = switch (row['action']) {
        'START' || 'RESUME' => 'ACTIVE',
        'BREAK' => 'BREAK',
        _ => 'OFF_DUTY',
      };
      result['version'] = (result['version'] as num).toInt() + 1;
    }
    return result;
  }

  Future<void> transferToManager() async {
    if (_busy || queue.isEmpty) return;
    _busy = true;
    final captured = _scope!;
    try {
      _checkScope(captured);
      await _request(
        '/workforce/me/attendance/recovery',
        method: 'POST',
        body: {'events': List<Map<String, dynamic>>.from(queue)},
      );
      _checkScope(captured);
      queue = [];
      syncError = null;
      await _save();
    } finally {
      _busy = false;
    }
    await sync();
  }

  Future<void> punch(String action) async {
    if (_busy) throw StateError('Sincronizzazione in corso.');
    if (state == null) {
      throw StateError('Collegati prima di registrare una timbratura.');
    }
    _checkScope(_scope!);
    if (queue.length >= 100) {
      throw StateError('Sincronizza le timbrature in attesa.');
    }
    // Server conflicts must be resolved before accepting more local transitions.
    if (syncError != null && !syncError!.startsWith('Rete non disponibile')) {
      throw StateError(
        'Risolvi la sincronizzazione prima di aggiungere altre timbrature.',
      );
    }
    queue.add({
      'action': action,
      'readiness': 'READY',
      'expectedVersion': displayState!['version'],
      'operationId': CompanyApi.operationId(),
      'occurredAt': DateTime.now().toUtc().toIso8601String(),
    });
    await _save();
    await sync();
  }
}
