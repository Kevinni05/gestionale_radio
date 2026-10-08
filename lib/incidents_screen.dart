import 'services/italian_labels.dart';
import 'package:flutter/material.dart';
import 'theme/radiotech_glass.dart';

import 'services/api_service.dart';
import 'services/session_service.dart';

class IncidentsScreen extends StatefulWidget {
  final Future<List<Map<String, dynamic>>> Function()? loadIncidents;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic> payload)?
  createIncident;
  final Future<Map<String, dynamic>> Function(String id, String status)?
  transitionIncident;
  final Future<Map<String, dynamic>> Function(
    String id,
    String status,
    String? rootCause,
    String? resolution,
  )?
  transitionIncidentWithDetails;

  const IncidentsScreen({
    this.loadIncidents,
    this.createIncident,
    this.transitionIncident,
    this.transitionIncidentWithDetails,
    super.key,
  });

  @override
  State<IncidentsScreen> createState() => _IncidentsScreenState();
}

class _IncidentsScreenState extends State<IncidentsScreen> {
  bool get _canManage =>
      SessionService.instance.canManage ||
      widget.createIncident != null ||
      widget.transitionIncident != null ||
      widget.transitionIncidentWithDetails != null;
  late Future<List<Map<String, dynamic>>> _incidentsFuture;
  final Set<String> _updatingIds = {};
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    _incidentsFuture = _loadIncidents();
  }

  Future<List<Map<String, dynamic>>> _loadIncidents() {
    final loader = widget.loadIncidents;
    if (loader != null) {
      return Future.sync(loader);
    }
    return ApiService.instance.getIncidents();
  }

  Future<Map<String, dynamic>> _createIncident(Map<String, dynamic> payload) {
    final creator = widget.createIncident;
    if (creator != null) {
      return Future.sync(() => creator(payload));
    }
    return ApiService.instance.createIncident(
      title: payload['title'] as String,
      description: payload['description'] as String?,
      severity: payload['severity'] as String,
    );
  }

  Future<Map<String, dynamic>> _transitionIncident(
    String id,
    String status, {
    String? rootCause,
    String? resolution,
  }) {
    final detailedTransition = widget.transitionIncidentWithDetails;
    if (detailedTransition != null) {
      return Future.sync(
        () => detailedTransition(id, status, rootCause, resolution),
      );
    }
    final transition = widget.transitionIncident;
    if (transition != null) {
      return Future.sync(() => transition(id, status));
    }
    return ApiService.instance.transitionIncident(
      id,
      status,
      rootCause: rootCause,
      resolution: resolution,
    );
  }

  void _reload() {
    setState(() {
      _incidentsFuture = _loadIncidents();
    });
  }

  Future<void> _create() async {
    final payload = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => const _CreateIncidentDialog(),
    );
    if (payload == null || !mounted) return;

    setState(() => _creating = true);
    try {
      await _createIncident(payload);
      if (!mounted) return;
      _reload();
    } catch (error) {
      if (mounted) _showError('Creazione incident non riuscita', error);
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _advance(Map<String, dynamic> incident) async {
    final id = _value(incident['id']);
    final current = _value(incident['status'])?.toUpperCase();
    final next = _nextStatus[current];
    if (id == null || next == null) return;

    String? rootCause;
    String? resolution;
    if (next == 'RESOLVED') {
      final details = await showDialog<Map<String, String>>(
        context: context,
        builder: (context) => const _IncidentResolutionDialog(),
      );
      if (details == null || !mounted) return;
      rootCause = details['rootCause'];
      resolution = details['resolution'];
    }

    setState(() => _updatingIds.add(id));
    try {
      await _transitionIncident(
        id,
        next,
        rootCause: rootCause,
        resolution: resolution,
      );
      if (!mounted) return;
      _reload();
    } catch (error) {
      if (mounted) _showError('Aggiornamento incident non riuscito', error);
    } finally {
      if (mounted) setState(() => _updatingIds.remove(id));
    }
  }

  void _showError(String action, Object error) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$action: $error')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Incidenti'),
        actions: [
          IconButton(
            tooltip: 'Aggiorna',
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: !_canManage
          ? null
          : FloatingActionButton.extended(
              onPressed: _creating ? null : _create,
              icon: _creating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add_alert_outlined),
              label: const Text('Nuovo incident'),
            ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _incidentsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _IncidentMessage(
              message: 'Impossibile caricare gli incident: ${snapshot.error}',
              buttonLabel: 'Riprova',
              onPressed: _reload,
            );
          }
          final incidents = snapshot.data ?? const [];
          if (incidents.isEmpty) {
            return const _IncidentMessage(
              message: 'Nessun incident registrato.',
            );
          }
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              itemCount: incidents.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final incident = incidents[index];
                final id = _value(incident['id']) ?? '';
                final status = _value(incident['status'])?.toUpperCase();
                final nextStatus = _nextStatus[status];
                final severity =
                    _value(incident['severity'])?.toUpperCase() ?? 'MEDIUM';
                final title =
                    _value(incident['title']) ?? 'Incident senza titolo';
                final description = _value(incident['description']);
                return Card(
                  color: Colors.transparent,
                  child: RadioTechGlass(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.crisis_alert,
                              color: _severityColor(context, severity),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                title,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            Text(
                              severity,
                              style: Theme.of(context).textTheme.labelMedium
                                  ?.copyWith(
                                    color: _severityColor(context, severity),
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text('Stato: ${italianLabel(status)}'),
                        if (description != null) ...[
                          const SizedBox(height: 8),
                          Text(description),
                        ],
                        for (final (label, key) in const [
                          ('Sito', 'siteId'),
                          ('Asset', 'assetId'),
                          ('Task', 'taskId'),
                        ])
                          if (_value(incident[key]) case final value?)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text('$label: $value'),
                            ),
                        if (_canManage &&
                            nextStatus != null &&
                            id.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Align(
                            alignment: Alignment.centerRight,
                            child: OutlinedButton(
                              onPressed: _updatingIds.contains(id)
                                  ? null
                                  : () => _advance(incident),
                              child: _updatingIds.contains(id)
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Text(_statusAction(nextStatus)),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _CreateIncidentDialog extends StatefulWidget {
  const _CreateIncidentDialog();

  @override
  State<_CreateIncidentDialog> createState() => _CreateIncidentDialogState();
}

class _CreateIncidentDialogState extends State<_CreateIncidentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  String _severity = 'MEDIUM';

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop({
      'title': _titleController.text.trim(),
      'description': _descriptionController.text.trim(),
      'severity': _severity,
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nuovo incident'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _titleController,
                maxLength: 200,
                decoration: const InputDecoration(labelText: 'Titolo'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Inserisci un titolo.'
                    : null,
              ),
              TextFormField(
                controller: _descriptionController,
                maxLength: 4000,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Descrizione'),
              ),
              DropdownButtonFormField<String>(
                initialValue: _severity,
                decoration: const InputDecoration(labelText: 'Severità'),
                items: const ['LOW', 'MEDIUM', 'HIGH', 'CRITICAL']
                    .map(
                      (value) =>
                          DropdownMenuItem(value: value, child: Text(value)),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) setState(() => _severity = value);
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annulla'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Crea')),
      ],
    );
  }
}

class _IncidentMessage extends StatelessWidget {
  final String message;
  final String? buttonLabel;
  final VoidCallback? onPressed;

  const _IncidentMessage({
    required this.message,
    this.buttonLabel,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.crisis_alert_outlined, size: 42),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            if (buttonLabel != null && onPressed != null) ...[
              const SizedBox(height: 12),
              FilledButton(onPressed: onPressed, child: Text(buttonLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

class _IncidentResolutionDialog extends StatefulWidget {
  const _IncidentResolutionDialog();

  @override
  State<_IncidentResolutionDialog> createState() =>
      _IncidentResolutionDialogState();
}

class _IncidentResolutionDialogState extends State<_IncidentResolutionDialog> {
  final _formKey = GlobalKey<FormState>();
  final _rootCause = TextEditingController();
  final _resolution = TextEditingController();

  @override
  void dispose() {
    _rootCause.dispose();
    _resolution.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop({
      'rootCause': _rootCause.text.trim(),
      'resolution': _resolution.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Risolvi incident'),
    content: Form(
      key: _formKey,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _rootCause,
              maxLength: 4000,
              decoration: const InputDecoration(labelText: 'Root cause'),
              validator: _requiredIncidentDetail,
            ),
            TextFormField(
              controller: _resolution,
              maxLength: 4000,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Risoluzione'),
              validator: _requiredIncidentDetail,
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Annulla'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Risolvi')),
    ],
  );
}

String? _requiredIncidentDetail(String? value) =>
    value == null || value.trim().isEmpty
    ? 'Campo obbligatorio.'
    : value.length > 4000
    ? 'Massimo 4000 caratteri.'
    : null;

const _nextStatus = <String, String>{
  'DETECTED': 'ACKNOWLEDGED',
  'ACKNOWLEDGED': 'ASSIGNED',
  'ASSIGNED': 'INVESTIGATING',
  'INVESTIGATING': 'MITIGATED',
  'MITIGATED': 'RESOLVED',
  'RESOLVED': 'POST_MORTEM',
  'POST_MORTEM': 'CLOSED',
};

String _statusAction(String status) => switch (status) {
  'ACKNOWLEDGED' => 'Prendi in carico',
  'ASSIGNED' => 'Imposta stato: assegnato',
  'INVESTIGATING' => 'Avvia indagine',
  'MITIGATED' => 'Mitiga',
  'RESOLVED' => 'Risolvi',
  'POST_MORTEM' => 'Apri analisi conclusiva',
  'CLOSED' => 'Chiudi incidente',
  _ => status,
};

String? _value(dynamic value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

Color _severityColor(BuildContext context, String severity) =>
    switch (severity) {
      'CRITICAL' => Theme.of(context).colorScheme.error,
      'HIGH' => Colors.deepOrange,
      'LOW' => Colors.green,
      _ => Colors.amber,
    };
