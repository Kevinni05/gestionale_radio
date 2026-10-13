import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gestionale_radio/services/app_navigation.dart';
import 'package:gestionale_radio/services/notification_service.dart';

class TestIdentity extends Fake implements IdTokenResult {
  TestIdentity(this.token, this.claims);
  @override
  final String token;
  @override
  final Map<String, dynamic> claims;
}

class TestUser extends Fake implements User {
  TestUser(this.uid, {this.tenant = 'company-a', this.role = 'OPERATOR'});
  @override
  final String uid;
  final String tenant, role;
  @override
  Future<IdTokenResult> getIdTokenResult([bool forceRefresh = false]) async =>
      TestIdentity('identity-$uid', {'role': role, 'tenantId': tenant});
  @override
  Future<String?> getIdToken([bool forceRefresh = false]) async =>
      'identity-$uid';
}

class TestAuth extends Fake implements FirebaseAuth {
  @override
  User? currentUser = TestUser('user-a');
  final changes = StreamController<User?>.broadcast();
  @override
  Stream<User?> idTokenChanges() => changes.stream;
}

class TestMessaging extends Fake implements FirebaseMessaging {
  final refreshes = StreamController<String>.broadcast();
  Future<String?> Function() token = () async => 'installation-token';
  RemoteMessage? initial;
  int deletes = 0;
  int deleteFailures = 0;
  @override
  Stream<String> get onTokenRefresh => refreshes.stream;
  @override
  Future<String?> getToken({
    String? vapidKey,
    String? serviceWorkerScriptPath,
  }) => token();
  @override
  Future<RemoteMessage?> getInitialMessage() async => initial;
  @override
  Future<void> deleteToken() async {
    if (deleteFailures-- > 0) throw StateError('Rotation unavailable');
    deletes++;
  }
}

class TestNotifications extends Fake
    implements FlutterLocalNotificationsPlugin {
  final shown = <String?>[];
  int failures = 0;
  DidReceiveNotificationResponseCallback? tapped;
  @override
  Future<bool?> initialize({
    required InitializationSettings settings,
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
    DidReceiveBackgroundNotificationResponseCallback?
    onDidReceiveBackgroundNotificationResponse,
  }) async {
    tapped = onDidReceiveNotificationResponse;
    return true;
  }

  @override
  Future<NotificationAppLaunchDetails?>
  getNotificationAppLaunchDetails() async => null;
  @override
  T? resolvePlatformSpecificImplementation<
    T extends FlutterLocalNotificationsPlatform
  >() => null;
  @override
  Future<void> show({
    required int id,
    String? title,
    String? body,
    NotificationDetails? notificationDetails,
    String? payload,
  }) async {
    if (failures-- > 0) throw StateError('Channel unavailable');
    shown.add(payload);
  }

  @override
  Future<void> cancelAll() async {
    shown.clear();
  }
}

