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
import 'api_service.dart';
import 'app_navigation.dart';
import 'notification_delivery_guard.dart';
import 'session_service.dart';
import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'sync_lifecycle_coordinator.dart';
import 'local_operational_store.dart';

class NotificationService {
  NotificationService({
    FirebaseAuth? auth,
    FirebaseMessaging? messaging,
    FlutterLocalNotificationsPlugin? localNotifications,
    http.Client? client,
    Stream<RemoteMessage>? messages,
    Stream<RemoteMessage>? openedMessages,
    Stream<bool>? networkChanges,
    void Function()? registerBackgroundHandler,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _messaging = messaging ?? FirebaseMessaging.instance,
       _localNotifications =
           localNotifications ?? FlutterLocalNotificationsPlugin(),
       _client = client ?? ApiHttpClient.instance,
       _messages = messages ?? FirebaseMessaging.onMessage,
       _openedMessages = openedMessages ?? FirebaseMessaging.onMessageOpenedApp,
       _networkChanges =
           networkChanges ??
           Connectivity().onConnectivityChanged.map(
             (types) => types.any((type) => type != ConnectivityResult.none),
           ),
       _registerBackgroundHandler =
           registerBackgroundHandler ??
           (() => FirebaseMessaging.onBackgroundMessage(
             firebaseMessagingBackgroundHandler,
           )) {
    _observedUid = _auth.currentUser?.uid;
  }

  static final NotificationService instance = NotificationService();

  final FirebaseAuth _auth;
  final FirebaseMessaging _messaging;
  final FlutterLocalNotificationsPlugin _localNotifications;
  final http.Client _client;
  final Stream<RemoteMessage> _messages, _openedMessages;
  final Stream<bool> _networkChanges;
  final void Function() _registerBackgroundHandler;
  final _subscriptions = <StreamSubscription<dynamic>>[];
  SyncLifecycleCoordinator? _recovery;
  Future<void>? _tokenSync;
  bool _needsRotation = false;
  static const _deviceOwnerKey = 'notification_device_owner';
  final _store = LocalOperationalStore.instance;
  bool _localReady = false;
  bool _loggingOut = false;
  String? _departingUid;
  bool _syncAgain = false;
  Future<void>? _localInitialization;
  int _revision = 0;
  String? _observedUid;
  Future<void>? _initialization;
  final _deliveryGuard = NotificationDeliveryGuard();

  Future<void> initialize() {
    return _initialization ??= _initialize();
  }

  Future<void> _initialize() async {
    // Reception must not depend on Play Services, permissions or an API request
    // succeeding during startup. Install every listener before those awaits.
    _registerBackgroundHandler();
    _subscriptions.add(
      _messages.listen((message) {
        unawaited(
          _attempt(
            'Ricezione notifica',
            () => _handleForegroundMessage(message),
          ),
        );
      }),
    );
    _subscriptions.add(
      _openedMessages.listen((message) {
        unawaited(
          _attempt(
            'Apertura notifica',
            () => _handleNotificationOpened(message),
          ),
        );
      }),
    );
    _subscriptions.add(
      _auth.idTokenChanges().listen((_) {
        final uid = _auth.currentUser?.uid;
        if (uid != _observedUid) {
          final previousUid = _observedUid;
          _observedUid = uid;
          _revision++;
          // A session may be replaced without going through the logout button.
          // Rotate the installation token before associating the next account.
          if (previousUid != null && !_loggingOut) {
            AppNavigation.clearRequests();
            _needsRotation = true;
          }
        }
        if (_loggingOut && _auth.currentUser?.uid != _departingUid) {
          _loggingOut = false;
          _departingUid = null;
        }
        unawaited(syncTokenWithBackend());
      }),
    );
    _subscriptions.add(
      _messaging.onTokenRefresh.listen((_) {
        unawaited(syncTokenWithBackend());
      }),
    );
    _recovery = SyncLifecycleCoordinator(
      networkChanges: _networkChanges,
      retry: (_) async {
        AppNavigation.refreshNotifications();
        AppNavigation.refreshTasks();
        await syncTokenWithBackend();
      },
    )..start(retryImmediately: false);

    // Cold-start navigation is independent of token registration too.
    await _attempt('Notifica iniziale', () async {
      final message = await _messaging.getInitialMessage().timeout(
        const Duration(seconds: 10),
      );
      if (message != null) await _handleNotificationOpened(message);
    });
    await _attempt('Canale notifiche', _ensureLocalNotifications);
    await _attempt('Notifica locale iniziale', _openLocalLaunch);
    await _attempt('Permesso notifiche', _requestPermission);
    await syncTokenWithBackend();
  }

  Future<void> _attempt(
    String operation,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (error) {
      // Never log payloads, tokens or server response bodies.
      debugPrint('$operation non riuscita: ${error.runtimeType}');
    }
  }

  Future<void> _ensureLocalNotifications() async {
    if (_localReady) return;
    final future = _localInitialization ??= _initializeLocalNotifications();
    try {
      await future;
      _localReady = true;
    } finally {
      if (identical(_localInitialization, future)) _localInitialization = null;
    }
  }

  /// Ri-registra il token FCM sul backend (es. dopo l'approvazione dell'account,
  /// quando prima il backend rispondeva 403).
  Future<void> syncTokenWithBackend() {
    if (_loggingOut) return Future.value();
    // Queue one further attempt when identity/token changes during a request.
    final running = _tokenSync;
    if (running != null) {
      _syncAgain = true;
      return running;
    }
    final future = _attempt('Sync token FCM', () async {
      final revision = _revision;
      final user = _auth.currentUser;
      if (user == null) return;
      final owner = await _store.read(_deviceOwnerKey);
      if (owner != null && owner != user.uid) _needsRotation = true;
      if (_needsRotation) await _clearInstallation();
      final token = await _messaging.getToken().timeout(
        const Duration(seconds: 20),
      );
      if (token != null && _isCurrent(user, revision)) {
        await _registerTokenWithBackend(token, user, revision);
      }
    });
    _tokenSync = future;
    return future.whenComplete(() {
      if (identical(_tokenSync, future)) _tokenSync = null;
      if (_syncAgain) {
        _syncAgain = false;
        unawaited(syncTokenWithBackend());
      }
    });
  }

  bool _isCurrent(User user, int revision) =>
      !_loggingOut &&
      !_needsRotation &&
      _revision == revision &&
      _auth.currentUser?.uid == user.uid;

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

  Future<void> _openLocalLaunch() async {
    final launch = await _localNotifications.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp != true) return;
    final payload = jsonDecode(launch?.notificationResponse?.payload ?? '{}');
    if (payload is Map<String, dynamic>) await _openPayload(payload);
  }

  Future<void> _registerTokenWithBackend(
    String token,
    User user,
    int revision,
  ) async {
    final identity = await user.getIdTokenResult().timeout(
      const Duration(seconds: 20),
    );
    if (!_isCurrent(user, revision) ||
        !SessionService.isAppRole(identity.claims?['role']) ||
        (identity.claims?['tenantId']?.toString().trim() ?? '').isEmpty) {
      return;
    }
    final idToken = identity.token;
    if (idToken == null || idToken.isEmpty) return;
    // Approved accounts already have an operator profile. Registering it on
    // every sync adds an unnecessary failure point before the FCM endpoint.
    final response = await _client
        .post(
          Uri.parse('${ApiService.baseUrl}/api/v1/operator/me/fcm-token'),
          headers: {
            'Authorization': 'Bearer $idToken',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'fcmToken': token}),
        )
        .timeout(const Duration(seconds: 20));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      debugPrint(
        'Registrazione token FCM rifiutata: HTTP ${response.statusCode}',
      );
      return;
    }

