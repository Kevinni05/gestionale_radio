import 'package:flutter/material.dart';

import 'services/auth_service.dart';
import 'services/session_service.dart';

/// Mostrata quando l'account e' valido ma non ancora abilitato all'app operatori.
class PendingApprovalScreen extends StatelessWidget {
  const PendingApprovalScreen({
    super.key,
    required this.state,
    required this.onRecheck,
    this.checking = false,
  });

  final AccessState state;
  final VoidCallback onRecheck;
  final bool checking;

  @override
  Widget build(BuildContext context) {
    final isError = state == AccessState.error;
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isError
                      ? Icons.wifi_off_rounded
                      : Icons.hourglass_top_rounded,
                  size: 64,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 24),
                Text(
                  isError ? 'VERIFICA NON RIUSCITA' : 'ACCOUNT IN ATTESA',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  isError
                      ? 'Non riesco a verificare i tuoi permessi. '
                            'Controlla la connessione e riprova.'
                      : 'Il tuo account è stato creato ma non è ancora '
                            'abilitato. Un responsabile deve approvarlo: '
                            'appena fatto, tocca "Ricontrolla".',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[400], height: 1.5),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: checking ? null : onRecheck,
                    child: checking
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Ricontrolla'),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: checking ? null : AuthService.instance.signOut,
                  child: const Text('Esci'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
