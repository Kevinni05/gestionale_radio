import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'auth_service.dart';
import 'session_service.dart';

/// Encrypted, identity-bound snapshots. No mutable workflow is accepted offline.
class OfflineTaskPackStore {
  static const _storage = FlutterSecureStorage();
  static String _owner() {
    final uid = AuthService.instance.currentUid,
        tenant = SessionService.instance.tenantId;
    if (uid == null || tenant == null || SessionService.instance.isCustomer) {
      throw StateError('Sessione operatore richiesta.');
    }
    return base64Url.encode(utf8.encode('$tenant:$uid'));
  }

  static Future<void> save(Map<String, dynamic> pack) async {
    final owner = _owner();
    if (pack['uid'] != AuthService.instance.currentUid ||
        pack['tenantId'] != SessionService.instance.tenantId) {
      throw StateError('Pacchetto appartenente ad un altro account.');
    }
    final task = Map<String, dynamic>.from(pack['task'] as Map);
    final key = 'taskpack_${owner}_${task['id']}';
    if (jsonEncode(pack).length > 1000000) {
      throw StateError('Pacchetto troppo grande per la copia offline.');
    }
    await _storage.write(key: key, value: jsonEncode(pack));
  }

  static Future<List<Map<String, dynamic>>> list() async {
    final owner = _owner();
    final values = await _storage.readAll();
    final packs = <Map<String, dynamic>>[];
    for (final item in values.entries.where(
      (e) => e.key.startsWith('taskpack_${owner}_'),
    )) {
      try {
        final pack = Map<String, dynamic>.from(jsonDecode(item.value) as Map);
        final until = DateTime.parse(pack['validUntil'] as String);
        if (pack['uid'] != AuthService.instance.currentUid ||
            pack['tenantId'] != SessionService.instance.tenantId ||
            until.isBefore(DateTime.now())) {
          await _storage.delete(key: item.key);
          continue;
        }
        packs.add(pack);
      } catch (_) {
        await _storage.delete(key: item.key);
      }
    }
    return packs;
  }

  static Future<void> clearOwn() async {
    final prefix = 'taskpack_${_owner()}_';
    for (final key in (await _storage.readAll()).keys.where(
      (k) => k.startsWith(prefix),
    )) {
      await _storage.delete(key: key);
    }
  }
}
