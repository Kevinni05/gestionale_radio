import 'package:flutter/material.dart';
import 'services/api_service.dart';
import 'services/offline_task_pack_store.dart';
import 'report_closure_screen.dart';

class OfflinePacksScreen extends StatefulWidget {
  const OfflinePacksScreen({super.key});
  @override
  State<OfflinePacksScreen> createState() => _OfflinePacksScreenState();
}

class _OfflineChecklist extends StatefulWidget {
  const _OfflineChecklist({required this.pack});
  final Map<String, dynamic> pack;
  @override
  State<_OfflineChecklist> createState() => _OfflineChecklistState();
}

class _OfflineChecklistState extends State<_OfflineChecklist> {
  final _checks = <String, bool>{};
  @override
  void initState() {
    super.initState();
    final task = widget.pack['task'] as Map;
    final metadata = task['metadata'];
    final lines = metadata is Map
        ? (metadata['checklist']?.toString() ?? '')
        : '';
    for (final line
        in lines.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty)) {
      _checks[line] = false;
    }
    if (widget.pack['checklistResults'] is Map) {
      (widget.pack['checklistResults'] as Map).forEach((k, v) {
        if (_checks.containsKey(k)) _checks[k.toString()] = v == true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.pack['task'] as Map;
    return Scaffold(
      appBar: AppBar(title: const Text('Controlli senza connessione')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(task['title']?.toString() ?? ''),
          ..._checks.entries.map(
            (e) => CheckboxListTile(
              title: Text(e.key),
              value: e.value,
              onChanged: (v) async {
                setState(() => _checks[e.key] = v ?? false);
                widget.pack['checklistResults'] = Map<String, bool>.from(
                  _checks,
                );
                try {
                  await OfflineTaskPackStore.save(widget.pack);
                } catch (error) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text(error.toString())));
                  }
                }
              },
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ReportClosureScreen(
                  checklistResults: Map<String, bool>.from(_checks),
                  antennaId: task['antennaId']?.toString() ?? 'GENERICO',
                  taskId: task['id']?.toString(),
                ),
              ),
            ),
            child: const Text('Prepara report intervento'),
          ),
        ],
      ),
    );
  }
}

class _OfflinePacksScreenState extends State<OfflinePacksScreen> {
  final _taskId = TextEditingController();
  late Future<List<Map<String, dynamic>>> _packs;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _packs = OfflineTaskPackStore.list();
  }

  @override
  void dispose() {
    _taskId.dispose();
    super.dispose();
  }

  Future<void> _download() async {
    final id = _taskId.text.trim();
    if (!RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(id)) return;
    setState(() => _busy = true);
    try {
      final data = await ApiService.instance.proRequest('task-packs/$id');
      await OfflineTaskPackStore.save(Map<String, dynamic>.from(data as Map));
      if (mounted) setState(() => _packs = OfflineTaskPackStore.list());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Pacchetti offline')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Scarica prima dell’intervento. Copie protette sul dispositivo, valide 24 ore. Le azioni sugli incarichi richiedono la rete; i report usano la coda offline esistente.',
        ),
        TextField(
          controller: _taskId,
          decoration: const InputDecoration(labelText: 'ID incarico'),
        ),
        FilledButton(
          onPressed: _busy ? null : _download,
          child: Text(
            _busy ? 'Download…' : 'Scarica incarico, checklist e documenti',
          ),
        ),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _packs,
          builder: (context, snapshot) {
            if (snapshot.hasError) return Text(snapshot.error.toString());
            if (!snapshot.hasData) return const CircularProgressIndicator();
            if (snapshot.data!.isEmpty) {
              return const Text('Nessun pacchetto salvato.');
            }
            return Column(
              children: snapshot.data!.map((p) {
                final task = Map<String, dynamic>.from(p['task'] as Map);
                return Card(
                  child: ExpansionTile(
                    title: Text(task['title']?.toString() ?? 'Incarico'),
                    subtitle: Text('Valido fino a ${p['validUntil']}'),
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SelectableText(
                              task['description']?.toString() ?? '',
                            ),
                            if (task['metadata'] is Map)
                              SelectableText(
                                (task['metadata'] as Map)['checklist']
                                        ?.toString() ??
                                    '',
                              ),
                            ...Map<String, dynamic>.from(p['site'] as Map)
                                .entries
                                .where(
                                  (e) => {
                                    'name',
                                    'address',
                                    'accessInstructions',
                                  }.contains(e.key),
                                )
                                .map(
                                  (e) => SelectableText('${e.key}: ${e.value}'),
                                ),
                            ...(p['documents'] as List).map(
                              (d) => Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                child: SelectableText(
                                  '${d['name']} · Revisione ${d['version']}\n${d['content']}',
                                ),
                              ),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => _OfflineChecklist(pack: p),
                                ),
                              ),
                              child: const Text('Compila checklist e report'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            );
          },
        ),
        TextButton(
          onPressed: () async {
            await OfflineTaskPackStore.clearOwn();
            if (mounted) setState(() => _packs = OfflineTaskPackStore.list());
          },
          child: const Text('Elimina copie offline'),
        ),
      ],
    ),
  );
}
