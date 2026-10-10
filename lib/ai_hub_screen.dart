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
  final _search = TextEditingController();
  late Future<Map<String, dynamic>> _data;
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

  Future<Map<String, dynamic>> _load() async {
    try {
      final result = await _request('/ai/insights');
      return Map<String, dynamic>.from(result as Map);
    } catch (error) {
      return {
        'error': error.toString(),
        'notice': 'Pianificazione non disponibile. Verifica la rete e riprova.',
        'risks': <dynamic>[],
      };
    }
  }

  void _reload() => setState(() {
    _data = _load();
  });
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Pianificazione preventiva'),
      actions: [
        IconButton(
          onPressed: _reload,
          tooltip: 'Aggiorna analisi',
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: FutureBuilder<Map<String, dynamic>>(
            future: _data,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError || snapshot.data?['error'] != null) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Pianificazione non disponibile. Verifica la rete e riprova.',
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
              final insights = snapshot.data!;
              final risks = (insights['risks'] as List? ?? [])
                  .where(
                    (r) => '${r['name']} ${r['assetId']}'
                        .toLowerCase()
                        .contains(_search.text.trim().toLowerCase()),
                  )
                  .toList();
              return ListView(
                padding: const EdgeInsets.all(18),
                children: [
                  Text(
                    'Scadenze e priorità operative',
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
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            Text(
                              '${italianLabel(risk['level'])} · Indicatore ${risk['score']}/100',
                            ),
                            if (risk['dataQuality'] == 'LIMITED')
                              const Text('Dati limitati'),
                            for (final reason in risk['reasons'] as List? ?? [])
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
              );
            },
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