RemoteMessage notice(
  String id, {
  String uid = 'user-a',
  String tenant = 'company-a',
  String? task,
  bool dataOnly = false,
}) => RemoteMessage(
  data: {
    'notificationId': id,
    'recipientUid': uid,
    'tenantId': tenant,
    'taskId': ?task,
    if (dataOnly) 'title': 'Comunicazione dalla centrale',
    if (dataOnly) 'message': 'Nuovo avviso',
  },
  notification: dataOnly
      ? null
      : const RemoteNotification(
          title: 'Comunicazione dalla centrale',
          body: 'Nuovo avviso',
        ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TestAuth auth;
  late TestMessaging messaging;
  late TestNotifications local;
  late StreamController<RemoteMessage> messages, opened;
  late StreamController<bool> network;
  late List<http.Request> requests;
  late NotificationService service;
  var status = 200;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppNavigation.clearRequests();
    auth = TestAuth();
    messaging = TestMessaging();
    local = TestNotifications();
    messages = StreamController.broadcast();
    opened = StreamController.broadcast();
    network = StreamController.broadcast();
    requests = [];
    status = 200;
    service = NotificationService(
      auth: auth,
      messaging: messaging,
      localNotifications: local,
      messages: messages.stream,
      openedMessages: opened.stream,
      networkChanges: network.stream,
      registerBackgroundHandler: () {},
      client: MockClient((request) async {
        requests.add(request);
        return http.Response('{}', status);
      }),
    );
  });
  tearDown(() async {
    await service.dispose();
    await messages.close();
    await opened.close();
    await network.close();
    await auth.changes.close();
    await messaging.refreshes.close();
    AppNavigation.clearRequests();
  });

  testWidgets(
    'startup token failure preserves reception, navigation and network recovery',
    (tester) async {
      messaging.token = () async =>
          throw StateError('Play Services temporarily unavailable');
      await service.initialize();
      await service.initialize();
      messages.add(notice('general'));
      await tester.pumpAndSettle();
      expect(local.shown, hasLength(1));
      opened.add(notice('general'));
      await tester.pumpAndSettle();
      expect(AppNavigation.requestedNotification.value, 'general');
      messaging.token = () async => 'recovered-token';
      network.add(false);
      network.add(true);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(requests.last.url.path, '/api/v1/operator/me/fcm-token');
      expect(jsonDecode(requests.last.body), {'fcmToken': 'recovered-token'});
    },
  );

  testWidgets(
    'cold-start general notice opens inbox before an unavailable token',
    (tester) async {
      messaging.initial = notice('cold-general');
      messaging.token = () async => throw StateError('Offline');
      await service.initialize();
      expect(AppNavigation.requestedNotification.value, 'cold-general');
      expect(AppNavigation.requestedTask.value, isNull);
    },
  );

  testWidgets(
    'foreground assignment refreshes tasks and inbox, deduplicates and remains tappable',
    (tester) async {
      await service.initialize();
      final taskRevision = AppNavigation.tasksRevision.value;
      final inboxRevision = AppNavigation.notificationsRevision.value;
      messages.add(notice('assignment', task: 'task-42'));
      messages.add(notice('assignment', task: 'task-42'));
      await tester.pumpAndSettle();
      expect(local.shown, hasLength(1));
      expect(AppNavigation.tasksRevision.value, taskRevision + 1);
      expect(AppNavigation.notificationsRevision.value, inboxRevision + 1);
      local.tapped!(
        NotificationResponse(
          notificationResponseType:
              NotificationResponseType.selectedNotification,
          payload: local.shown.single,
        ),
      );
      await tester.pumpAndSettle();
      expect(AppNavigation.requestedTask.value, 'task-42');
    },
  );

  testWidgets(
    'failed banners retry and data-only foreground notices are visible',
    (tester) async {
      await service.initialize();
      local.failures = 1;
      messages.add(notice('retry-banner', dataOnly: true));
      await tester.pumpAndSettle();
      expect(local.shown, isEmpty);
      messages.add(notice('retry-banner', dataOnly: true));
      await tester.pumpAndSettle();
      expect(local.shown, hasLength(1));
    },
  );

  testWidgets(
    'wrong-account and wrong-tenant pushes never display or navigate',
    (tester) async {
      await service.initialize();
      for (final message in [
        notice('other-user', uid: 'user-b'),
        notice('other-tenant', tenant: 'company-b'),
      ]) {
        messages.add(message);
        opened.add(message);
      }
      await tester.pumpAndSettle();
      expect(local.shown, isEmpty);
      expect(AppNavigation.requestedNotification.value, isNull);
      expect(AppNavigation.requestedTask.value, isNull);
    },
  );

  testWidgets(
    'backend rejection retries on resume with the same installation token',
    (tester) async {
      status = 503;
      await service.initialize();
      expect(requests.single.url.path, '/api/v1/operator/me/fcm-token');
      status = 200;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(requests, hasLength(2));
      expect(requests.last.body, requests.first.body);
    },
  );

  testWidgets(
    'account switch while obtaining token cannot register it to the previous account',
    (tester) async {
      final pending = Completer<String?>();
      messaging.token = () => pending.future;
      final sync = service.syncTokenWithBackend();
      auth.currentUser = TestUser('user-b', tenant: 'company-b');
      pending.complete('device-token');
      await sync;
      expect(requests, isEmpty);
      await service.syncTokenWithBackend();
      expect(
        requests.single.headers['Authorization'],
        'Bearer identity-user-b',
      );
    },
  );

  testWidgets(
    'logout blocks registration until auth departs, then login registers the new account',
    (tester) async {
      await service.initialize();
      requests.clear();
      await service.clearDeviceToken();
      await service.syncTokenWithBackend();
      expect(requests.map((r) => r.method), ['DELETE']);
      expect(messaging.deletes, 1);
      auth.currentUser = null;
      auth.changes.add(null);
      await tester.pumpAndSettle();
      auth.currentUser = TestUser('user-b', tenant: 'company-b');
      auth.changes.add(auth.currentUser);
      await tester.pumpAndSettle();
      expect(requests.last.method, 'POST');
      expect(requests.last.headers['Authorization'], 'Bearer identity-user-b');
    },
  );

  testWidgets(
    'direct account replacement rotates the device token and clears old notification destinations',
    (tester) async {
      await service.initialize();
      AppNavigation.openNotification('old-account');
      requests.clear();
      auth.currentUser = TestUser('user-b', tenant: 'company-b');
      messaging.token = () async => 'replacement-token';
      auth.changes.add(auth.currentUser);
      await tester.pumpAndSettle();
      expect(messaging.deletes, 1);
      expect(AppNavigation.requestedNotification.value, isNull);
      expect(
        requests.single.headers['Authorization'],
        'Bearer identity-user-b',
      );
      expect(jsonDecode(requests.single.body), {
        'fcmToken': 'replacement-token',
      });
      opened.add(notice('old-account'));
      await tester.pumpAndSettle();
      expect(AppNavigation.requestedNotification.value, isNull);
    },
  );

  testWidgets(
    'failed rotation keeps the next account unassociated until recovery succeeds',
    (tester) async {
      await service.initialize();
      requests.clear();
      messaging.deleteFailures = 1;
      auth.currentUser = TestUser('user-b', tenant: 'company-b');
      auth.changes.add(auth.currentUser);
      await tester.pumpAndSettle();
      expect(requests, isEmpty);
      opened.add(notice('next-account', uid: 'user-b', tenant: 'company-b'));
      await tester.pumpAndSettle();
      expect(AppNavigation.requestedNotification.value, isNull);
      await service.syncTokenWithBackend();
      expect(messaging.deletes, 1);
      expect(
        requests.single.headers['Authorization'],
        'Bearer identity-user-b',
      );
    },
  );
}
