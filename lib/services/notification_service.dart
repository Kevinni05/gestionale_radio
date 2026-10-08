import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import '../firebase_options.dart';
import 'personal_badge_cache.dart';
import 'api_http_client.dart';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'auth_service.dart';
import 'api_service.dart';
import 'app_navigation.dart';

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  bool _authListenerRegistered = false;

  Future<void> initialize() async {
    try {
      await _initializeLocalNotifications();
      await _requestPermission();
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      final token = await _messaging.getToken();

      if (token != null) await _registerTokenWithBackend(token);

      if (!_authListenerRegistered) {
        _authListenerRegistered = true;
        FirebaseAuth.instance.authStateChanges().listen((_) async {
          final refreshedToken = await _messaging.getToken();
          if (refreshedToken != null) {
            await _registerTokenWithBackend(refreshedToken);
          }
        });
      }

      _messaging.onTokenRefresh.listen((newToken) async {
        await _registerTokenWithBackend(newToken);
      });

      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

      FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationOpened);

      final initialMessage = await FirebaseMessaging.instance
          .getInitialMessage();

      if (initialMessage != null) {
        _handleNotificationOpened(initialMessage);
      }
    } catch (e) {
      debugPrint('Errore inizializzazione notifiche: $e');
    }
  }

  /// Ri-registra il token FCM sul backend (es. dopo l'approvazione dell'account,
  /// quando prima il backend rispondeva 403).
  Future<void> syncTokenWithBackend() async {
    try {
      final token = await _messaging.getToken();
      if (token != null) await _registerTokenWithBackend(token);
    } catch (e) {
      debugPrint('Sync token FCM non riuscita: $e');
    }
  }

  Future<void> _initializeLocalNotifications() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    await _localNotifications.initialize(
      settings: const InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: (response) =>
          AppNavigation.openTask(response.payload),
    );

    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        'radiotech_alerts',
        'Alert RadioTech',
        description: 'Notifiche operative e task assegnati',
        importance: Importance.max,
      ),
    );
    await androidPlugin?.requestNotificationsPermission();
  }

  Future<void> _requestPermission() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return;
    }

    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    debugPrint(
      'Stato autorizzazione notifiche: '
      '${settings.authorizationStatus}',
    );
  }

  Future<void> _registerTokenWithBackend(String token) async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      debugPrint('FCM token ricevuto ma nessun utente autenticato.');
      return;
    }

    try {
      final idToken = await AuthService.instance.requireIdToken();
      await _ensureOperatorRegistered(idToken, user);
      final response = await ApiHttpClient.instance.post(
        Uri.parse('${ApiService.baseUrl}/api/v1/operator/me/fcm-token'),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'fcmToken': token}),
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint(
          'Registrazione token FCM rifiutata: ${response.statusCode} ${response.body}',
        );
        return;
      }

      debugPrint('FCM token registrato per ${user.uid}');
    } catch (e) {
      debugPrint('Errore registrazione token FCM: $e');
    }
  }

  Future<void> _ensureOperatorRegistered(String idToken, User user) async {
    final response = await ApiHttpClient.instance.post(
      Uri.parse('${ApiService.baseUrl}/api/v1/operator/register'),
      headers: {
        'Authorization': 'Bearer $idToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'fullName':
            user.displayName ?? user.email?.split('@').first ?? 'Operatore',
        'email': user.email,
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Impossibile associare l account operatore.');
    }
  }

  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    if (message.data['type'] == 'BADGE_UPDATED') {
      try {
        await PersonalBadgeCache.refresh();
      } catch (_) {
        /* Resume and profile polling will retry. */
      }
      return;
    }
    if (message.data['taskId'] != null) AppNavigation.refreshTasks();
    debugPrint(
      'Notifica ricevuta in foreground: '
      '${message.notification?.title}',
    );

    debugPrint('Payload: ${message.data}');
    final notification = message.notification;
    if (notification != null) {
      _localNotifications.show(
        id: message.hashCode,
        title: notification.title ?? 'RadioTech',
        body: notification.body ?? 'Nuova comunicazione operativa',
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'radiotech_alerts',
            'Alert RadioTech',
            channelDescription: 'Notifiche operative e task assegnati',
            importance: Importance.max,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
          ),
          iOS: DarwinNotificationDetails(),
        ),
        payload: message.data['taskId'],
      );
    }
  }

  void _handleNotificationOpened(RemoteMessage message) {
    AppNavigation.openTask(message.data['taskId']?.toString());
  }

  Future<void> clearDeviceToken() async {
    try {
      await PersonalBadgeCache.clearOwn();
      await _messaging.deleteToken();
    } catch (_) {
      /* Logout must still complete. */
    }
    AppNavigation.requestedTask.value = null;
  }
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (message.data['type'] != 'BADGE_UPDATED') return;
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
    await FirebaseAppCheck.instance.activate(
      providerAndroid: const bool.fromEnvironment('APP_CHECK_DEBUG')
          ? AndroidDebugProvider()
          : AndroidPlayIntegrityProvider(),
      providerApple: const bool.fromEnvironment('APP_CHECK_DEBUG')
          ? AppleDebugProvider()
          : AppleDeviceCheckProvider(),
    );
    await ApiService.initializeEndpoint();
    await PersonalBadgeCache.refresh().timeout(const Duration(seconds: 20));
  } catch (_) {
    /* Android may defer delivery; foreground/resume always retry. */
  }
}
