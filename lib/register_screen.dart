import 'services/api_http_client.dart';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'login_scanner.dart';
import 'services/api_service.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _nameController = TextEditingController();

  final TextEditingController _emailController = TextEditingController();

  final TextEditingController _passwordController = TextEditingController();

  bool _isLoading = false;
  String? _registeredUid;

  /*
   * Android Emulator:
   * 10.0.2.2 = PC host
   *
   * Se usi un telefono fisico collegato alla stessa Wi-Fi,
   * dovrai mettere l'IP locale del PC, ad esempio:
   *
   * http://192.168.1.100:8080
   */
  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submitRegistration() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      /*
       * 1. Creazione account Firebase Authentication
       */
      final userCredential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
            email: _emailController.text.trim(),
            password: _passwordController.text.trim(),
          );

      final user = userCredential.user;

      if (user == null) {
        throw Exception('Impossibile creare account Firebase.');
      }

      final uid = user.uid;

      /*
       * 2. Creazione operatore tramite BACKEND
       *
       * NON scriviamo più direttamente nella collection
       * Firestore da Flutter.
       */
      final idToken = await user.getIdToken();
      final response = await ApiHttpClient.instance.post(
        Uri.parse('${ApiService.baseUrl}/api/v1/operator/register'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode({
          'fullName': _nameController.text.trim(),
          'email': _emailController.text.trim(),
          'level': 'TECNICO',
          'shift': 'GIORNALIERO',
          'firebaseUid': uid,
        }),
      );

      /*
       * 3. Controlliamo la risposta del backend
       */
      if (response.statusCode != 201) {
        /*
         * Se il backend fallisce, eliminiamo anche l'utente
         * Firebase appena creato per evitare account orfani.
         */
        try {
          await user.delete();
        } catch (_) {}

        String message = 'Errore nella creazione dell\'operatore.';

        try {
          final data = jsonDecode(response.body);

          if (data is Map && data['message'] != null) {
            message = data['message'].toString();
          }
        } catch (_) {}

        throw Exception(message);
      }

      /*
       * 4. Registrazione completata
       */
      if (!mounted) return;

      setState(() {
        _registeredUid = uid;
      });
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;

      String message = e.message ?? 'Errore di registrazione Firebase.';

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Errore: ${e.toString()}')));
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,

      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),

          child: _registeredUid == null
              ? Form(
                  key: _formKey,

                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,

                    children: [
                      const SizedBox(height: 20),

                      Text(
                        'Registrazione Operatore',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: 8),

                      Text(
                        'Inserisci i tuoi dati per creare l’account. Sarà abilitato dopo l’approvazione di un responsabile.',
                        style: TextStyle(color: Colors.grey[400], height: 1.4),
                      ),

                      const SizedBox(height: 32),

                      TextFormField(
                        controller: _nameController,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          labelText: 'Nome e Cognome',
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Inserisci il nome';
                          }

                          return null;
                        },
                      ),

                      const SizedBox(height: 16),

                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          labelText: 'Email aziendale',
                        ),
                        validator: (value) {
                          if (value == null || !value.contains('@')) {
                            return 'Inserisci un’email valida';
                          }

                          return null;
                        },
                      ),

                      const SizedBox(height: 16),

                      TextFormField(
                        controller: _passwordController,
                        obscureText: true,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          labelText: 'Password (min. 6 caratteri)',
                        ),
                        validator: (value) {
                          if (value == null || value.length < 6) {
                            return 'La password deve avere almeno 6 caratteri';
                          }

                          return null;
                        },
                      ),

                      const SizedBox(height: 36),

                      ElevatedButton(
                        onPressed: _isLoading ? null : _submitRegistration,

                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),

                        child: _isLoading
                            ? const CircularProgressIndicator(
                                color: Color(0xFF10111A),
                              )
                            : const Text(
                                'REGISTRATI E GENERA QR',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.2,
                                ),
                              ),
                      ),
                    ],
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,

                  children: [
                    const SizedBox(height: 20),

                    Text(
                      'Registrazione Completata!',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: theme.colorScheme.secondary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 12),

                    Text(
                      'Questo è il tuo QR code personale. Fai uno screenshot o salvalo sul telefono.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.grey[300],
                        height: 1.5,
                        fontSize: 13,
                      ),
                    ),

                    const SizedBox(height: 30),

                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(20),

                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                        ),

                        child: QrImageView(
                          data: 'uid=$_registeredUid',
                          version: QrVersions.auto,
                          size: 220,
                          backgroundColor: Colors.white,
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    SelectableText(
                      'UID: $_registeredUid',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey[500], fontSize: 11),
                    ),

                    const SizedBox(height: 40),

                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(
                            builder: (_) => const LoginScannerScreen(),
                          ),
                        );
                      },

                      icon: const Icon(Icons.check_circle_rounded),

                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),

                      label: const Text(
                        'HO SALVATO IL QR • PROCEDI AL LOGIN',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.1,
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
