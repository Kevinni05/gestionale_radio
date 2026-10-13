import 'widgets/radiotech_safe_area.dart';
import 'config/product_brand.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'theme/radiotech_theme.dart';
import 'theme/radiotech_backdrop.dart';
import 'services/app_navigation.dart';
import 'firebase_options.dart';
import 'login_screen.dart';
import 'home_screen.dart';
import 'pro_suite_screen.dart';
import 'pending_approval_screen.dart';
import 'services/session_service.dart';
import 'services/session_route_guard.dart';
import 'services/notification_route_handler.dart';
import 'services/operator_presence_service.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'services/notification_service.dart';
import 'services/api_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(const ProviderScope(child: _BootstrapApp()));
}

Future<void> _initializeApplication() async {
  if (kReleaseMode && const bool.fromEnvironment('APP_CHECK_DEBUG')) {
    throw StateError('App Check debug is forbidden in release builds.');
  }
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
    providerWeb: const bool.fromEnvironment('APP_CHECK_DEBUG')
        ? WebDebugProvider()
        : const String.fromEnvironment('APP_CHECK_WEB_SITE_KEY').isEmpty
        ? null
        : ReCaptchaV3Provider(
            const String.fromEnvironment('APP_CHECK_WEB_SITE_KEY'),
          ),
  );

  // Start API/offline synchronization only after Firebase and App Check are
  // ready, so queued work never races authentication/bootstrap state.
  await ApiService.initialize();

  unawaited(NotificationService.instance.initialize());
  OperatorPresenceService.instance.initialize();
}

class GestionaleRadioApp extends StatelessWidget {
  const GestionaleRadioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: ProductBrand.appName,
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      locale: const Locale('it'),
      supportedLocales: const [Locale('it'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,

      navigatorKey: AppNavigation.navigatorKey,
      theme: RadioTechTheme.dark,
      builder: (context, child) => RadioTechBackdrop(
        child: RadioTechSafeArea(child: child ?? const SizedBox.shrink()),
      ),

      home: SessionRouteGuard(
        identities: FirebaseAuth.instance.authStateChanges().map(
          (user) => user?.uid,
        ),
        initialIdentity: FirebaseAuth.instance.currentUser?.uid,
        child: const AuthGate(),
      ),
    );
  }
}

///
/// Decide automaticamente quale schermata mostrare.
///
/// NON usiamo più currentUser una sola volta durante il build.
/// Ascoltiamo FirebaseAuth in tempo reale.
///
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // Firebase sta controllando la sessione.
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _SplashScreen();
        }

        final user = snapshot.data;

        // Nessun utente autenticato.
        if (user == null) {
          return const LoginScreen();
        }

        // Utente autenticato: verifichiamo che sia abilitato all'app.
        return _AccessGate(key: ValueKey(user.uid));
      },
    );
  }
}

///
/// Dopo il login controlla il ruolo dell'utente. Gli account auto-registrati
/// restano "in attesa" finche' un manager non li approva.
///
class _AccessGate extends StatefulWidget {
  const _AccessGate({super.key});

  @override
  State<_AccessGate> createState() => _AccessGateState();
}

class _AccessGateState extends State<_AccessGate> {
  late Future<AccessState> _access = SessionService.instance.resolveAccess();
  bool _rechecking = false;
  AccessState _last = AccessState.pending;

  Future<void> _recheck() async {
    setState(() {
      _rechecking = true;
      _access = SessionService.instance.resolveAccess(forceRefresh: true);
    });
    try {
      await _access;
    } finally {
      if (mounted) setState(() => _rechecking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AccessState>(
      future: _access,
      builder: (context, snapshot) {
        final done = snapshot.connectionState == ConnectionState.done;

        if (!done && !_rechecking) {
          return const _SplashScreen();
        }

        // Durante "Ricontrolla" mostriamo lo stato precedente, senza lampeggiare l'errore.
        final state = done ? (snapshot.data ?? AccessState.error) : _last;
        if (done) _last = state;

        if (state == AccessState.approved) {
          return NotificationRouteHandler(
            child:
                SessionService.instance.isCustomer ||
                    SessionService.instance.managementOnly
                ? const ProSuiteScreen()
                : const HomeScreen(),
          );
        }

        return PendingApprovalScreen(
          state: state,
          checking: _rechecking,
          onRecheck: _recheck,
        );
      },
    );
  }
}

///
/// Splash iniziale professionale.
///
class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFF10111A),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ImageIcon(
              AssetImage(ProductBrand.logoAsset),
              size: 64,
              color: Color(0xFFE6E6E6),
            ),
            const SizedBox(height: 24),
            Text(
              ProductBrand.appName.toUpperCase(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: 3,
              ),
            ),
            const SizedBox(height: 24),
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFFE6E6E6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BootstrapApp extends StatefulWidget {
  const _BootstrapApp();
  @override
  State<_BootstrapApp> createState() => _BootstrapAppState();
}

class _BootstrapAppState extends State<_BootstrapApp> {
  late Future<void> _initialization = _initializeApplication();
  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
    future: _initialization,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.done &&
          !snapshot.hasError) {
        return const GestionaleRadioApp();
      }
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: RadioTechTheme.dark,
        home: snapshot.hasError
            ? Scaffold(
                body: SafeArea(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.cloud_off_outlined, size: 56),
                          const SizedBox(height: 20),
                          const Text(
                            'Avvio non riuscito',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Verifica la connessione. Se il problema persiste, contatta il responsabile del servizio.',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 24),
                          ElevatedButton(
                            onPressed: () => setState(() {
                              _initialization = _initializeApplication();
                            }),
                            child: const Text('Riprova'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              )
            : const _SplashScreen(),
      );
    },
  );
}
