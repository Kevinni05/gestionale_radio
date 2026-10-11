import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gestionale_radio/services/notification_delivery_guard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final payload = <String, dynamic>{
    'notificationId': 'n1',
    'tenantId': 'company-a',
    'recipientUid': 'user-a',
    'taskId': 'task-a',
  };

  test(
    'rejects another account, tenant, legacy and missing identity',
    () async {
      final guard = NotificationDeliveryGuard();
      for (final identity in [
        (uid: 'user-b', tenantId: 'company-a'),
        (uid: 'user-a', tenantId: 'company-b'),
        (uid: '', tenantId: 'company-a'),
      ]) {
        expect(
          await guard.accept(
            payload,
            uid: identity.uid,
            tenantId: identity.tenantId,
            channel: 'open',
          ),
          isFalse,
        );
      }
      expect(
        await guard.accept(
          {'taskId': 'legacy'},
          uid: 'user-a',
          tenantId: 'company-a',
          channel: 'open',
        ),
        isFalse,
      );
      expect(
        await guard.accept(
          payload,
          uid: 'user-a',
          tenantId: 'company-a',
          channel: 'open',
        ),
        isTrue,
      );
    },
  );

  test(
    'concurrent duplicates and process restart retain one receipt',
    () async {
      final guard = NotificationDeliveryGuard();
      final results = await Future.wait(
        List.generate(
          3,
          (_) => guard.accept(
            payload,
            uid: 'user-a',
            tenantId: 'company-a',
            channel: 'show',
          ),
        ),
      );
      expect(results.where((accepted) => accepted), hasLength(1));
      final restarted = NotificationDeliveryGuard();
      expect(
        await restarted.accept(
          payload,
          uid: 'user-a',
          tenantId: 'company-a',
          channel: 'show',
        ),
        isFalse,
      );
      // A delivered foreground banner can still be opened once.
      expect(
        await restarted.accept(
          payload,
          uid: 'user-a',
          tenantId: 'company-a',
          channel: 'open',
        ),
        isTrue,
      );
      expect(
        await restarted.accept(
          payload,
          uid: 'user-a',
          tenantId: 'company-a',
          channel: 'open',
        ),
        isFalse,
      );
    },
  );

  test('corrupt receipts are preserved and do not permit navigation', () async {
    final preferences = await SharedPreferences.getInstance();
    final key =
        'notification_receipts_${base64Url.encode(utf8.encode('company-a:user-a:open'))}';
    await preferences.setString(key, '{corrupt');
    await expectLater(
      NotificationDeliveryGuard().accept(
        payload,
        uid: 'user-a',
        tenantId: 'company-a',
        channel: 'open',
      ),
      throwsFormatException,
    );
    expect(preferences.getString(key), '{corrupt');
  });
}
