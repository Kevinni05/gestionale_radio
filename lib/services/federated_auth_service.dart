import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class FederatedAuthService {
  static Future<UserCredential> login(String provider) async {
    if (provider == 'microsoft') {
      return FirebaseAuth.instance.signInWithProvider(MicrosoftAuthProvider());
    }
    final google = GoogleSignIn.instance;
    await google.initialize(
      serverClientId:
          const String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID').isEmpty
          ? null
          : const String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID'),
    );
    final account = await google.authenticate();
    return FirebaseAuth.instance.signInWithCredential(
      GoogleAuthProvider.credential(idToken: account.authentication.idToken),
    );
  }
}
