import 'package:flutter/material.dart';
import 'theme/radiotech_glass.dart';
import 'ai_hub_screen.dart' show CompanyRequest;
import 'services/company_api.dart';
import 'services/session_service.dart';

class WorkforceScreen extends StatefulWidget {
  const WorkforceScreen({super.key, this.request, this.canManage});
  final CompanyRequest? request;
  final bool? canManage;
  @override
  State<WorkforceScreen> createState() => _WorkforceScreenState();
}

class _WorkforceScreenState extends State<WorkforceScreen> {
  final _description = TextEditingController();
  final _asset = TextEditingController();
  late Future<List<dynamic>> _data;
  bool _busy = false;
  String _readiness = 'READY', _type = 'HAZARD', _severity = 'MEDIUM';
  bool get _manager => widget.canManage ?? SessionService.instance.canManage;
  Future<dynamic> _request(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
  }) => (widget.request ?? CompanyApi.instance.request)(
    path,
    method: method,
    body: body,
  );
  @override
  void initState() {
    super.initState();
    _data = _load();
  }

  Future<List<dynamic>> _load() => Future.wait([
    _request('/workforce/me/shift'),
    _request('/workforce/signals'),
    if (_manager) _request('/workforce/shifts'),
  ]);
  void _reload() => setState(() {
    _data = _load();
  });
  @override
  void dispose() {
    _description.dispose();
    _asset.dispose();
    super.dispose();
  }

  String _label(dynamic value) =>
      {
        'ACTIVE': 'Al lavoro',
        'BREAK': 'In pausa',
        'OFF_DUTY': 'Fuori turno',
        'READY': 'Disponibile',
        'NEEDS_BREAK': 'Richiede pausa',
        'REQUEST_SUPPORT': 'Richiede supporto',
        'OPEN': 'Da prendere in carico',
        'ACKNOWLEDGED': 'In carico',
        'RESOLVED': 'Risolto',
        'HAZARD': 'Pericolo',
        'NEAR_MISS': 'Quasi incidente',
        'SUPPORT_REQUEST': 'Supporto',
      }[value] ??
      value.toString();
  Future<void> _perform(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) _reload();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
        _reload();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signal() => _perform(() async {
    if (_description.text.trim().isEmpty) {
      throw StateError('Descrivi la segnalazione.');
    }
    await _request(
      '/workforce/signals',
      method: 'POST',
      body: {
        'type': _type,
        'severity': _severity,
        'description': _description.text.trim(),
        'assetId': _asset.text.trim().isEmpty ? null : _asset.text.trim(),
        'operationId': CompanyApi.operationId(),
      },
    );
    if (mounted) {
      _description.clear();
      _asset.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Segnalazione registrata per i responsabili.'),
        ),
      );
    }
  });
  Future<void> _review(Map signal) async {
    String resolution = '';
    if (signal['status'] == 'ACKNOWLEDGED') {
      final controller = TextEditingController();
      final result = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Risoluzione'),
          content: TextField(
            controller: controller,
            maxLength: 1000,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Descrivi la risoluzione',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annulla'),
            ),
            TextButton(
              onPressed: () {
                if (controller.text.trim().isNotEmpty) {
                  Navigator.pop(context, controller.text.trim());
                }
              },
              child: const Text('Conferma'),
            ),
          ],
        ),
      );
      controller.dispose();
      if (result == null || !mounted) return;
      resolution = result;
    }
    await _perform(() async {
      await _request(
        '/workforce/signals/${signal['id']}',
        method: 'PATCH',
        body: {
          'status': signal['status'] == 'OPEN' ? 'ACKNOWLEDGED' : 'RESOLVED',
          'resolution': resolution,
          'expectedVersion': signal['version'],
        },
      );
    });
  }

  Widget _select(
    String label,
    String value,
    Map<String, String> options,
    void Function(String) changed,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: options.entries
          .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
          .toList(),
      onChanged: _busy
          ? null
          : (next) {
              if (next != null) setState(() => changed(next));
            },
    ),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Squadra e sicurezza'),
      actions: [
        IconButton(
          onPressed: _busy ? null : _reload,
          tooltip: 'Aggiorna',
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: FutureBuilder<List<dynamic>>(
            future: _data,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Stato non disponibile. Le operazioni richiedono una connessione attiva.',
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: _reload,
                          child: const Text('Riprova'),
                        ),
                      ],
                    ),
                  ),
                );
              }
              final shift = snapshot.data![0] as Map;
              final signals = snapshot.data![1] as List;
              final actions = shift['status'] == 'OFF_DUTY'
                  ? {'START': 'Inizia turno'}
                  : shift['status'] == 'BREAK'
                  ? {'RESUME': 'Riprendi', 'END': 'Termina turno'}
                  : {'BREAK': 'Inizia pausa', 'END': 'Termina turno'};
              return ListView(
                padding: const EdgeInsets.all(18),
                children: [
                  Card(
                    color: Colors.transparent,
                    child: RadioTechGlass(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Il mio turno e le pause',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '${_label(shift['status'])} · ${shift['workMinutes']} min attività · ${shift['restMinutes']} min pausa',
                          ),
                          if (shift['stale'] == true)
                            const Text(
                              'Registrazione non aggiornata: verifica il turno.',
                            ),
                          if (shift['pauseSuggested'] == true)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: Text(
                                'Valuta una pausa con il responsabile.',
                              ),
                            ),
                          const SizedBox(height: 14),
                          _select(
                            'Disponibilità dichiarata',
                            _readiness,
                            {
                              'READY': 'Disponibile',
                              'NEEDS_BREAK': 'Ho bisogno di una pausa',
                              'REQUEST_SUPPORT': 'Chiedo supporto',
                            },
                            (v) => _readiness = v,
                          ),
                          Wrap(
                            spacing: 12,
                            runSpacing: 10,
                            children: [
                              for (final action in actions.entries)
                                ElevatedButton(
                                  onPressed: _busy
                                      ? null
                                      : () => _perform(() async {
                                          await _request(
                                            '/workforce/me/shift',
                                            method: 'PUT',
                                            body: {
                                              'action': action.key,
                                              'readiness': _readiness,
                                              'expectedVersion':
                                                  shift['version'],
                                              'operationId':
                                                  CompanyApi.operationId(),
                                            },
                                          );
                                        }),
                                  child: Text(action.value),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Registrazione volontaria visibile ai responsabili. Nessun GPS continuo. Timbrature disponibili nel registro presenze; ore soggette a validazione.',
                            style: TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    color: Colors.transparent,
                    child: RadioTechGlass(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Segnala e chiedi supporto',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 16),
                          _select('Tipo', _type, {
                            'HAZARD': 'Pericolo',
                            'NEAR_MISS': 'Quasi incidente',
                            'SUPPORT_REQUEST': 'Richiesta di supporto',
                          }, (v) => _type = v),
                          _select('Priorità', _severity, {
                            'LOW': 'Bassa',
                            'MEDIUM': 'Media',
                            'HIGH': 'Alta',
                            'CRITICAL': 'Critica',
                          }, (v) => _severity = v),
                          TextField(
                            controller: _description,
                            enabled: !_busy,
                            maxLength: 1000,
                            maxLines: 4,
                            decoration: const InputDecoration(
                              labelText: 'Descrizione',
                            ),
                          ),
                          TextField(
                            controller: _asset,
                            enabled: !_busy,
                            maxLength: 128,
                            decoration: const InputDecoration(
                              labelText: 'ID asset (facoltativo)',
                            ),
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton(
                            onPressed: _busy ? null : _signal,
                            child: const Text('Registra segnalazione'),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Visibile ai responsabili del tuo tenant. Non inserire dati sanitari. Per un pericolo immediato usa i canali di emergenza aziendali: la sezione non è monitorata in continuo.',
                            style: TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_manager) ...[
                    const SizedBox(height: 20),
                    Text(
                      'Disponibilità della squadra',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    for (final member in snapshot.data![2] as List)
                      Card(
                        child: ListTile(
                          title: Text(member['name'].toString()),
                          subtitle: Text(
                            '${_label(member['status'])} · ${_label(member['readiness'])} · ${member['workMinutes']} min${member['stale'] == true ? ' · Da verificare' : ''}',
                          ),
                        ),
                      ),
                  ],
                  const SizedBox(height: 20),
                  Text(
                    'Segnalazioni e presa in carico',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  for (final signal in signals)
                    Card(
                      color: Colors.transparent,
                      child: RadioTechGlass(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${_label(signal['type'])} · ${signal['severity']}',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            Text(signal['description'].toString()),
                            Text(
                              '${_label(signal['status'])} · ${signal['name']}',
                            ),
                            if (signal['resolution'] != null)
                              Text(signal['resolution'].toString()),
                            if (_manager && signal['status'] != 'RESOLVED')
                              TextButton(
                                onPressed: _busy ? null : () => _review(signal),
                                child: Text(
                                  signal['status'] == 'OPEN'
                                      ? 'Prendi in carico'
                                      : 'Risolvi',
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  if (signals.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('Nessuna segnalazione.'),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );
}

