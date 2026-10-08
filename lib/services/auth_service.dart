import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'notification_service.dart';
import 'offline_task_pack_store.dart';

class AuthService {
  AuthService._();

  static final AuthService instance = AuthService._();

  FirebaseAuth? get _auth {
    if (Firebase.apps.isEmpty) {
      return null;
    }
    return FirebaseAuth.instance;
  }

  User? get currentUser => _auth?.currentUser;

  String? get currentUid => _auth?.currentUser?.uid;

  bool get isLoggedIn => _auth?.currentUser != null;

  Future<UserCredential> signInWithEmail({
    required String email,
    required String password,
  }) async {
    final auth = _auth;
    if (auth == null) {
      throw StateError(
        'Firebase non inizializzato: nessuna app Firebase attiva.',
      );
    }

    return await auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<UserCredential> createAccount({
    required String email,
    required String password,
  }) async {
    final auth = _auth;
    if (auth == null) {
      throw StateError(
        'Firebase non inizializzato: nessuna app Firebase attiva.',
      );
    }

    return await auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<String?> getIdToken() async {
    final user = _auth?.currentUser;

    if (user == null) {
      return null;
    }

    return await user.getIdToken();
  }

  Future<String?> refreshIdToken() async =>
      _auth?.currentUser?.getIdToken(true);
  Future<UserCredential> signInDeviceToken(String token) =>
      _auth!.signInWithCustomToken(token);

  Future<String> requireIdToken() async {
    final token = await getIdToken();

    if (token == null || token.isEmpty) {
      throw Exception('Utente Firebase non autenticato.');
    }

    return token;
  }

  Future<void> signOut() async {
    final auth = _auth;
    if (auth == null) {
      return;
    }
    await NotificationService.instance.clearDeviceToken();
    try {
      await OfflineTaskPackStore.clearOwn();
    } catch (_) {
      /* No approved operator session. */
    }
    await auth.signOut();
  }

  Stream<User?> authStateChanges() {
    final auth = _auth;
    if (auth == null) {
      return const Stream.empty();
    }
    return auth.authStateChanges();
  }
}
