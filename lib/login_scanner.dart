import 'services/api_http_client.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'services/api_service.dart';
import 'services/qr_login_service.dart';

class LoginScannerScreen extends StatefulWidget {
  const LoginScannerScreen({super.key});

  @override
  State<LoginScannerScreen> createState() => _LoginScannerScreenState();
}

class _LoginScannerScreenState extends State<LoginScannerScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _glowAnimation;
  late final Animation<double> _buttonScale;

  final MobileScannerController _scannerController = MobileScannerController(
    facing: CameraFacing.back,
  );

  bool _isProcessing = false;

  String _statusMessage = 'Inquadra il QR personale dell’operatore.';

  String? _errorMessage;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);

    _glowAnimation = Tween<double>(
      begin: 0.1,
      end: 0.8,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    _buttonScale = Tween<double>(
      begin: 0.98,
      end: 1.02,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _scannerController.dispose();
    _controller.dispose();
    super.dispose();
  }

  // ============================================================
  // QR
  // ============================================================

  Future<void> _handleBarcode(BarcodeCapture capture) async {
    if (_isProcessing) return;

    if (capture.barcodes.isEmpty) return;

    final barcode = capture.barcodes.first;

    final rawValue = barcode.rawValue?.trim();

    if (rawValue == null || rawValue.isEmpty) {
      return;
    }

    setState(() {
      _isProcessing = true;
      _errorMessage = null;
      _statusMessage = 'Verifica credenziali operatore...';
    });

    await _scannerController.stop();
    if (!mounted) return;

    await _authenticateFromQr(rawValue);
  }

  Future<void> _authenticateFromQr(String rawValue) async {
    try {
      final server = QrLoginService.readServerUrl(rawValue);
      if (server != null && server != ApiService.baseUrl) {
        if (kReleaseMode) {
          throw const QrLoginFailure(
            'Questo badge appartiene a una centrale diversa dalla versione aziendale installata.',
          );
        }
        final accepted = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Centrale del badge'),
            content: SingleChildScrollView(
              child: Text(
                'Il QR indica questa centrale:\n\n$server\n\nContinua solo se è il server della tua azienda.',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Annulla'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Usa questa centrale'),
              ),
            ],
          ),
        );
        if (accepted != true) {
          throw const QrLoginFailure('Cambio centrale annullato.');
        }
        ApiService.baseUrl = server;
      }
      if (!mounted) return;
      final customToken = await QrLoginService(
        client: ApiHttpClient.instance,
      ).exchange(rawValue, baseUrl: ApiService.baseUrl);
      if (!mounted) return;

      setState(() {
        _statusMessage = 'Operatore autorizzato. Accesso in corso...';
      });

      await FirebaseAuth.instance
          .signInWithCustomToken(customToken)
          .timeout(const Duration(seconds: 20));

      if (!mounted) return;

      setState(() {
        _statusMessage = 'Benvenuto! Accesso completato.';
      });

      await Future.delayed(const Duration(milliseconds: 350));
      if (!mounted) return;

      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (error) {
      if (!mounted) return;

      final connectionFailure = error is QrLoginFailure && error.connection;
      final msg = error is TimeoutException
          ? 'La verifica della sessione Firebase non risponde. Controlla Internet. '
                'Se il QR risulta già usato al nuovo tentativo, rigeneralo dalla centrale.'
          : error.toString().replaceFirst('Exception: ', '');
      setState(() {
        _errorMessage = msg;
        _statusMessage = connectionFailure
            ? 'Centrale non raggiungibile.'
            : 'Accesso non completato.';
      });

      // Retry only on explicit tap: a badge may be single use even if the
      // response was lost. Do not automatically exchange the same QR again.
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  // ============================================================
  // RESET
  // ============================================================

  Future<void> _resetScanner() async {
    if (_isProcessing) return;

    setState(() {
      _errorMessage = null;

      _statusMessage = 'Inquadra il QR personale dell’operatore.';
    });

    await _scannerController.start();
  }

  // ============================================================
  // UI
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF08090D),
      body: Stack(
        children: [
          _buildBackground(),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(),

                  const SizedBox(height: 22),

                  Expanded(child: _buildScanner()),

                  const SizedBox(height: 18),

                  _buildStatus(),

                  const SizedBox(height: 14),

                  _buildButton(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: const Color(0xFFE6E6E6).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: const Color(0xFFE6E6E6).withValues(alpha: 0.22),
            ),
          ),
          child: const Icon(
            Icons.radar_rounded,
            color: Color(0xFFE6E6E6),
            size: 25,
          ),
        ),

        const SizedBox(width: 14),

        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'RADIO TECH',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.8,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'Accesso operatori',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 12,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildScanner() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _scannerController,
            onDetect: _handleBarcode,
          ),

          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x33000000),
                  Colors.transparent,
                  Color(0x99000000),
                ],
              ),
            ),
          ),

          _buildScannerFrame(),

          Positioned(top: 16, right: 16, child: _buildTorchButton()),

          if (_isProcessing)
            Container(
              color: Colors.black.withValues(alpha: 0.55),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Color(0xFFE6E6E6)),
                    SizedBox(height: 14),
                    Text(
                      'Verifica in corso...',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildScannerFrame() {
    return Center(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Container(
            width: 260,
            height: 260,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
              border: Border.all(
                color: const Color(
                  0xFFE6E6E6,
                ).withValues(alpha: 0.35 + (_glowAnimation.value * 0.45)),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(
                    0xFFE6E6E6,
                  ).withValues(alpha: _glowAnimation.value * 0.16),
                  blurRadius: 30,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: Center(
              child: Icon(
                Icons.qr_code_2_rounded,
                color: Colors.white.withValues(alpha: 0.16),
                size: 80,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTorchButton() {
    return ValueListenableBuilder(
      valueListenable: _scannerController,
      builder: (context, value, child) {
        final torchOn = value.torchState == TorchState.on;

        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _scannerController.toggleTorch(),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF10111A).withValues(alpha: 0.82),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
              ),
              child: Icon(
                torchOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                color: const Color(0xFFE6E6E6),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatus() {
    final hasError = _errorMessage != null;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: hasError
            ? const Color(0xFFFF3B30).withValues(alpha: 0.08)
            : Colors.white.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: hasError
              ? const Color(0xFFFF3B30).withValues(alpha: 0.25)
              : Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: Row(
        children: [
          Icon(
            hasError
                ? Icons.error_outline_rounded
                : Icons.verified_user_rounded,
            color: hasError ? const Color(0xFFFF5A52) : const Color(0xFFE6E6E6),
            size: 22,
          ),

          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _statusMessage,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),

                if (_errorMessage != null) ...[
                  const SizedBox(height: 5),
                  Text(
                    _errorMessage!,
                    style: const TextStyle(
                      color: Color(0xFFFF6B63),
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildButton() {
    return ScaleTransition(
      scale: _buttonScale,
      child: SizedBox(
        height: 56,
        child: ElevatedButton.icon(
          onPressed: _isProcessing ? null : _resetScanner,
          icon: const Icon(Icons.qr_code_scanner_rounded),
          label: Text(
            _errorMessage != null ? 'RIPROVA' : 'SCANSIONA QR',
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFE6E6E6),
            foregroundColor: const Color(0xFF151518),
            disabledBackgroundColor: Colors.white.withValues(alpha: 0.08),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            elevation: 0,
          ),
        ),
      ),
    );
  }

  Widget _buildBackground() {
    return Stack(
      children: [
        Positioned.fill(
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF08090D), Color(0xFF191A24)],
              ),
            ),
          ),
        ),

        Positioned(
          top: -120,
          left: -100,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (_, _) {
              return Container(
                width: 320,
                height: 320,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(
                        0xFFE6E6E6,
                      ).withValues(alpha: _glowAnimation.value * 0.16),
                      Colors.transparent,
                    ],
                  ),
                ),
              );
            },
          ),
        ),

        Positioned(
          bottom: -100,
          right: -100,
          child: Container(
            width: 300,
            height: 300,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [Color(0x33005CFF), Colors.transparent],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
