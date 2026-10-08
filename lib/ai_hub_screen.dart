import 'services/italian_labels.dart';
import 'package:flutter/material.dart';
import 'theme/radiotech_glass.dart';
import 'services/company_api.dart';

typedef CompanyRequest =
    Future<dynamic> Function(
      String path, {
      String method,
      Map<String, dynamic>? body,
    });

class AiHubScreen extends StatefulWidget {
  const AiHubScreen({super.key, this.request});
  final CompanyRequest? request;
  @override
  State<AiHubScreen> createState() => _AiHubScreenState();
}

class _AiHubScreenState extends State<AiHubScreen> {
  final _message = TextEditingController();
  final _search = TextEditingController();
  final _history = <Map<String, String>>[];
  late Future<List<dynamic>> _data;
  bool _sending = false;
  bool _includeContext = false;
  String? _error;
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
    _request('/ai/insights').catchError(
      (Object error) => <String, dynamic>{
        'error': error.toString(),
        'notice': 'Analisi non disponibile. Puoi comunque usare la chat.',
        'risks': <dynamic>[],
      },
    ),
    _request('/ai/status').catchError(
      (Object error) => <String, dynamic>{
        'enabled': false,
        'error': error.toString(),
      },
    ),
  ]);
  void _reload() => setState(() {
    _data = _load();
  });
  @override
  void dispose() {
    _message.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final message = _message.text.trim();
    if (_sending || message.isEmpty) return;
    final previous = _history
        .skip(_history.length > 8 ? _history.length - 8 : 0)
        .map(
          (entry) => {
            'role': entry['role']!,
            'content': entry['content']!.length > 3000
                ? entry['content']!.substring(0, 3000)
                : entry['content']!,
          },
        )
        .toList();
    setState(() {
      _sending = true;
      _error = null;
      _history.add({'role': 'user', 'content': message});
    });
    try {
      final result = await _request(
        '/ai/chat',
        method: 'POST',
        body: {
          'message': message,
          'history': previous,
          'includeOperationalContext': _includeContext,
        },
      );
      if (!mounted) return;
      setState(() {
        _history.add({
          'role': 'assistant',
          'content': result['answer'].toString(),
        });
        if (_history.length > 40) _history.removeRange(0, _history.length - 40);
        _message.clear();
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _history.removeLast();
          _error = error.toString();
        });
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('AI e previsioni'),
        actions: [
          IconButton(
            onPressed: _reload,
            tooltip: 'Aggiorna analisi',
            icon: const Icon(Icons.refresh),
          ),
        ],
        bottom: const TabBar(
          tabs: [
            Tab(icon: Icon(Icons.insights_rounded), text: 'Analisi'),
            Tab(icon: Icon(Icons.auto_awesome_rounded), text: 'Assistente AI'),
          ],
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
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
                            'Analisi non disponibile. Verifica la rete e riprova.',
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
                final insights = Map<String, dynamic>.from(
                  snapshot.data![0] as Map,
                );
                final provider = Map<String, dynamic>.from(
                  snapshot.data![1] as Map,
                );
                final risks = (insights['risks'] as List? ?? [])
                    .where(
                      (r) => '${r['name']} ${r['assetId']}'
                          .toLowerCase()
                          .contains(_search.text.trim().toLowerCase()),
                    )
                    .toList();
                return TabBarView(
                  children: [
                    ListView(
                      padding: const EdgeInsets.all(18),
                      children: [
                        Text(
                          insights['scope'] == 'PERSONAL'
                              ? 'Analisi dei tuoi incarichi e asset assegnati'
                              : 'Analisi aziendale',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 14),
                        RadioTechGlass(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            insights['notice']?.toString() ??
                                'Analisi operativa aggiornata.',
                          ),
                        ),
                        const SizedBox(height: 16),
                        _metricGrid(context, insights),
                        const SizedBox(height: 12),
                        if (insights['partial'] == true)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              'Campione parziale: raggiunto il limite di analisi.',
                            ),
                          ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _search,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            labelText: 'Cerca impianto',
                            prefixIcon: Icon(Icons.search),
                          ),
                        ),
                        const SizedBox(height: 12),
                        for (final risk in risks)
                          Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            color: Colors.transparent,
                            child: RadioTechGlass(
                              padding: const EdgeInsets.all(18),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    risk['name']?.toString().isNotEmpty == true
                                        ? risk['name'].toString()
                                        : risk['assetId'].toString(),
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                  ),
                                  Text(
                                    '${italianLabel(risk['level'])} · Indicatore ${risk['score']}/100',
                                  ),
                                  if (risk['dataQuality'] == 'LIMITED')
                                    const Text('Dati limitati'),
                                  for (final reason
                                      in risk['reasons'] as List? ?? [])
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: Text('• $reason'),
                                    ),
                                  const SizedBox(height: 12),
                                  Text(risk['recommendation'].toString()),
                                  const SizedBox(height: 8),
                                  Text(
                                    risk['estimatedMaintenanceAt'] == null
                                        ? 'Storico insufficiente per stimare una data.'
                                        : 'Manutenzione stimata: ${DateTime.tryParse(risk['estimatedMaintenanceAt'].toString())?.toLocal().toString().split(' ').first} · mediana ${risk['medianIntervalDays']} giorni',
                                  ),
                                ],
                              ),
                            ),
                          ),
                        if (risks.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(24),
                            child: Text('Nessun impianto corrispondente.'),
                          ),
                      ],
                    ),
                    ListView(
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      children: [
                        RadioTechGlass(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.auto_awesome_rounded,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      'Assistente aziendale',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleMedium,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                provider['enabled'] == true
                                    ? 'Modello: ${provider['model']}. Le risposte restano in questa sessione.'
                                    : 'Il responsabile deve attivare il modello aziendale per usare la chat.',
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (_history.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              'Scrivi una domanda per iniziare la conversazione.',
                            ),
                          ),
                        for (final message in _history)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: RadioTechGlass(
                              padding: const EdgeInsets.all(18),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    message['role'] == 'user'
                                        ? 'Tu'
                                        : 'Assistente',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  SelectableText(message['content']!),
                                ],
                              ),
                            ),
                          ),
                        if (_sending)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Text("L'assistente sta rispondendo…"),
                          ),
                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Text(
                              _error!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                        RadioTechGlass(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SwitchListTile.adaptive(
                                contentPadding: EdgeInsets.zero,
                                title: const Text(
                                  'Includi indicatori operativi autorizzati',
                                ),
                                value: _includeContext,
                                onChanged: _sending
                                    ? null
                                    : (value) => setState(
                                        () => _includeContext = value,
                                      ),
                              ),
                              const SizedBox(height: 14),
                              TextField(
                                controller: _message,
                                enabled:
                                    !_sending && provider['enabled'] == true,
                                minLines: 3,
                                maxLines: 8,
                                maxLength: 3000,
                                decoration: const InputDecoration(
                                  labelText: 'Chiedi all’assistente',
                                  hintText:
                                      'Chiedi un’analisi o una spiegazione',
                                ),
                              ),
                              const SizedBox(height: 12),
                              ElevatedButton.icon(
                                onPressed:
                                    _sending || provider['enabled'] != true
                                    ? null
                                    : _send,
                                icon: const Icon(Icons.send_rounded),
                                label: Text(
                                  _sending
                                      ? 'Risposta in corso…'
                                      : 'Invia messaggio',
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextButton(
                                onPressed: _sending
                                    ? null
                                    : () => setState(() {
                                        _history.clear();
                                        _error = null;
                                      }),
                                child: const Text('Nuova chat'),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Verifica le risposte. Il modello locale non ha costi per richiesta; il server resta a carico dell’azienda.',
                          style: TextStyle(fontSize: 12, height: 1.5),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    ),
  );

  Widget _metricGrid(BuildContext context, Map insights) => LayoutBuilder(
    builder: (context, bounds) {
      final scale = MediaQuery.textScalerOf(context).scale(1);
      final columns = bounds.maxWidth < 330 * scale
          ? 1
          : bounds.maxWidth < 680 * scale
          ? 2
          : 4;
      final metrics = [
        ('Impianti', insights['assetsObserved'], Icons.cell_tower_rounded),
        (
          'Priorità alte',
          insights['highRiskAssets'],
          Icons.warning_amber_rounded,
        ),
        (
          'Incarichi attivi',
          insights['activeTasks'],
          Icons.assignment_outlined,
        ),
        ('Scaduti', insights['overdueTasks'], Icons.schedule_rounded),
      ];
      return Column(
        children: [
          for (var start = 0; start < metrics.length; start += columns)
            Padding(
              padding: EdgeInsets.only(
                bottom: start + columns < metrics.length ? 12 : 0,
              ),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (
                      var index = start;
                      index < (start + columns).clamp(0, metrics.length);
                      index++
                    ) ...[
                      if (index > start) const SizedBox(width: 12),
                      Expanded(
                        child: RadioTechGlass(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                metrics[index].$3,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                '${metrics[index].$2 ?? '—'}',
                                style: Theme.of(
                                  context,
                                ).textTheme.headlineMedium,
                              ),
                              const SizedBox(height: 6),
                              Text(metrics[index].$1),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      );
    },
  );
}
