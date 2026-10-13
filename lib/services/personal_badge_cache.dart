import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'auth_service.dart';
import 'company_api.dart';
import 'session_service.dart';

/// Credentials stay encrypted and scoped to the Firebase owner, including
/// updates received by Android's background messaging isolate.
class PersonalBadgeCache {
  static const _storage = FlutterSecureStorage();
  static final revision = ValueNotifier<int>(0);
  static Future<void> refresh() async {
    final uid = AuthService.instance.currentUid;
    final tenant = SessionService.instance.tenantId;
    if (uid == null) return;
    final data = await CompanyApi.instance.request('/operator/me/badge');
    if (uid != AuthService.instance.currentUid ||
        tenant != SessionService.instance.tenantId) {
      return;
    }
    await _storage.write(key: 'rt_badge_$uid', value: jsonEncode(data));
    revision.value++;
  }

  static Future<void> clearOwn() async {
    final uid = AuthService.instance.currentUid;
    if (uid != null) await _storage.delete(key: 'rt_badge_$uid');
  }
}
