import 'package:flutter/material.dart';
import 'services/api_service.dart';
import 'services/api_endpoint.dart';
import 'services/api_http_client.dart';
import 'services/backend_health.dart';
import 'services/app_navigation.dart';
import 'theme/radiotech_glass.dart';

/// Test builds can change endpoint without signing out or deleting drafts.
class BackendSettingsScreen extends StatefulWidget {
  const BackendSettingsScreen({super.key});
  @override
  State<BackendSettingsScreen> createState() => _BackendSettingsScreenState();
}

class _BackendSettingsScreenState extends State<BackendSettingsScreen> {
  final _url = TextEditingController(text: ApiService.baseUrl);
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final endpoint = ApiEndpoint.normalize(_url.text);
      final response = await ApiHttpClient.instance
          .get(Uri.parse('$endpoint/api/v1/health'))
          .timeout(const Duration(seconds: 15));
      if (!mounted) return;

      if (!BackendHealth.isHealthyRadioTech(
        statusCode: response.statusCode,
        body: response.body,
      )) {
        throw StateError(
          'Il link non identifica un backend RadioTech disponibile.',
        );
      }
      ApiService.baseUrl = endpoint;
      AppNavigation.refreshTasks();
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Server non raggiungibile. Inserisci il link HTTPS attuale, senza /api o altri percorsi.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Connessione al server')),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(20),
            children: [
              RadioTechGlass(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.dns_outlined, size: 32),
                    const SizedBox(height: 16),
                    Text(
                      'Collega il tuo spazio di lavoro',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Usa il link HTTPS fornito dal responsabile. I link Cloudflare di test cambiano quando il tunnel viene riavviato.',
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _url,
                      enabled: !_busy,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Indirizzo del server',
                        hintText: 'https://…trycloudflare.com',
                        prefixIcon: Icon(Icons.link),
                      ),
                    ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: _busy ? null : _save,
                      icon: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check),
                      label: Text(
                        _busy ? 'Verifica in corso…' : 'Verifica e salva',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