    debugPrint('FCM token registrato sul backend.');
    await _store.write(_deviceOwnerKey, user.uid);
  }

  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    await _acceptPayload(
      message.data,
      'show',
      onAccept: () => _showForegroundMessage(message),
    );
  }

  Future<void> _showForegroundMessage(RemoteMessage message) async {
    final user = _auth.currentUser;
    final revision = _revision;
    if (message.data['type'] == 'BADGE_UPDATED') {
      try {
        await PersonalBadgeCache.refresh();
      } catch (_) {
        /* Resume and profile polling will retry. */
      }
      return;
    }
    AppNavigation.refreshNotifications();
    if (message.data['taskId'] != null) AppNavigation.refreshTasks();
    debugPrint('Notifica operativa ricevuta in foreground.');
    final notification = message.notification;
    if (notification != null ||
        message.data['title'] != null ||
        message.data['message'] != null) {
      await _ensureLocalNotifications();
      if (user == null || !_isCurrent(user, revision)) {
        throw StateError('Identità cambiata.');
      }
      await _localNotifications.show(
        id: notificationDisplayId(message.data['notificationId'] as String),
        title:
            notification?.title ??
            message.data['title']?.toString() ??
            ProductBrand.appName,
        body:
            notification?.body ??
            message.data['message']?.toString() ??
            'Nuova comunicazione operativa',
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

  Future<bool> _acceptPayload(
    Map<String, dynamic> data,
    String channel, {
    Future<void> Function()? onAccept,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return false;
      final revision = _revision;
      final claims = await user.getIdTokenResult();
      final tenant = claims.claims?['tenantId']?.toString() ?? '';
      if (!_isCurrent(user, revision) ||
          !SessionService.isAppRole(claims.claims?['role'])) {
        return false;
      }
      final accepted = await _deliveryGuard.accept(
        data,
        uid: user.uid,
        tenantId: tenant,
        channel: channel,
        onAccept: () async {
          if (!_isCurrent(user, revision)) {
            throw StateError('Identità cambiata.');
          }
          await onAccept?.call();
        },
      );
      return accepted && _isCurrent(user, revision);
    } catch (_) {
      return false;
    }
  }

  Future<void> _openPayload(Map<String, dynamic> data) async {
    await _acceptPayload(
      data,
      'open',
      onAccept: () async {
        final taskId = data['taskId']?.toString().trim() ?? '';
        if (taskId.isNotEmpty) {
          AppNavigation.openTask(taskId);
        } else {
          AppNavigation.openNotification(data['notificationId'] as String);
        }
      },
    );
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
    _loggingOut = true;
    _departingUid = _auth.currentUser?.uid;
    _revision++;
    await _tokenSync;
    // Remove the relationship while the departing user's ID token is valid.
    // Local token deletion still runs if the backend is unavailable.
    try {
      final token = await _messaging.getToken();
      if (token != null && _auth.currentUser != null) {
        final idToken = await _auth.currentUser!.getIdToken();
        await _client
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
    _needsRotation = true;
    await _attempt('Pulizia dispositivo', _clearInstallation);
    try {
      await PersonalBadgeCache.clearOwn();
    } catch (_) {
      /* Complete logout. */
    }
    AppNavigation.clearRequests();
  }

  Future<void> _clearInstallation() async {
    final revision = _revision;
    // A failed rotation keeps the next account unassociated. Resume/network
    // recovery must rotate successfully before registering or accepting push.
    await _localNotifications.cancelAll();
    await _messaging.deleteToken().timeout(const Duration(seconds: 10));
    await _store.delete(_deviceOwnerKey);
    if (revision == _revision) _needsRotation = false;
  }

  @visibleForTesting
  Future<void> dispose() async {
    await _recovery?.dispose();
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
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
