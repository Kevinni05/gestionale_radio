import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'api_http_client.dart';
import 'api_service.dart';
import 'auth_service.dart';
import 'company_api.dart';
import 'session_service.dart';

typedef DossierRequest =
    Future<dynamic> Function(
      String path, {
      String method,
      Map<String, dynamic>? body,
    });

/// Deliberate downloads only. Original attachments and metadata are encrypted,
/// bound to tenant/account, expire after 24h, and never queue mutations offline.
class DossierRepository {
  DossierRepository({
    DossierRequest? request,
    String Function()? owner,
    Future<String?> Function(String)? read,
    Future<void> Function(String, String)? write,
    Future<void> Function(String)? remove,
    DateTime Function()? now,
  }) : _request = request ?? CompanyApi.instance.request,
       _owner = owner ?? currentOwner,
       _read = read ?? ((key) => _storage.read(key: key)),
       _write =
           write ?? ((key, value) => _storage.write(key: key, value: value)),
       _remove = remove ?? ((key) => _storage.delete(key: key)),
       _now = now ?? DateTime.now;
  static const _storage = FlutterSecureStorage();
  static const maxPackBytes = 28 * 1024 * 1024;
  final DossierRequest _request;
  final String Function() _owner;
  final Future<String?> Function(String) _read;
  final Future<void> Function(String, String) _write;
  final Future<void> Function(String) _remove;
  final DateTime Function() _now;
  static String currentOwner() {
    final uid = AuthService.instance.currentUid,
        tenant = SessionService.instance.tenantId;
    if (uid == null || tenant == null || SessionService.instance.isCustomer) {
      throw StateError('Sessione operatore richiesta.');
    }
    return base64Url.encode(utf8.encode('$tenant:$uid'));
  }

  static String path(String id) =>
      '/antennas/${Uri.encodeComponent(id)}/dossier';
  void _check(String owner) {
    if (_owner() != owner) throw StateError('Sessione cambiata.');
  }

  Future<Map<String, dynamic>> load(String id) async {
    final owner = _owner();
    final result = Map<String, dynamic>.from(await _request(path(id)) as Map);
    _check(owner);
    return result;
  }

  Future<Map<String, dynamic>?> offline(String id) async {
    final owner = _owner(), key = 'dossier_${_owner()}_$id';
    final raw = await _read(key);
    _check(owner);
    if (raw == null) return null;
    final pack = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    if (pack['owner'] != owner ||
        !DateTime.parse(pack['validUntil'] as String).isAfter(_now())) {
      await _remove(key);
      return null;
    }
    return Map<String, dynamic>.from(pack['data'] as Map)
      ..['validUntil'] = pack['validUntil']
      ..['_offlineFiles'] = pack['files'];
  }

  Future<void> download(String id) async {
    final owner = _owner(), data = await load(id);
    final tenant = SessionService.instance.tenantId,
        uid = AuthService.instance.currentUid;
    if (tenant != null && data['tenantId'] != tenant ||
        uid != null && data['uid'] != uid) {
      throw StateError('Pacchetto appartenente a un altro account.');
    }
    final fileIds = <String>{};
    for (final section in ['photos', 'documents']) {
      for (final row in data[section] as List) {
        final fileId = (row as Map)['fileId'];
        if (fileId is String) fileIds.add(fileId);
      }
    }
    if (fileIds.length > 50) {
      throw StateError('Massimo 50 allegati per il pacchetto offline.');
    }
    final files = <String, dynamic>{};
    var total = 0;
    for (final fileId in fileIds) {
      final file = Map<String, dynamic>.from(
        await _request('${path(id)}/files/$fileId') as Map,
      );
      _check(owner);
      total += (file['base64'] as String).length;
      if (total > maxPackBytes - 1000000) {
        throw StateError(
          'Pacchetto troppo grande: riduci gli allegati o consulta online (limite 28 MB cifrati).',
        );
      }
      files[fileId] = file;
    }
    _check(owner);
    final expiry = DateTime.parse(data['validUntil'] as String);
    final until = expiry.isBefore(_now().add(const Duration(hours: 24)))
        ? expiry
        : _now().add(const Duration(hours: 24));
    if (!until.isAfter(_now())) {
      throw StateError(
        'Fascicolo scaduto durante il download. Riprova online.',
      );
    }
    final pack = jsonEncode({
      'owner': owner,
      'validUntil': until.toIso8601String(),
      'data': data,
      'files': files,
    });
    if (utf8.encode(pack).length > maxPackBytes) {
      throw StateError('Pacchetto troppo grande per il download offline.');
    }
    final key = 'dossier_${owner}_$id';
    _check(owner);
    await _write(key, pack);
    try {
      _check(owner);
    } catch (_) {
      await _remove(key);
      rethrow;
    }
  }

