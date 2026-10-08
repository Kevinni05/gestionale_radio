import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class ReportDraftStore {
  static String storageKey({
    required String tenantId,
    required String operatorUid,
    required String taskScope,
  }) {
    final scope = '$tenantId|$operatorUid|$taskScope';
    final encoded = base64Url.encode(utf8.encode(scope)).replaceAll('=', '');
    return 'report_draft_$encoded';
  }

  Future<Map<String, dynamic>?> load(String key) async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(key);
    if (raw == null || raw.isEmpty) return null;

    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic>
          ? Map<String, dynamic>.from(decoded)
          : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> save(String key, Map<String, dynamic> draft) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(key, jsonEncode(draft));
  }

  Future<void> delete(String key) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(key);
  }
}
