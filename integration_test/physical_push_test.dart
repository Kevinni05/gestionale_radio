import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:gestionale_radio/firebase_options.dart';
import 'package:gestionale_radio/services/api_service.dart';
import 'package:gestionale_radio/services/local_operational_store.dart';
import 'package:gestionale_radio/services/notification_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'physical QA receives FCM and persists the foreground receipt',
    (tester) async {
      const email = String.fromEnvironment('QA_EMAIL');
      const password = String.fromEnvironment('QA_PASSWORD');
      const expected = String.fromEnvironment('QA_NOTIFICATION_ID');
      const tenant = String.fromEnvironment('QA_TENANT_ID');
      expect(email.endsWith('@example.test'), true);
      expect(expected.startsWith('qa_push_'), true);
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final directory = await getApplicationDocumentsDirectory();
      final evidence = File('${directory.path}/qa-push.json');
      final received = Completer<RemoteMessage>();
      final subscription = FirebaseMessaging.onMessage.listen((message) {
        if (message.data['notificationId'] == expected &&
            !received.isCompleted) {
          received.complete(message);
        }
      });
      try {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(body: Text('Collaudo notifiche QA')),
          ),
        );
        await ApiService.initializeEndpoint();
        await NotificationService.instance.initialize();
        final token = await FirebaseMessaging.instance.getToken();
        expect(token, isNotEmpty);
        await evidence.writeAsString(
          jsonEncode({
            'phase': 'ready',
            'uid': uid,
            'tenantId': tenant,
            'notificationId': expected,
            'token': token,
          }),
          flush: true,
        );
        final message = await received.future.timeout(
          const Duration(minutes: 3),
        );
        expect(message.data['tenantId'], tenant);
        expect(message.data['recipientUid'], uid);
        final key =
            'notification_receipts_${base64Url.encode(utf8.encode('$tenant:$uid:show'))}';
        String? receipt;
        for (var attempt = 0; attempt < 30; attempt++) {
          await tester.pump(const Duration(milliseconds: 200));
          receipt = await LocalOperationalStore.instance.read(key);
          if (receipt?.contains(expected) == true) break;
        }
        expect(receipt, contains(expected));
        await evidence.writeAsString(
          jsonEncode({
            'phase': 'received',
            'notificationId': expected,
            'receivedAt': DateTime.now().toUtc().toIso8601String(),
            'foregroundReceipt': true,
          }),
          flush: true,
        );
      } finally {
        await subscription.cancel();
        await NotificationService.instance.clearDeviceToken();
        await FirebaseAuth.instance.signOut();
        await NotificationService.instance.dispose();
      }
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