  Future<Map<String, dynamic>> file(
    String id,
    String fileId,
    Map<String, dynamic> dossier,
  ) async {
    final owner = _owner();
    final cached = dossier['_offlineFiles'];
    if (cached is Map && cached[fileId] is Map) {
      if (!DateTime.parse(dossier['validUntil'] as String).isAfter(_now())) {
        throw StateError('Copia offline scaduta.');
      }
      return Map<String, dynamic>.from(cached[fileId] as Map);
    }
    final file = Map<String, dynamic>.from(
      await _request('${path(id)}/files/$fileId') as Map,
    );
    _check(owner);
    return file;
  }

  Future<void> change(
    String id,
    int version,
    String section,
    Map<String, dynamic> data,
  ) async {
    await _request(
      '${path(id)}/changes',
      method: 'POST',
      body: {
        'expectedVersion': version,
        'operationId': CompanyApi.operationId(),
        'section': section,
        'data': data,
      },
    );
  }

  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
  }) => _request(path, method: method, body: body);
  Future<String> upload(String name, Uint8List bytes) async {
    if (bytes.isEmpty || bytes.length > 10000000) {
      throw StateError('La fotografia deve essere entro 10 MB.');
    }
    final owner = _owner(), revision = AuthService.instance.sessionRevision;
    void lease() {
      _check(owner);
      if (revision != AuthService.instance.sessionRevision) {
        throw StateError('Sessione cambiata.');
      }
    }

    final token = await AuthService.instance.requireIdToken();
    lease();
    final client = ApiHttpClient(
      refreshToken: () async {
        lease();
        final fresh = await AuthService.instance.refreshIdToken();
        lease();
        return fresh;
      },
    );
    try {
      final url = Uri.parse(ApiService.apiV1Url('/files')).replace(
        queryParameters: {
          'name': name,
          'operationId': CompanyApi.operationId(),
        },
      );
      final response = await client.post(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/octet-stream',
        },
        body: bytes,
      );
      lease();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError('Caricamento non riuscito.');
      }
      final result = jsonDecode(response.body) as Map;
      return (result['reference'] as String).replaceFirst(
        'radiotech-file:',
        '',
      );
    } finally {
      client.close();
    }
  }

  static Future<List<Map<String, dynamic>>> offlineIndex() async {
    final owner = currentOwner(), result = <Map<String, dynamic>>[];
    for (final item in (await _storage.readAll()).entries.where(
      (e) => e.key.startsWith('dossier_${owner}_'),
    )) {
      try {
        final pack = _mapPack(item.value);
        if (pack['owner'] != owner ||
            !DateTime.parse(
              pack['validUntil'] as String,
            ).isAfter(DateTime.now())) {
          await _storage.delete(key: item.key);
          continue;
        }
        final data = Map<String, dynamic>.from(pack['data'] as Map);
        result.add({
          'antennaId': data['antennaId'],
          'name': data['name'],
          'fetchedAt': data['fetchedAt'],
          'validUntil': pack['validUntil'],
        });
      } catch (_) {
        await _storage.delete(key: item.key);
      }
    }
    if (currentOwner() != owner) throw StateError('Sessione cambiata.');
    return result;
  }

  static Map<String, dynamic> _mapPack(String raw) =>
      Map<String, dynamic>.from(jsonDecode(raw) as Map);
  static Future<void> clearOwn() async {
    final prefix = 'dossier_${currentOwner()}_';
    for (final key in (await _storage.readAll()).keys.where(
      (key) => key.startsWith(prefix),
    )) {
      await _storage.delete(key: key);
    }
  }
}
