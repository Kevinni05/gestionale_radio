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
    final (title, message, icon) = switch (state) {
      AccessState.pending => (
        'ACCOUNT IN ATTESA',
        'Un responsabile deve abilitare il tuo account. Ricontrolla dopo l’approvazione.',
        Icons.hourglass_top_rounded,
      ),
      AccessState.offline => (
        'RETE NON DISPONIBILE',
        'Torna online per verificare l’accesso. Le bozze sono conservate sul dispositivo.',
        Icons.wifi_off_rounded,
      ),
      AccessState.expired => (
        'SESSIONE SCADUTA',
        'Esci e accedi nuovamente con le credenziali o il QR di attivazione. Le bozze restano associate al tuo account.',
        Icons.lock_clock_outlined,
      ),
      AccessState.suspended => (
        'ACCESSO NON AUTORIZZATO',
        'L’account è sospeso o non ha più i permessi richiesti. Contatta il responsabile; le bozze sono conservate.',
        Icons.person_off_outlined,
      ),
      AccessState.deviceRevoked => (
        'DISPOSITIVO REVOCATO',
        'La centrale ha revocato questo dispositivo. Contatta il responsabile prima di attivarlo nuovamente.',
        Icons.phonelink_erase_outlined,
      ),
      _ => (
        'VERIFICA NON RIUSCITA',
        'Non riesco a verificare i tuoi permessi. Controlla la connessione e riprova.',
        Icons.cloud_off_outlined,
      ),
    };
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 64, color: theme.colorScheme.primary),
                const SizedBox(height: 24),
                Text(
                  title,
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
                  message,
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
