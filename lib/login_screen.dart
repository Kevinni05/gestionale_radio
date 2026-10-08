import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'services/api_endpoint.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'theme/radiotech_glass.dart';
import 'package:http/http.dart' as http;

import 'login_scanner.dart';
import 'services/api_service.dart';
import 'services/federated_auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  static const routeName = '/login';

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  late final AnimationController _animationController;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;

  bool _isLoading = false;
  bool _testingBackend = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    );

    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _animationController,
            curve: Curves.easeOutCubic,
          ),
        );

    _animationController.forward();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _loginWithEmail() async {
    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      // NON facciamo Navigator.push(HomeScreen).
      //
      // AuthGate rileverà automaticamente l'utente autenticato
      // tramite authStateChanges() e mostrerà la HomeScreen.
    } on FirebaseAuthMultiFactorException catch (e) {
      await _completeMfa(e);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;

      setState(() {
        _errorMessage = _firebaseErrorMessage(e);
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _errorMessage =
            'Si è verificato un errore imprevisto. Riprova tra poco.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _completeMfa(FirebaseAuthMultiFactorException error) async {
    final factors = error.resolver.hints
        .where((f) => f.factorId == 'totp')
        .toList();
    if (factors.isEmpty) {
      if (mounted) {
        setState(
          () => _errorMessage =
              'Secondo fattore non supportato. Contatta il responsabile.',
        );
      }
      return;
    }
    if (!mounted) return;
    final code = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Verifica a due fattori'),
        content: TextField(
          controller: code,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Codice app di autenticazione',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Verifica'),
          ),
        ],
      ),
    );
    final otp = code.text.trim();
    code.dispose();
    if (confirmed != true) return;
    try {
      final assertion = await TotpMultiFactorGenerator.getAssertionForSignIn(
        factors.first.uid,
        otp,
      );
      await error.resolver.resolveSignIn(assertion);
    } catch (e) {
      if (mounted) setState(() => _errorMessage = e.toString());
    }
  }

  Future<void> _sso(String provider) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      await FederatedAuthService.login(provider);
    } on FirebaseAuthMultiFactorException catch (e) {
      await _completeMfa(e);
    } catch (e) {
      if (mounted) {
        setState(
          () => _errorMessage =
              'Accesso federato non riuscito. Verifica configurazione del provider. $e',
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _firebaseErrorMessage(FirebaseAuthException error) {
    switch (error.code) {
      case 'invalid-credential':
      case 'wrong-password':
      case 'user-not-found':
        return 'Email o password non corrette.';

      case 'invalid-email':
        return 'Inserisci un indirizzo email valido.';

      case 'user-disabled':
        return 'Questo account è stato disabilitato.';

      case 'too-many-requests':
        return 'Troppi tentativi. Riprova più tardi.';

      case 'network-request-failed':
        return 'Problema di connessione. Controlla la rete.';

      case 'operation-not-allowed':
        return 'Il login tramite email non è abilitato su Firebase.';

      default:
        return error.message ?? 'Impossibile effettuare il login.';
    }
  }

  Future<void> _openQrLogin() async {
    FocusScope.of(context).unfocus();

    await Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, animation, secondaryAnimation) {
          return const LoginScannerScreen();
        },
        transitionsBuilder: (_, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 350),
      ),
    );
  }

  Future<void> _resetPassword() async {
    final email = _emailController.text.trim();

    if (email.isEmpty) {
      setState(() {
        _errorMessage =
            'Inserisci prima il tuo indirizzo email per recuperare la password.';
      });
      return;
    }

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Email per il recupero della password inviata.'),
        ),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;

      setState(() {
        _errorMessage = _firebaseErrorMessage(e);
      });
    }
  }

  void _showServerConfigDialog() {
    final controller = TextEditingController(text: ApiService.baseUrl);
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          scrollable: true,
          backgroundColor: const Color(0xFF191A24),
          title: const Row(
            children: [
              Icon(Icons.dns, color: Color(0xFFE6E6E6)),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Server Backend API',
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Inserisci l’indirizzo HTTPS della tua centrale per accedere anche da rete mobile o da un’altra Wi-Fi. Per i soli test locali puoi usare l’IP del PC nella stessa rete. localhost e 127.0.0.1 indicano il telefono stesso.',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: const Color(0xFF10111A),
                  hintText: 'http://10.0.2.2:8080',
                  hintStyle: TextStyle(
                    color: Colors.white.withValues(alpha: 0.3),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  ActionChip(
                    label: const Text('Emulatore (10.0.2.2)'),
                    onPressed: () => controller.text = 'http://10.0.2.2:8080',
                  ),
                  ActionChip(
                    label: const Text('Telefono: IP del PC'),
                    onPressed: () =>
                        controller.text = 'http://192.168.1.20:8080',
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _testingBackend
                    ? null
                    : () async {
                        final messenger = ScaffoldMessenger.of(context);
                        setDialogState(() => _testingBackend = true);
                        try {
                          final base = ApiEndpoint.normalize(controller.text);
                          final response = await http
                              .get(Uri.parse('$base/api/v1/health'))
                              .timeout(const Duration(seconds: 6));
                          if (response.statusCode < 200 ||
                              response.statusCode >= 300) {
                            throw Exception(
                              'Il server ha risposto HTTP ${response.statusCode}.',
                            );
                          }
                          final health = jsonDecode(response.body);
                          if (health is! Map ||
                              health['service'] != 'radiotech-backend' ||
                              health['status'] != 'UP') {
                            throw const FormatException(
                              'L’indirizzo non corrisponde a una centrale RadioTech attiva.',
                            );
                          }
                          if (!messenger.mounted) return;
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text('Backend raggiungibile: $base'),
                            ),
                          );
                        } catch (error) {
                          if (!messenger.mounted) return;
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text(
                                'Backend non raggiungibile: $error',
                              ),
                            ),
                          );
                        } finally {
                          if (ctx.mounted) {
                            setDialogState(() => _testingBackend = false);
                          }
                        }
                      },
                icon: _testingBackend
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.wifi_tethering_rounded),
                label: Text(
                  _testingBackend
                      ? 'Verifica connessione...'
                      : 'Prova connessione al backend',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text(
                'Annulla',
                style: TextStyle(color: Colors.white60),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE6E6E6),
              ),
              onPressed: () {
                try {
                  ApiService.baseUrl = controller.text.trim();
                } on FormatException catch (error) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(error.message)));
                  return;
                }
                Navigator.pop(ctx);
                setState(() {});
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Endpoint backend impostato su: ${ApiService.baseUrl}',
                    ),
                  ),
                );
              },
              child: const Text(
                'Salva',
                style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          _buildBackground(theme),

          SafeArea(
            child: Stack(
              children: [
                Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 32,
                    ),
                    child: FadeTransition(
                      opacity: _fadeAnimation,
                      child: SlideTransition(
                        position: _slideAnimation,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 480),
                          child: Column(
                            children: [
                              _buildBrand(theme),

                              const SizedBox(height: 36),

                              _buildLoginCard(theme),

                              const SizedBox(height: 24),

                              _buildSecurityInfo(theme),

                              const SizedBox(height: 24),

                              Text(
                                '© 2026 Kevin Cagnazzo e Anthony Piccinonno.\nTutti i diritti riservati.',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.35),
                                  fontSize: 11,
                                  letterSpacing: 0.8,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBrand(ThemeData theme) {
    return Column(
      children: [
        Container(
          width: 82,
          height: 82,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0x55452324), Color(0xFF191A24)],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFE6E6E6).withValues(alpha: 0.28),
                blurRadius: 35,
                spreadRadius: 4,
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Image.asset(
              'assets/brand/radiotech-symbol-v1.png',
              semanticLabel: 'Logo RadioTech',
            ),
          ),
        ),

        const SizedBox(height: 20),

        const Text(
          'RADIOTECH',
          style: TextStyle(
            color: Colors.white,
            fontSize: 23,
            fontWeight: FontWeight.w900,
            letterSpacing: 3,
          ),
          textAlign: TextAlign.center,
        ),

        const SizedBox(height: 8),

        Text(
          'PIATTAFORMA OPERATIVA',
          style: TextStyle(
            color: theme.colorScheme.primary,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 2.5,
          ),
        ),
      ],
    );
  }

  Widget _buildLoginCard(ThemeData theme) {
    return RadioTechGlass(
      padding: const EdgeInsets.all(24),
      radius: 20,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Accesso operatore',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),

            const SizedBox(height: 8),

            Text(
              'Accedi con le credenziali aziendali oppure utilizza il tuo QR personale.',
              style: TextStyle(
                color: Colors.grey[400],
                height: 1.5,
                fontSize: 13,
              ),
            ),

            const SizedBox(height: 26),

            _buildLabel('EMAIL'),

            const SizedBox(height: 8),

            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const [
                AutofillHints.username,
                AutofillHints.email,
              ],
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: 'operatore@azienda.it',
                prefixIcon: Icon(Icons.email_outlined),
              ),
              validator: (value) {
                final email = value?.trim() ?? '';

                if (email.isEmpty) {
                  return 'Inserisci la tua email';
                }

                if (!email.contains('@')) {
                  return 'Inserisci un\'email valida';
                }

                return null;
              },
            ),

            const SizedBox(height: 18),

            _buildLabel('PASSWORD'),

            const SizedBox(height: 8),

            TextFormField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.password],
              onFieldSubmitted: (_) => _loginWithEmail(),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Inserisci la password',
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: IconButton(
                  tooltip: _obscurePassword
                      ? 'Mostra password'
                      : 'Nascondi password',
                  onPressed: () {
                    setState(() {
                      _obscurePassword = !_obscurePassword;
                    });
                  },
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Inserisci la password';
                }

                return null;
              },
            ),

            const SizedBox(height: 12),

            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _isLoading ? null : _resetPassword,
                child: const Text('Password dimenticata?'),
              ),
            ),

            if (_errorMessage != null) ...[
              const SizedBox(height: 8),
              _buildErrorBox(),
            ],

            const SizedBox(height: 20),

            SizedBox(
              height: 56,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _loginWithEmail,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE6E6E6),
                  foregroundColor: const Color(0xFF151518),
                  disabledBackgroundColor: Colors.white.withValues(alpha: 0.12),
                  disabledForegroundColor: Colors.white38,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 23,
                        height: 23,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Color(0xFF151518),
                        ),
                      )
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.login_rounded, size: 21),
                          SizedBox(width: 10),
                          Text(
                            'ACCEDI',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ],
                      ),
              ),
            ),

            const SizedBox(height: 24),

            Row(
              children: [
                Expanded(
                  child: Divider(color: Colors.white.withValues(alpha: 0.10)),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Text(
                    'OPPURE',
                    style: TextStyle(
                      color: Colors.grey[500],
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
                Expanded(
                  child: Divider(color: Colors.white.withValues(alpha: 0.10)),
                ),
              ],
            ),

            const SizedBox(height: 24),

            if (const bool.fromEnvironment('SSO_ENABLED')) ...[
              OutlinedButton(
                onPressed: _isLoading ? null : () => _sso('google'),
                child: const Text('Accedi con Google'),
              ),
              OutlinedButton(
                onPressed: _isLoading ? null : () => _sso('microsoft'),
                child: const Text('Accedi con Microsoft'),
              ),
            ],

            SizedBox(
              height: 56,
              child: OutlinedButton.icon(
                onPressed: _isLoading ? null : _openQrLogin,
                icon: const Icon(Icons.qr_code_scanner_rounded, size: 22),
                label: const Text(
                  'ACCEDI CON QR',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(
                    color: const Color(0xFFE6E6E6).withValues(alpha: 0.45),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
            if (!kReleaseMode) ...[
              const SizedBox(height: 16),
              TextButton.icon(
                key: const ValueKey('configure-backend'),
                onPressed: _isLoading ? null : _showServerConfigDialog,
                icon: const Icon(Icons.settings_rounded),
                label: const Text(
                  'Configura Server Backend',
                  textAlign: TextAlign.center,
                ),
              ),
              Text(
                'Centrale: ${ApiService.baseUrl}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: TextStyle(
        color: Colors.grey[500],
        fontSize: 10,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.4,
      ),
    );
  }

  Widget _buildErrorBox() {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFFF3B30).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFFFF3B30).withValues(alpha: 0.20),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: Color(0xFFFF6B6B),
            size: 19,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _errorMessage!,
              style: const TextStyle(
                color: Color(0xFFFF8A8A),
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSecurityInfo(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.verified_user_outlined,
            color: theme.colorScheme.secondary,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Accesso protetto tramite autenticazione Firebase.',
              style: TextStyle(
                color: Colors.grey[400],
                fontSize: 11,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackground(ThemeData theme) => const SizedBox.expand();
}
