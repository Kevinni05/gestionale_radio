import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'services/api_service.dart';
import 'services/session_service.dart';

class SecurityProScreen extends StatefulWidget {
  const SecurityProScreen({super.key});
  @override
  State<SecurityProScreen> createState() => _SecurityProScreenState();
}

class _SecurityProScreenState extends State<SecurityProScreen> {
  final _uid = TextEditingController(), _customer = TextEditingController();
  final _permissions = TextEditingController();
  String _role = 'CUSTOMER';
  bool _busy = false, _requireMfa = false;
  String _status = '';
  @override
  void dispose() {
    _uid.dispose();
    _customer.dispose();
    _permissions.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() operation) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = '';
    });
    try {
      await operation();
      if (mounted) setState(() => _status = 'Operazione completata.');
    } catch (e) {
      if (mounted) setState(() => _status = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _enroll() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Accesso richiesto.');
    final session = await user.multiFactor.getSession();
    final secret = await TotpMultiFactorGenerator.generateSecret(session);
    if (!mounted) return;
    final code = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Configura MFA'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Aggiungi questa chiave alla tua app di autenticazione. Non condividerla.',
              ),
              SelectableText(secret.secretKey),
              TextField(
                controller: code,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Codice a 6 cifre',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Conferma'),
          ),
        ],
      ),
    );
    final otp = code.text.trim();
    code.dispose();
    if (confirmed != true) return;
    final assertion = await TotpMultiFactorGenerator.getAssertionForEnrollment(
      secret,
      otp,
    );
    await user.multiFactor.enroll(assertion, displayName: 'RadioTech TOTP');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Sicurezza e accessi')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'SSO e MFA richiedono provider aziendale e Firebase Identity Platform configurati. Il test gratuito mantiene gli accessi attuali; nessun piano a pagamento viene attivato automaticamente.',
        ),
        FilledButton(
          onPressed: _busy ? null : () => _run(_enroll),
          child: const Text('Configura app di autenticazione (MFA)'),
        ),
        if (SessionService.instance.canManageAccounts) ...[
          const Divider(),
          const Text(
            'Assegna account esistente al cliente / ruolo. Gli accessi precedenti saranno revocati.',
          ),
          TextField(
            controller: _uid,
            decoration: const InputDecoration(
              labelText: 'UID Firebase account',
            ),
          ),
          DropdownButtonFormField<String>(
            initialValue: _role,
            decoration: const InputDecoration(labelText: 'Ruolo'),
            items: [
              'CUSTOMER',
              'OPERATOR',
              'VIEWER',
              'NETWORK_MANAGER',
            ].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
            onChanged: (v) => _role = v ?? 'CUSTOMER',
          ),
          TextField(
            controller: _customer,
            decoration: const InputDecoration(
              labelText: 'ID cliente (per account cliente)',
            ),
          ),
          SwitchListTile(
            value: _requireMfa,
            onChanged: (v) => setState(() => _requireMfa = v),
            title: const Text('Richiedi secondo fattore già configurato'),
          ),
          TextField(
            controller: _permissions,
            maxLength: 2000,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Permessi Enterprise Pro (facoltativo)',
              hintText: 'clients:READ, purchases:READ, purchases:APPROVE',
              helperText:
                  'Vuoto: permessi del ruolo. La lista limita le nuove sezioni Pro.',
              helperMaxLines: 3,
            ),
          ),
          FilledButton(
            onPressed: _busy
                ? null
                : () => _run(() async {
                    await ApiService.instance.proRequest(
                      'security/accounts/${Uri.encodeComponent(_uid.text.trim())}',
                      method: 'PUT',
                      body: {
                        'role': _role,
                        'customerId': _customer.text.trim(),
                        'mfaRequired': _requireMfa,
                        if (_permissions.text.trim().isNotEmpty)
                          'proPermissions': _permissions.text
                              .split(',')
                              .map((p) => p.trim())
                              .where((p) => p.isNotEmpty)
                              .toList(),
                      },
                    );
                  }),
            child: const Text('Assegna accesso'),
          ),
          OutlinedButton(
            onPressed: _busy
                ? null
                : () => _run(() async {
                    await ApiService.instance.proRequest(
                      'security/accounts/${Uri.encodeComponent(_uid.text.trim())}/revoke',
                      method: 'POST',
                    );
                  }),
            child: const Text('Revoca tutte le sessioni di questo account'),
          ),
        ],
        Text(_status),
      ],
    ),
  );
}
