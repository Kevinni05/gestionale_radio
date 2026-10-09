import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../services/android_update_service.dart';

class AndroidUpdateButton extends StatefulWidget {
  const AndroidUpdateButton({super.key});
  @override
  State<AndroidUpdateButton> createState() => _AndroidUpdateButtonState();
}

class _AndroidUpdateButtonState extends State<AndroidUpdateButton> {
  bool _busy = false;
  Future<void> _check() async {
    setState(() => _busy = true);
    try {
      final result = await AndroidUpdateService().check();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Aggiornamenti RadioTech'),
          content: Text(result.message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Chiudi'),
            ),
            if (result.url != null)
              FilledButton(
                onPressed: () async {
                  Navigator.pop(context);
                  try {
                    await AndroidUpdateService.openDownload(result.url!);
                  } catch (_) {
                    if (mounted) {
                      ScaffoldMessenger.of(this.context).showSnackBar(
                        const SnackBar(
                          content: Text('Impossibile aprire il download.'),
                        ),
                      );
                    }
                  }
                },
                child: const Text('Apri download'),
              ),
          ],
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Verifica aggiornamenti non disponibile. Riprova.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) =>
      kIsWeb || defaultTargetPlatform != TargetPlatform.android
      ? const SizedBox.shrink()
      : TextButton.icon(
          onPressed: _busy ? null : _check,
          icon: const Icon(Icons.system_update_outlined),
          label: Text(_busy ? 'Verifica aggiornamenti…' : 'Aggiornamenti app'),
        );
}
