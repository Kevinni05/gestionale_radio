import 'package:flutter/material.dart';
import 'services/company_api.dart';
import 'report_closure_screen.dart';
import 'theme/radiotech_glass.dart';

class NewReportScreen extends StatefulWidget {
  const NewReportScreen({super.key, this.loadAntennas});
  final Future<dynamic> Function()? loadAntennas;
  @override
  State<NewReportScreen> createState() => _NewReportScreenState();
}

class _NewReportScreenState extends State<NewReportScreen> {
  late final Future<dynamic> _antennas =
      widget.loadAntennas?.call() ?? CompanyApi.instance.request('/antennas');
  String? _antenna;
  String _type = 'Manutenzione preventiva';
  final Map<String, bool> _checks = {};
  final List<String> _antennaChecks = [];
  static const _templates = {
    'Manutenzione preventiva': [
      'Area e dispositivi di sicurezza',
      'Fissaggi e struttura',
      'Cavi e connettori',
      'Alimentazione e messa a terra',
      'Misure RF e qualità del segnale',
    ],
    'Intervento correttivo': [
      'Area e dispositivi di sicurezza',
      'Diagnosi del guasto',
      'Componenti sostituiti',
      'Ripristino del servizio',
      'Verifica delle misure finali',
    ],
    'Installazione e collaudo': [
      'Area e dispositivi di sicurezza',
      'Posizionamento e orientamento',
      'Cablaggio e impermeabilizzazione',
      'Configurazione apparati',
      'Collaudo e documentazione',
    ],
  };
  final _extra = TextEditingController();
  @override
  void initState() {
    super.initState();
    _setTemplate();
  }

  void _setTemplate() {
    _checks
      ..clear()
      ..addEntries(
        [
          ..._templates[_type]!,
          ..._antennaChecks,
        ].map((e) => MapEntry(e, false)),
      );
  }

  @override
  void dispose() {
    _extra.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Nuovo report')),
    body: FutureBuilder<dynamic>(
      future: _antennas,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(
            child: Text(
              'Impossibile caricare le antenne. Riapri la sezione per riprovare.',
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final raw = snapshot.data is Map
            ? snapshot.data['data']
            : snapshot.data;
        final antennas = (raw as List? ?? []).cast<Map>();
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Impianto e controlli',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              'Seleziona l’antenna e prepara i controlli da includere nel documento.',
            ),
            const SizedBox(height: 20),
            DropdownButtonFormField<String>(
              initialValue: _antenna,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Antenna di riferimento',
              ),
              items: antennas
                  .map(
                    (a) => DropdownMenuItem(
                      value: a['id'].toString(),
                      child: Text(
                        (a['name'] ?? a['id']).toString(),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (v) => setState(() {
                _antenna = v;
                final a = antennas.firstWhere((a) => a["id"].toString() == v);
                final template = a["checklistTemplate"];
                _antennaChecks.clear();
                if (template is List) {
                  for (final item in template) {
                    if (item is String && item.trim().isNotEmpty) {
                      _antennaChecks.add(item.trim());
                    }
                  }
                }
                _setTemplate();
              }),
            ),
            if (antennas.isEmpty)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Nessuna antenna disponibile. Richiedi al responsabile la registrazione dell’impianto.',
                ),
              ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _type,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Tipo di intervento',
              ),
              items: _templates.keys
                  .map((k) => DropdownMenuItem(value: k, child: Text(k)))
                  .toList(),
              onChanged: (v) => setState(() {
                _type = v!;
                _setTemplate();
              }),
            ),
            const SizedBox(height: 20),
            RadioTechGlass(
              child: Column(
                children: [
                  ListTile(
                    title: const Text('Lista di controllo'),
                    subtitle: Text(
                      '${_checks.values.where((v) => v).length} di ${_checks.length} verificati',
                    ),
                  ),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    child: LinearProgressIndicator(
                      value: _checks.isEmpty
                          ? 0
                          : _checks.values.where((v) => v).length /
                                _checks.length,
                    ),
                  ),
                  for (final e in _checks.entries)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      decoration: BoxDecoration(
                        color: e.value
                            ? Theme.of(
                                context,
                              ).colorScheme.primary.withValues(alpha: .08)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: CheckboxListTile(
                          value: e.value,
                          title: Text(e.key),
                          controlAffinity: ListTileControlAffinity.leading,
                          onChanged: (v) =>
                              setState(() => _checks[e.key] = v ?? false),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _extra,
              decoration: InputDecoration(
                labelText: 'Aggiungi un controllo personalizzato',
                suffixIcon: IconButton(
                  tooltip: 'Aggiungi controllo',
                  icon: const Icon(Icons.add),
                  onPressed: () {
                    final v = _extra.text.trim();
                    if (v.isNotEmpty && v.length <= 150) {
                      setState(() {
                        _checks.putIfAbsent(v, () => false);
                        _extra.clear();
                      });
                    }
                  },
                ),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              key: const Key('reportContinue'),
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Continua con il report'),
              onPressed: _antenna == null
                  ? null
                  : () {
                      final a = antennas.firstWhere(
                        (a) => a['id'].toString() == _antenna,
                      );
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ReportClosureScreen(
                            antennaId: _antenna!,
                            antennaName: (a['name'] ?? a['id']).toString(),
                            checklistResults: Map.of(_checks),
                          ),
                        ),
                      );
                    },
            ),
          ],
        );
      },
    ),
  );
}
