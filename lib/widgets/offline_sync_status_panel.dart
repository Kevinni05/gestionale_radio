import 'dart:async';

import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/offline_sync_service.dart';
import '../services/auth_service.dart';
import '../services/session_service.dart';

class OfflineSyncStatusPanel extends StatefulWidget {
  const OfflineSyncStatusPanel({super.key, this.refreshToken = 0});

  final int refreshToken;

  @override
  State<OfflineSyncStatusPanel> createState() => _OfflineSyncStatusPanelState();
}

class _OfflineSyncStatusPanelState extends State<OfflineSyncStatusPanel> {
  final OfflineSyncService _service = OfflineSyncService.instance;
  List<QueuedSyncAction> _actions = [];
  bool _queueCorrupted = false;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _refresh();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _refresh(),
    );
  }

  @override
  void didUpdateWidget(covariant OfflineSyncStatusPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) {
      _refresh();
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    List<QueuedSyncAction> actions;
    try {
      actions = await _service.pending();
      final uid = AuthService.instance.currentUid;
      if (uid != null) {
        actions = actions
            .where(
              (action) =>
                  action.payload['actorUid'] == uid &&
                  action.payload['tenantId'] ==
                      SessionService.instance.tenantId,
            )
            .toList();
      }
    } on StateError {
      if (!mounted) return;
      setState(() {
        _actions = [];
        _queueCorrupted = true;
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      _actions = actions;
      _queueCorrupted = _service.queueCorrupted;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_queueCorrupted) {
      return const Padding(
        padding: EdgeInsets.only(top: 14),
        child: Material(
          color: Color(0x33FF9800),
          child: Padding(
            padding: EdgeInsets.all(14),
            child: Text(
              'La coda offline è danneggiata. I dati sono stati conservati; serve assistenza per il recupero.',
              style: TextStyle(color: Colors.orangeAccent),
            ),
          ),
        ),
      );
    }
    if (_actions.isEmpty) return const SizedBox.shrink();

    final failedCount = _actions.where((action) => action.failed).length;
    final waitingCount = _actions.length - failedCount;
    final accent = failedCount > 0 ? Colors.orangeAccent : Colors.cyanAccent;

    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Material(
        color: Colors.white.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: _showQueue,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: accent.withValues(alpha: 0.35)),
            ),
            child: Row(
              children: [
                Icon(Icons.cloud_sync_outlined, color: accent, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '$waitingCount in attesa · $failedCount da risolvere',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.white70),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showQueue() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sincronizzazione'),
        content: SizedBox(
          width: double.maxFinite,
          height: 280,
          child: ListView.separated(
            itemCount: _actions.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final action = _actions[index];
              final detail = action.failed
                  ? action.lastError ?? 'Azione da verificare.'
                  : action.nextAttemptAt == null
                  ? 'In attesa di connessione.'
                  : 'Prossimo tentativo: ${action.nextAttemptAt!.toLocal()}';
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(_actionLabel(action.action)),
                subtitle: Text(
                  '${action.failed ? 'Da risolvere' : 'In attesa'} · ${action.retryCount} tentativi\n$detail',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                isThreeLine: true,
                trailing: action.failed
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Riprova',
                            onPressed: () async {
                              Navigator.of(dialogContext).pop();
                              await _service.retryFailed(action.id);
                              await _refresh();
                            },
                            icon: const Icon(Icons.refresh),
                          ),
                          IconButton(
                            tooltip: 'Rimuovi operazione fallita',
                            onPressed: () =>
                                _confirmDiscard(dialogContext, action),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      )
                    : null,
              );
            },
          ),
        ),
        actions: [
          if (_actions.any((action) => !action.failed))
            TextButton.icon(
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                await _service.retryPending(force: true);
                await _refresh();
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Sincronizzazione manuale completata.'),
                  ),
                );
              },
              icon: const Icon(Icons.sync),
              label: const Text('Sincronizza ora'),
            ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Chiudi'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDiscard(
    BuildContext dialogContext,
    QueuedSyncAction action,
  ) async {
    final confirmed = await showDialog<bool>(
      context: dialogContext,
      builder: (confirmationContext) => AlertDialog(
        title: const Text('Rimuovere l’operazione?'),
        content: const Text(
          'Il report e gli allegati locali in coda verranno eliminati. Non potrai ripristinarli.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(confirmationContext).pop(false),
            child: const Text('Annulla'),
          ),
          TextButton(
            onPressed: () => Navigator.of(confirmationContext).pop(true),
            child: const Text('Rimuovi'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await ApiService.instance.discardFailedSyncAction(action.id);
    await _refresh();
    if (dialogContext.mounted) Navigator.of(dialogContext).pop();
  }

  String _actionLabel(String action) => switch (action) {
    'maintenance_report' => 'Report manutenzione',
    'task_checkout' => 'Check-out GPS',
    'task_check_in' => 'Check-in GPS',
    'task_status_update' => 'Aggiornamento task',
    _ => 'Operazione offline',
  };
}
