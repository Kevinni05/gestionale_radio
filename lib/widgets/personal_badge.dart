import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/company_api.dart';
import '../services/personal_badge_cache.dart';
import '../ai_hub_screen.dart' show CompanyRequest;

/// Polling plus document invalidation keeps the badge current while connected;
/// resume always refreshes after Android suspends background execution.
class PersonalBadge extends StatefulWidget {
  final String? operatorId;
  const PersonalBadge({this.operatorId, this.request, super.key});
  final CompanyRequest? request;
  @override
  State<PersonalBadge> createState() => _PersonalBadgeState();
}

class _PersonalBadgeState extends State<PersonalBadge>
    with WidgetsBindingObserver {
  CompanyRequest get _request => widget.request ?? CompanyApi.instance.request;
  Timer? _timer;
  StreamSubscription<dynamic>? _changes;
  Map<String, dynamic>? _badge;
  String? _error;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    PersonalBadgeCache.revision.addListener(_onRevision);
    unawaited(_refresh());
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _refresh());
    if (widget.operatorId != null) {
      _changes = FirebaseFirestore.instance
          .collection('operators')
          .doc(widget.operatorId)
          .snapshots()
          .listen((_) => _refresh(), onError: (Object _) {});
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    PersonalBadgeCache.revision.removeListener(_onRevision);
    _timer?.cancel();
    _changes?.cancel();
    super.dispose();
  }

  void _onRevision() {
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    if (_busy || !mounted) return;
    _busy = true;
    try {
      final result = await _request('/operator/me/badge');
      if (mounted) {
        setState(() {
          _badge = Map<String, dynamic>.from(result as Map);
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _badge = null;
          _error =
              'Badge non disponibile. Verifica la connessione e la validità configurata.';
        });
      }
    } finally {
      _busy = false;
    }
  }

  Uint8List get _png =>
      base64Decode((_badge!['imageDataUrl'] as String).split(',').last);
  Future<void> _save() async {
    try {
      await Gal.putImageBytes(_png, name: 'RadioTech-badge');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'QR salvato nella galleria. Conserva il badge come una credenziale personale.',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Salvataggio non riuscito. Consenti l’accesso alla galleria e riprova.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _reset() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await _request(
        '/operator/me/reset-password',
        method: 'POST',
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('${result['message']}')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Reimpostazione non riuscita. Verifica il servizio email con il responsabile.',
            ),
          ),
        );
      }
    } finally {
      _busy = false;
      if (mounted) {
        setState(() {});
        await _refresh();
      }
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      if (_error != null)
        Text(_error!)
      else if (_badge == null)
        const CircularProgressIndicator()
      else ...[
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Image.memory(
            _png,
            width: 220,
            height: 220,
            gaplessPlayback: true,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          _badge!['expiresAt'] == null
              ? 'Validità senza scadenza · accesso singolo'
              : 'Valido fino al ${DateTime.tryParse(_badge!['expiresAt'].toString())?.toLocal() ?? _badge!['expiresAt']} · accesso singolo',
        ),
        const SizedBox(height: 8),
        const Text(
          'Si aggiorna automaticamente quando il badge cambia. Un QR già scaricato non si aggiorna: salva la nuova versione.',
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.download),
          label: const Text('Salva QR sul dispositivo'),
        ),
      ],
      Wrap(
        alignment: WrapAlignment.center,
        spacing: 12,
        children: [
          TextButton.icon(
            onPressed: _busy ? null : _refresh,
            icon: const Icon(Icons.refresh),
            label: const Text('Aggiorna badge'),
          ),
          TextButton.icon(
            onPressed: _busy ? null : _reset,
            icon: const Icon(Icons.lock_reset),
            label: const Text('Reimposta password'),
          ),
        ],
      ),
    ],
  );
}
