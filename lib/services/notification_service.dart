import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import '../firebase_options.dart';
import '../config/product_brand.dart';
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
import 'notification_delivery_guard.dart';
import 'session_service.dart';

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  bool _authListenerRegistered = false;
  Future<void>? _initialization;
  final _deliveryGuard = NotificationDeliveryGuard();

  Future<void> initialize() {
    return _initialization ??= _initialize();
  }

  Future<void> _initialize() async {
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
      onDidReceiveNotificationResponse: (response) async {
        try {
          final payload = jsonDecode(response.payload ?? '{}');
          if (payload is Map<String, dynamic>) await _openPayload(payload);
        } catch (_) {
          // Old task-only payloads cannot establish the receiving account.
        }
      },
    );

    final launch = await _localNotifications.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true) {
      try {
        final payload = jsonDecode(
          launch?.notificationResponse?.payload ?? '{}',
        );
        if (payload is Map<String, dynamic>) await _openPayload(payload);
      } catch (_) {
        // Inbox remains available if an old notification cannot be resolved.
      }
    }

    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidPlugin?.createNotificationChannel(
      AndroidNotificationChannel(
        'radiotech_alerts',
        'Alert ${ProductBrand.appName}',
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

      debugPrint('FCM token registrato sul backend.');
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
    if (!await _acceptPayload(message.data, 'show')) return;
    if (message.data['type'] == 'BADGE_UPDATED') {
      try {
        await PersonalBadgeCache.refresh();
      } catch (_) {
        /* Resume and profile polling will retry. */
      }
      return;
    }
    if (message.data['taskId'] != null) AppNavigation.refreshTasks();
    debugPrint('Notifica operativa ricevuta in foreground.');
    final notification = message.notification;
    if (notification != null) {
      await _localNotifications.show(
        id: notificationDisplayId(message.data['notificationId'] as String),
        title: notification.title ?? ProductBrand.appName,
        body: notification.body ?? 'Nuova comunicazione operativa',
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            'radiotech_alerts',
            'Alert ${ProductBrand.appName}',
            channelDescription: 'Notifiche operative e task assegnati',
            importance: Importance.max,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
          ),
          iOS: const DarwinNotificationDetails(),
        ),
        payload: jsonEncode(message.data),
      );
    }
  }

  Future<bool> _acceptPayload(Map<String, dynamic> data, String channel) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return false;
      final claims = await user.getIdTokenResult();
      final tenant = claims.claims?['tenantId']?.toString() ?? '';
      if (FirebaseAuth.instance.currentUser?.uid != user.uid ||
          !SessionService.isAppRole(claims.claims?['role'])) {
        return false;
      }
      final accepted = await _deliveryGuard.accept(
        data,
        uid: user.uid,
        tenantId: tenant,
        channel: channel,
      );
      return accepted && FirebaseAuth.instance.currentUser?.uid == user.uid;
    } catch (_) {
      return false;
    }
  }

  Future<void> _openPayload(Map<String, dynamic> data) async {
    if (!await _acceptPayload(data, 'open')) return;
    AppNavigation.openTask(data['taskId']?.toString());
  }

  Future<void> _handleNotificationOpened(RemoteMessage message) =>
      _openPayload(message.data);

  /// Stable across process restarts; OS updates the same banner on redelivery.
  static int notificationDisplayId(String id) {
    var hash = 2166136261;
    for (final byte in utf8.encode(id)) {
      hash = ((hash ^ byte) * 16777619) & 0x7fffffff;
    }
    return hash;
  }

  Future<void> clearDeviceToken() async {
    // Remove the relationship while the departing user's ID token is valid.
    // Local token deletion still runs if the backend is unavailable.
    try {
      final token = await _messaging.getToken();
      if (token != null && FirebaseAuth.instance.currentUser != null) {
        final idToken = await AuthService.instance.requireIdToken();
        await ApiHttpClient.instance
            .delete(
              Uri.parse('${ApiService.baseUrl}/api/v1/operator/me/fcm-token'),
              headers: {
                'Authorization': 'Bearer $idToken',
                'Content-Type': 'application/json',
              },
              body: jsonEncode({'fcmToken': token}),
            )
            .timeout(const Duration(seconds: 10));
      }
    } catch (_) {
      // Deleting the installation token invalidates stale server associations.
    }
    try {
      await _messaging.deleteToken();
    } catch (_) {
      /* Logout must still complete. */
    }
    try {
      await _localNotifications.cancelAll();
    } catch (_) {
      /* Complete logout. */
    }
    try {
      await PersonalBadgeCache.clearOwn();
    } catch (_) {
      /* Complete logout. */
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
