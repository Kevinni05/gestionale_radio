import 'dart:ui' as ui;
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:printing/printing.dart';
import 'package:gal/gal.dart';
import 'services/dossier_repository.dart';
import 'services/company_api.dart';
import 'services/auth_service.dart';
import 'theme/radiotech_glass.dart';

const _tabs = <String, String>{
  'overview': 'Riepilogo',
  'access': 'Accesso',
  'configuration': 'Configurazioni',
  'measurements': 'Misure',
  'dependencies': 'Dipendenze',
  'photos': 'Fotografie',
  'documents': 'Documenti',
  'components': 'Componenti',
  'issues': 'Problemi',
  'proposals': 'Correzioni',
  'sessions': 'Ponte radio',
  'shares': 'Condivisione',
};
const _access = <String, String>{
  'address': 'Indirizzo',
  'contact': 'Referente e contatti',
  'hours': 'Orari di accesso',
  'parking': 'Parcheggio',
  'keyInstructions': 'Ritiro chiavi',
  'route': 'Percorso',
  'restrictions': 'Restrizioni e precauzioni',
};
String _stamp(dynamic v) {
  final t = DateTime.tryParse(v?.toString() ?? '')?.toLocal();
  return t == null
      ? '—'
      : '${t.day.toString().padLeft(2, '0')}/${t.month.toString().padLeft(2, '0')}/${t.year} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

Map<String, dynamic> _map(dynamic v) =>
    v is Map ? Map<String, dynamic>.from(v) : {};
List<Map<String, dynamic>> _rows(Map<String, dynamic> data, String key) =>
    (data[key] as List? ?? []).map(_map).toList();

class AntennaDossierScreen extends StatefulWidget {
  const AntennaDossierScreen({
    super.key,
    required this.antennaId,
    this.repository,
    this.startOffline = false,
  });
  final String antennaId;
  final DossierRepository? repository;
  final bool startOffline;
  @override
  State<AntennaDossierScreen> createState() => _AntennaDossierScreenState();
}

class _AntennaDossierScreenState extends State<AntennaDossierScreen>
    with WidgetsBindingObserver {
  late final DossierRepository _repo = widget.repository ?? DossierRepository();
  Map<String, dynamic>? _data;
  String? _error;
  bool _loading = true, _offline = false, _busy = false;
  bool _foreground = true;
  StreamSubscription<dynamic>? _authChanges;
  String _tab = 'overview';
  String? _owner;
  Timer? _timer;
  int _generation = 0;
  List<Map<String, dynamic>> _sessions = [];
  Map<String, dynamic>? _session;
  int _before = 0, _after = 0;
  String? _metric;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    try {
      _owner = DossierRepository.currentOwner();
    } catch (_) {
      _owner = null;
    }
    _authChanges = AuthService.instance.authStateChanges().listen((_) {
      if (mounted && !_identityValid()) setState(() => _data = null);
    });
    _load(offline: widget.startOffline);
    _timer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!mounted) return;
      if (!_identityValid()) {
        setState(() => _data = null);
        return;
      }
      if (_offline &&
          _data != null &&
          DateTime.parse(
            _data!['validUntil'] as String,
          ).isBefore(DateTime.now())) {
        setState(() {
          _data = null;
          _error = 'Copia offline scaduta. Scaricala nuovamente online.';
        });
      }
      if (_foreground &&
          _tab == 'sessions' &&
          !_offline &&
          !_busy &&
          !_loading &&
          _data != null) {
        _run(_loadSessions);
      }
    });
  }

  @override
  void dispose() {
    _generation++;
    _timer?.cancel();
    _authChanges?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (state == AppLifecycleState.resumed && mounted && !_identityValid()) {
      setState(() => _data = null);
    }
  }

  bool _identityValid() {
    if (widget.repository != null) return true;
    try {
      return DossierRepository.currentOwner() == _owner;
    } catch (_) {
      return false;
    }
  }

  Future<void> _load({bool offline = false}) async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = offline
          ? await _repo.offline(widget.antennaId)
          : await _repo.load(widget.antennaId);
      if (data == null) {
        throw StateError(
          'Nessuna copia offline valida. Scarica il fascicolo quando sei online.',
        );
      }
      if (!mounted || generation != _generation || !_identityValid()) return;
      setState(() {
        _data = data;
        _offline = offline;
        _before = (_rows(data, 'configuration').length - 2)
            .clamp(0, 100)
            .toInt();
        _after = (_rows(data, 'configuration').length - 1)
            .clamp(0, 100)
            .toInt();
      });
      if (_foreground && _tab == 'sessions' && !offline) await _loadSessions();
    } catch (e) {
      if (mounted && generation == _generation) {
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy || !_identityValid()) return;
    setState(() => _busy = true);
    try {
      await action();
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

  Widget _card(String title, Widget child, {Widget? action}) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: RadioTechGlass(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              ?action,
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    ),
  );
  Widget _facts(Map<String, dynamic> values) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: values.entries
        .map(
          (e) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _access[e.key] ??
                      const {
                        'model': 'Modello',
                        'status': 'Stato',
                        'code': 'Codice',
                        'serial': 'Matricola',
                        'manufacturer': 'Produttore',
                        'site': 'Sede',
                        'specs': 'Dati tecnici',
                        'metric': 'Parametro',
                        'unit': 'Unità',
                        'value': 'Valore',
                        'notes': 'Note',
                        'recordedAt': 'Registrato il',
                        'actor': 'Tecnico',
                      }[e.key] ??
                      e.key,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                const SizedBox(height: 4),
                SelectableText(
                  e.value is Map
                      ? (_map(
                          e.value,
                        ).entries.map((p) => '${p.key}: ${p.value}').join('\n'))
                      : '${e.value ?? '—'}',
                ),
              ],
            ),
          ),
        )
        .toList(),
  );
  Widget _button(
    String title,
    FutureOr<void> Function() action, {
    IconData icon = Icons.add,
  }) => OutlinedButton.icon(
    onPressed: _busy || _offline || _data?['canContribute'] == false
        ? null
        : () => _run(() async {
            await action();
          }),
    icon: Icon(icon, size: 18),
    label: Text(title),
  );
  Widget _empty(String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 18),
    child: Text(text),
  );
  @override
  Widget build(BuildContext context) {
    final data = _identityValid() ? _data : null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fascicolo impianto'),
        actions: [
          IconButton(
            tooltip: 'Aggiorna online',
            onPressed: _busy ? null : () => _load(),
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Scarica fascicolo completo offline',
            onPressed: _busy || data == null || _offline
                ? null
                : () => _run(() async {
                    await _repo.download(widget.antennaId);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Fascicolo e allegati scaricati. Disponibili per 24 ore.',
                          ),
                        ),
                      );
                    }
                  }),
            icon: const Icon(Icons.download_for_offline_outlined),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : data == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.folder_off_outlined, size: 42),
                    const SizedBox(height: 16),
                    Text(_error ?? 'Sessione cambiata. Riapri il fascicolo.'),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () => _load(offline: true),
                      child: const Text('Apri copia offline'),
                    ),
                    TextButton(
                      onPressed: () => _load(),
                      child: const Text('Riprova online'),
                    ),
                  ],
                ),
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${data['name']}',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 5),
                        Text(
                          'Revisione ${data['version']} · ${_stamp(data['fetchedAt'])}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        if (_offline)
                          Text(
                            'COPIA OFFLINE · valida fino al ${_stamp(data['validUntil'])}',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.tertiary,
                            ),
                          ),
                        if (_busy) const LinearProgressIndicator(),
                      ],
                    ),
                  ),
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    children: _tabs.entries
                        .where(
                          (e) => e.key != 'shares' || data['canManage'] == true,
                        )
                        .map(
                          (e) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(e.value),
                              selected: _tab == e.key,
                              onSelected: (_) {
                                setState(() => _tab = e.key);
                                if (e.key == 'sessions' && !_offline) {
                                  _run(_loadSessions);
                                }
                              },
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () => _load(offline: _offline),
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: _content(data),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  List<Widget> _content(Map<String, dynamic> d) {
    final manage = d['canManage'] == true;
    switch (_tab) {
      case 'overview':
        return [
          _card('Identità e dati tecnici', _facts(_map(d['identity']))),
          _card(
            'Cronologia interventi e report',
            Column(
              children: [
                if (d['historyPartial'] == true)
                  const Text('Storico limitato a 200 elementi per sorgente.'),
                ..._rows(d, 'history').map(
                  (r) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('${r['title'] ?? r['id']}'),
                    subtitle: Text(
                      '${r['summary'] ?? r['description'] ?? ''}\n${r['status'] ?? ''} · ${_stamp(r['submittedAt'] ?? r['createdAt'])}',
                    ),
                  ),
                ),
                if (_rows(d, 'history').isEmpty)
                  _empty('Nessun intervento registrato.'),
              ],
            ),
          ),
        ];
      case 'access':
        return [
          _card(
            'Accesso al sito',
            _facts(_map(d['access'])),
            action: _button(
              manage ? 'Modifica' : 'Correggi',
              () => manage ? _editAccess() : _propose(),
            ),
          ),
        ];
      case 'configuration':
        final configs = _rows(d, 'configuration');
        if (configs.isEmpty) {
          return [
            _card(
              'Configurazioni',
              _empty('Nessuna revisione registrata.'),
              action: manage ? _button('Aggiungi', _configuration) : null,
            ),
          ];
        }
        final before = _map(
              configs[_before.clamp(0, configs.length - 1).toInt()]['values'],
            ),
            after = _map(
              configs[_after.clamp(0, configs.length - 1).toInt()]['values'],
            );
        return [
          _card(
            'Confronto revisioni',
            Column(
              children: [
                DropdownButtonFormField<int>(
                  key: ValueKey('before_${d["version"]}'),
                  initialValue: _before.clamp(0, configs.length - 1).toInt(),
                  decoration: const InputDecoration(labelText: 'Prima'),
                  items: List.generate(
                    configs.length,
                    (i) => DropdownMenuItem(
                      value: i,
                      child: Text(
                        '${configs[i]['label']}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  onChanged: (v) => setState(() => _before = v ?? 0),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  key: ValueKey('after_${d["version"]}'),
                  initialValue: _after.clamp(0, configs.length - 1).toInt(),
                  decoration: const InputDecoration(labelText: 'Dopo'),
                  items: List.generate(
                    configs.length,
                    (i) => DropdownMenuItem(
                      value: i,
                      child: Text(
                        '${configs[i]['label']}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  onChanged: (v) => setState(() => _after = v ?? 0),
                ),
                ...({...before.keys, ...after.keys}.toList()..sort()).map(
                  (k) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      before[k] == after[k]
                          ? Icons.check
                          : Icons.compare_arrows,
                      color: before[k] == after[k]
                          ? null
                          : Theme.of(context).colorScheme.primary,
                    ),
                    title: Text(k),
                    subtitle: Text('${before[k] ?? '—'} → ${after[k] ?? '—'}'),
                  ),
                ),
              ],
            ),
            action: manage
                ? _button('Revisione', _configuration)
                : _button('Correggi', _propose),
          ),
          ...configs.reversed.map(
            (r) => _card(
              '${r['label']}',
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${r['reason']}'),
                  Text(_stamp(r['createdAt'])),
                  ExpansionTile(
                    title: const Text('Parametri'),
                    children: [_facts(_map(r['values']))],
                  ),
                ],
              ),
            ),
          ),
        ];
      case 'measurements':
        final rows = _rows(
          d,
          'measurements',
        )..sort((a, b) => '${a['measuredAt']}'.compareTo('${b['measuredAt']}'));
        final metrics = rows.map((r) => '${r['metric']}').toSet().toList();
        if (!metrics.contains(_metric)) _metric = metrics.firstOrNull;
        final selected = rows.where((r) => r['metric'] == _metric).toList();
        final units = selected.map((r) => '${r['unit']}').toSet();
        return [
          _card(
            'Misurazioni manuali',
            Column(
              children: [
                if (metrics.isNotEmpty)
                  DropdownButtonFormField<String>(
                    initialValue: _metric,
                    items: metrics
                        .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                        .toList(),
                    onChanged: (v) => setState(() => _metric = v),
                  ),
                for (final unit in units) ...[
                  const SizedBox(height: 20),
                  Text('${_metric ?? ''} · $unit'),
                  SizedBox(
                    height: 150,
                    width: double.infinity,
                    child: CustomPaint(
                      painter: _MeasurementPainter(
                        selected.where((r) => r['unit'] == unit).toList(),
                        Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                ],
                ...selected.reversed.map(
                  (r) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      r['outsideThreshold'] == true
                          ? Icons.warning_amber
                          : Icons.show_chart,
                    ),
                    title: Text('${r['value']} ${r['unit']}'),
                    subtitle: Text(
                      '${_stamp(r['measuredAt'])}\nSoglie: ${r['low'] ?? '—'} / ${r['high'] ?? '—'}\n${r['notes'] ?? ''}',
                    ),
                  ),
                ),
                if (rows.isEmpty) _empty('Nessuna misura registrata.'),
              ],
            ),
            action: _button('Misura', _measurement),
          ),
        ];
      case 'dependencies':
        final edges = _rows(
          d,
          'dependencies',
        ).where((r) => r['archived'] != true).toList();
        return [
          _card(
            'Dipendenze dirette',
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Impianti da cui dipende questo sito. I collegamenti sono quelli documentati nel fascicolo.',
                ),
                ...edges.map(
                  (r) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.account_tree_outlined),
                    title: Text(
                      '${d['name']} → ${r['name'] ?? r['antennaId']}',
                    ),
                    subtitle: Text(
                      '${r['type']} · ${r['label']}\n${r['notes'] ?? ''}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => AntennaDossierScreen(
                          antennaId: '${r['antennaId']}',
                        ),
                      ),
                    ),
                  ),
                ),
                if (edges.isEmpty) _empty('Nessuna dipendenza registrata.'),
                if (d['networkNotice'] != null) Text('${d['networkNotice']}'),
                if (d['network'] is Map)
                  ExpansionTile(
                    title: const Text('Rete collegata'),
                    children: _rows(_map(d['network']), 'edges').map((edge) {
                      final nodes = _rows(_map(d['network']), 'nodes');
                      String name(dynamic id) =>
                          nodes
                              .where((n) => n['id'] == id)
                              .firstOrNull?['name']
                              ?.toString() ??
                          '$id';
                      return ListTile(
                        title: Text(
                          '${name(edge['source'])} → ${name(edge['target'])}',
                        ),
                        subtitle: Text('${edge['type']} · ${edge['label']}'),
                      );
                    }).toList(),
                  ),
              ],
            ),
          ),
        ];
      case 'photos':
        return [
          _card(
            'Fotografie originali e annotazioni',
            const Text(
              'Le annotazioni sono sovrapposte: il file originale rimane conservato.',
            ),
            action: _button('Aggiungi', _photo),
          ),
          ..._rows(d, 'photos').reversed.map(
            (r) => _card(
              '${r['title']}',
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${r['notes'] ?? ''}'),
                  Text(_stamp(r['createdAt'])),
                  OutlinedButton.icon(
                    onPressed: () => _run(() => _viewFile(r, photo: true)),
                    icon: const Icon(Icons.image_outlined),
                    label: const Text('Apri fotografia'),
                  ),
                ],
              ),
            ),
          ),
        ];
      case 'documents':
        return [
          _card(
            'Documentazione tecnica',
            const Text(
              'Gli allegati vengono inclusi nel download completo del fascicolo.',
            ),
          ),
          ..._rows(d, 'documents').reversed.map(
            (r) => _card(
              '${r['title']}',
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${r['notes'] ?? ''}'),
                  OutlinedButton.icon(
                    onPressed: r['fileId'] == null
                        ? null
                        : () => _run(() => _viewFile(r)),
                    icon: const Icon(Icons.description_outlined),
                    label: const Text('Apri e condividi documento'),
                  ),
                ],
              ),
            ),
          ),
        ];
      case 'components':
        return [
          _card(
            'Componenti installati',
            Column(
              children: [
                ..._rows(d, 'components').map(
                  (r) => ExpansionTile(
                    title: Text('${r['name']}'),
                    subtitle: Text(
                      '${r['model'] ?? ''} · ${r['serial'] ?? ''}',
                    ),
                    children: [
                      _facts({
                        'Installazione': r['installedAt'],
                        'Garanzia': r['warrantyUntil'],
                        'Note': r['notes'],
                      }),
                    ],
                  ),
                ),
                if (_rows(d, 'components').isEmpty)
                  _empty('Nessun componente registrato.'),
              ],
            ),
          ),
        ];
      case 'issues':
        return [
          _card(
            'Problemi dell’impianto',
            Column(
              children: [
                ..._rows(d, 'issues').reversed.map(
                  (r) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      r['status'] == 'OPEN'
                          ? Icons.error_outline
                          : Icons.check_circle_outline,
                    ),
                    title: Text('${r['title']}'),
                    subtitle: Text(
                      '${r['notes']}\n${r['status'] == 'OPEN' ? 'Aperto' : 'Risolto'}',
                    ),
                  ),
                ),
                if (_rows(d, 'issues').isEmpty)
                  _empty('Nessun problema registrato.'),
              ],
            ),
            action: _button('Segnala', _issue),
          ),
        ];
      case 'proposals':
        return [
          _card(
            'Correzioni proposte',
            const Text(
              'Il responsabile verifica la proposta; il valore precedente e la motivazione restano nella cronologia.',
            ),
            action: _button('Proponi', _propose),
          ),
          ..._rows(d, 'proposals').reversed.map(
            (r) => _card(
              '${r['target'] == 'access' ? 'Accesso' : 'Configurazione'} · ${r['field']}',
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _facts({
                    'Prima': r['before'],
                    'Proposta': r['value'],
                    'Motivazione': r['reason'],
                    'Stato': ({
                      'PENDING': 'Da verificare',
                      'APPROVED': 'Approvata',
                      'REJECTED': 'Respinta',
                    })[r['status']],
                    'Decisione': r['reviewReason'],
                  }),
                  if (manage && r['status'] == 'PENDING')
                    Wrap(
                      spacing: 8,
                      children: [
                        _button(
                          'Approva',
                          () => _review(r, true),
                          icon: Icons.check,
                        ),
                        _button(
                          'Respingi',
                          () => _review(r, false),
                          icon: Icons.close,
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ];
      case 'sessions':
        return _sessionContent();
      case 'shares':
        return [
          _card(
            'Condivisione temporanea',
            const Text(
              'Crea dal web un link con le sole sezioni da condividere. Il collegamento può essere revocato in qualsiasi momento.',
            ),
          ),
        ];
      default:
        return [];
    }
  }

  Future<void> _form(
    String title,
    Map<String, String> fields,
    Future<void> Function(Map<String, String>) save, {
    Map<String, String> initial = const {},
    String? description,
  }) async {
    if (_offline || !_identityValid()) return;
    final controllers = {
      for (final k in fields.keys)
        k: TextEditingController(text: initial[k] ?? ''),
    };
    final key = GlobalKey<FormState>();
    bool saving = false;
    String? error;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Form(
                key: key,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (description != null) Text(description),
                    ...fields.entries.map(
                      (e) => Padding(
                        padding: const EdgeInsets.only(top: 14),
                        child: TextFormField(
                          controller: controllers[e.key],
                          decoration: InputDecoration(labelText: e.value),
                          maxLines:
                              [
                                'notes',
                                'reason',
                                'values',
                                'value',
                                'route',
                                'keyInstructions',
                              ].contains(e.key)
                              ? 3
                              : 1,
                          maxLength: 2000,
                          keyboardType:
                              ['low', 'high'].contains(e.key) ||
                                  (e.key == 'value' &&
                                      fields.containsKey('metric'))
                              ? const TextInputType.numberWithOptions(
                                  decimal: true,
                                  signed: true,
                                )
                              : TextInputType.text,
                          validator: (v) =>
                              !{
                                    'notes',
                                    'unit',
                                    'low',
                                    'high',
                                    ..._access.keys,
                                  }.contains(e.key) &&
                                  (v == null || v.trim().isEmpty)
                              ? 'Campo obbligatorio'
                              : null,
                        ),
                      ),
                    ),
                    if (error != null)
                      Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(context),
              child: const Text('Annulla'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (!key.currentState!.validate()) return;
                      setLocal(() => saving = true);
                      try {
                        if (!_identityValid()) {
                          throw StateError('Sessione cambiata.');
                        }
                        await save(
                          controllers.map((k, c) => MapEntry(k, c.text.trim())),
                        );
                        if (context.mounted) Navigator.pop(context);
                      } catch (e) {
                        if (context.mounted) {
                          setLocal(() => error = e.toString());
                        }
                      } finally {
                        if (context.mounted) setLocal(() => saving = false);
                      }
                    },
              child: Text(saving ? 'Salvataggio…' : 'Salva'),
            ),
          ],
        ),
      ),
    );
    for (final c in controllers.values) {
      c.dispose();
    }
  }

  Future<void> _change(String section, Map<String, dynamic> data) async {
    await _repo.change(
      widget.antennaId,
      (_data!['version'] as num).toInt(),
      section,
      data,
    );
    await _load();
  }

  Future<void> _editAccess() => _form(
    'Accesso al sito',
    _access,
    (v) => _change('access', v),
    initial: _map(_data!['access']).map((k, v) => MapEntry(k, '$v')),
  );
  Map<String, String> _parsePairs(String value) {
    final values = <String, String>{};
    for (final line in value.split('\n').where((l) => l.trim().isNotEmpty)) {
      final pos = line.indexOf('=');
      if (pos < 1) {
        throw StateError('Usa nome = valore, una riga per parametro.');
      }
      values[line.substring(0, pos).trim()] = line.substring(pos + 1).trim();
    }
    return values;
  }

  Future<void> _configuration() => _form(
    'Nuova revisione',
    {
      'label': 'Nome revisione',
      'reason': 'Motivazione',
      'values': 'Parametri: nome = valore',
    },
    (v) => _change('configuration', {
      'label': v['label'],
      'reason': v['reason'],
      'values': _parsePairs(v['values']!),
    }),
    initial: {
      'values': _map(
        _rows(_data!, 'configuration').lastOrNull?['values'],
      ).entries.map((e) => '${e.key} = ${e.value}').join('\n'),
    },
  );
  Future<void> _measurement() async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (time == null || !mounted) return;
    final at = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    ).toUtc();
    await _form(
      'Misura del ${_stamp(at.toIso8601String())}',
      {
        'metric': 'Parametro',
        'unit': 'Unità',
        'value': 'Valore',
        'low': 'Soglia minima (facoltativa)',
        'high': 'Soglia massima (facoltativa)',
        'notes': 'Note (facoltative)',
      },
      (v) => _change('measurements', {
        'metric': v['metric'],
        'unit': v['unit'],
        'value': double.parse(v['value']!.replaceAll(',', '.')),
        'low': v['low']!.isEmpty
            ? null
            : double.parse(v['low']!.replaceAll(',', '.')),
        'high': v['high']!.isEmpty
            ? null
            : double.parse(v['high']!.replaceAll(',', '.')),
        'notes': v['notes'],
        'measuredAt': at.toIso8601String(),
      }),
    );
  }

  Future<void> _propose() async {
    final config = _map(_rows(_data!, 'configuration').lastOrNull?['values']);
    final selected = await showDialog<(String, String)>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Quale dato vuoi correggere?'),
        content: SizedBox(
          width: 500,
          child: ListView(
            shrinkWrap: true,
            children: [
              const Text('Accesso al sito'),
              ..._access.entries.map(
                (e) => ListTile(
                  title: Text(e.value),
                  onTap: () => Navigator.pop(context, ('access', e.key)),
                ),
              ),
              if (config.isNotEmpty) const Text('Configurazione'),
              ...config.keys.map(
                (k) => ListTile(
                  title: Text(k),
                  onTap: () => Navigator.pop(context, ('configuration', k)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (selected == null || !mounted) return;
    final values = selected.$1 == 'access' ? _map(_data!['access']) : config;
    await _form(
      'Proponi correzione',
      {'value': 'Valore corretto', 'reason': 'Motivazione'},
      (v) => _change('proposals', {
        'target': selected.$1,
        'field': selected.$2,
        ...v,
      }),
      initial: {'value': '${values[selected.$2] ?? ''}'},
      description:
          'La modifica sarà applicata dopo la verifica del responsabile.',
    );
  }

  Future<void> _issue() => _form('Segnala problema', {
    'title': 'Titolo',
    'notes': 'Descrizione',
  }, (v) => _change('issues', {...v, 'status': 'OPEN'}));
  Future<void> _review(Map<String, dynamic> proposal, bool approve) => _form(
    approve ? 'Approva correzione' : 'Respingi correzione',
    {'reason': 'Motivazione'},
    (v) async {
      await _repo.request(
        '${DossierRepository.path(widget.antennaId)}/reviews',
        method: 'POST',
        body: {
          'expectedVersion': _data!['version'],
          'operationId': CompanyApi.operationId(),
          'proposalId': proposal['id'],
          'approve': approve,
          'reason': v['reason'],
        },
      );
      await _load();
    },
  );
  Future<void> _photo() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Scatta una fotografia'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Scegli dalla galleria'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    final picked = await ImagePicker().pickImage(source: source);
    if (picked == null || !mounted) return;
    final bytes = await picked.readAsBytes();
    if (bytes.length > 10000000) throw StateError('Fotografia oltre 10 MB.');
    if (!mounted) return;
    final annotations = await Navigator.of(context)
        .push<List<Map<String, dynamic>>>(
          MaterialPageRoute(builder: (_) => _PhotoAnnotations(bytes: bytes)),
        );
    if (annotations == null || !mounted) return;
    await _form(
      'Registra fotografia',
      {'title': 'Titolo', 'notes': 'Descrizione'},
      (v) async {
        final fileId = await _repo.upload(picked.name, bytes);
        await _change('photos', {
          ...v,
          'fileId': fileId,
          'annotations': annotations,
        });
      },
    );
  }

  Future<void> _viewFile(Map<String, dynamic> row, {bool photo = false}) async {
    final file = await _repo.file(widget.antennaId, '${row['fileId']}', _data!);
    if (!mounted || !_identityValid()) return;
    final bytes = base64Decode(file['base64'] as String);
    if (photo ||
        RegExp(
          r'\.(png|jpe?g|webp)$',
          caseSensitive: false,
        ).hasMatch('${file['name']}')) {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final ratio = frame.image.width / frame.image.height;
      frame.image.dispose();
      codec.dispose();
      if (!mounted || !_identityValid()) return;
      Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => Scaffold(
            appBar: AppBar(
              title: Text('${row['title']}'),
              actions: [
                IconButton(
                  tooltip: 'Salva fotografia originale',
                  onPressed: () => _run(
                    () => Gal.putImageBytes(bytes, name: '${file['name']}'),
                  ),
                  icon: const Icon(Icons.share_outlined),
                ),
              ],
            ),
            body: Center(
              child: InteractiveViewer(
                child: _AnnotatedImage(
                  aspectRatio: ratio,
                  bytes: bytes,
                  marks: _rows(row, 'annotations'),
                ),
              ),
            ),
          ),
        ),
      );
    } else {
      await Printing.sharePdf(bytes: bytes, filename: '${file['name']}');
    }
  }

  Future<void> _loadSessions() async {
    final generation = _generation;
    final list =
        await _repo.request(
              '${DossierRepository.path(widget.antennaId)}/sessions',
            )
            as List;
    if (!mounted || !_identityValid() || generation != _generation) return;
    setState(() {
      _sessions = list.map(_map).toList();
      if (_session != null) {
        _session = _sessions
            .where((s) => s['id'] == _session!['id'])
            .firstOrNull;
      }
    });
  }

  List<Widget> _sessionContent() {
    if (_offline) {
      return [
        _card(
          'Prove coordinate',
          _empty(
            'La sessione condivisa richiede una connessione. Nessuna misura viene confermata offline.',
          ),
        ),
      ];
    }
    final s = _session;
    return [
      _card(
        'Sessioni del ponte radio',
        Column(
          children: [
            const Text(
              'La centrale configura i due impianti e i partecipanti. Aggiornamento ogni 10 secondi.',
            ),
            ..._sessions.map(
              (r) => ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${r['title']}'),
                subtitle: Text(
                  '${r['nameA']} ↔ ${r['nameB']}\n${r['state'] == 'OPEN' ? 'Aperta' : 'Conclusa'}',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => setState(() => _session = r),
              ),
            ),
            if (_sessions.isEmpty) _empty('Nessuna sessione assegnata.'),
          ],
        ),
      ),
      if (s != null) ...[
        _card(
          '${s['title']}',
          _facts({
            'A': '${s['nameA']} · ${s['operatorA']}',
            'B': '${s['nameB']} · ${s['operatorB']}',
          }),
          action: s['state'] == 'OPEN'
              ? _button(
                  'Prepara prova',
                  () => _form(
                    'Prova coordinata',
                    {
                      'label': 'Descrizione della prova',
                      'values': 'Regolazioni: nome = valore',
                    },
                    (v) => _trial('CREATE_TRIAL', {
                      'label': v['label'],
                      'settings': _parsePairs(v['values']!),
                    }),
                  ),
                )
              : null,
        ),
        ..._rows(s, 'trials').map(
          (r) => _card(
            '${r['label']}',
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _facts(_map(r['settings'])),
                for (final side in ['A', 'B']) ...[
                  const Divider(),
                  Text(
                    'Estremo $side',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  if (_map(r['results'])[side] is Map)
                    _facts(_map(_map(r['results'])[side]))
                  else ...[
                    const Text('In attesa della misura.'),
                    if (s['uid$side'] == _data!['uid'] && s['state'] == 'OPEN')
                      _button(
                        'Registra risultato',
                        () => _form(
                          'Misura estremo $side',
                          {
                            'metric': 'Parametro',
                            'unit': 'Unità',
                            'value': 'Valore',
                            'notes': 'Note',
                          },
                          (v) => _trial('RESULT', {
                            'trialId': r['id'],
                            'side': side,
                            ...v,
                            'value': double.parse(
                              v['value']!.replaceAll(',', '.'),
                            ),
                          }),
                        ),
                      ),
                  ],
                ],
              ],
            ),
          ),
        ),
        if (s['state'] == 'OPEN')
          _button(
            'Concludi sessione',
            () => _form('Esito delle prove', {
              'notes': 'Conclusione',
            }, (v) => _trial('CLOSE', v)),
            icon: Icons.check_circle_outline,
          )
        else
          _card('Esito finale', Text('${s['conclusion']}')),
      ],
    ];
  }

  Future<void> _trial(String action, Map<String, dynamic> payload) async {
    final s = _session!;
    await _repo.request(
      '/radio-pair-sessions/${s['id']}/trials',
      method: 'POST',
      body: {
        'expectedVersion': s['version'],
        'operationId': CompanyApi.operationId(),
        'action': action,
        ...payload,
      },
    );
    await _loadSessions();
  }
}

class _MeasurementPainter extends CustomPainter {
  _MeasurementPainter(this.rows, this.color);
  final List<Map<String, dynamic>> rows;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    if (rows.isEmpty) return;
    final values = rows.map((r) => (r['value'] as num).toDouble()).toList();
    final lo = values.reduce((a, b) => a < b ? a : b),
        hi = values.reduce((a, b) => a > b ? a : b);
    final times = rows
        .map(
          (r) =>
              DateTime.parse(r['measuredAt'] as String).millisecondsSinceEpoch,
        )
        .toList();
    final start = times.first, span = times.last - start;
    final path = Path();
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    for (var i = 0; i < rows.length; i++) {
      final p = Offset(
        10 + (span == 0 ? 0.5 : (times[i] - start) / span) * (size.width - 20),
        size.height -
            15 -
            ((values[i] - lo) / (hi == lo ? 1 : hi - lo)) * (size.height - 35),
      );
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawCircle(p, 3, Paint()..color = color);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _MeasurementPainter old) =>
      old.rows != rows || old.color != color;
}

class _AnnotatedImage extends StatelessWidget {
  const _AnnotatedImage({
    required this.bytes,
    required this.marks,
    required this.aspectRatio,
  });
  final Uint8List bytes;
  final double aspectRatio;
  final List<Map<String, dynamic>> marks;
  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: aspectRatio,
    child: Stack(
      fit: StackFit.expand,
      children: [
        Image.memory(bytes, width: double.infinity, fit: BoxFit.fill),
        Positioned.fill(child: CustomPaint(painter: _AnnotationPainter(marks))),
      ],
    ),
  );
}

class _AnnotationPainter extends CustomPainter {
  _AnnotationPainter(this.marks);
  final List<Map<String, dynamic>> marks;
  @override
  void paint(Canvas c, Size s) {
    final p = Paint()
      ..color = const Color(0xffffb454)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    for (final m in marks) {
      final a = Offset(
            (m['x'] as num).toDouble() * s.width,
            (m['y'] as num).toDouble() * s.height,
          ),
          b = Offset(
            (m['x2'] as num).toDouble() * s.width,
            (m['y2'] as num).toDouble() * s.height,
          );
      if (m['type'] == 'RECT') {
        c.drawRect(Rect.fromPoints(a, b), p);
      } else if (m['type'] == 'ARROW') {
        c.drawLine(a, b, p);
        final v = a - b;
        if (v.distance > 0) {
          final u = v / v.distance;
          final wing = Offset(-u.dy, u.dx);
          c.drawLine(b, b + u * 14 + wing * 7, p);
          c.drawLine(b, b + u * 14 - wing * 7, p);
        }
      }
      final t = TextPainter(
        text: TextSpan(
          text: '${m['text'] ?? ''}',
          style: const TextStyle(
            color: Color(0xffffb454),
            backgroundColor: Color(0xb3000000),
            fontSize: 14,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: s.width);
      t.paint(
        c,
        Offset(
          a.dx.clamp(0, s.width - t.width).toDouble(),
          a.dy.clamp(0, s.height - t.height).toDouble(),
        ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _AnnotationPainter old) => true;
}

class _PhotoAnnotations extends StatefulWidget {
  const _PhotoAnnotations({required this.bytes});
  final Uint8List bytes;
  @override
  State<_PhotoAnnotations> createState() => _PhotoAnnotationsState();
}

class _PhotoAnnotationsState extends State<_PhotoAnnotations> {
  final _marks = <Map<String, dynamic>>[];
  final _text = TextEditingController();
  Offset? _start, _end;
  String _type = 'ARROW';
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Annota la fotografia'),
      actions: [
        IconButton(
          tooltip: 'Annulla ultimo segno',
          onPressed: _marks.isEmpty
              ? null
              : () => setState(() => _marks.removeLast()),
          icon: const Icon(Icons.undo),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _marks),
          child: const Text('Conferma'),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Trascina sull’immagine. Il file originale non viene modificato.',
        ),
        const SizedBox(height: 14),
        DropdownButtonFormField<String>(
          initialValue: _type,
          items: const [
            DropdownMenuItem(value: 'ARROW', child: Text('Freccia')),
            DropdownMenuItem(value: 'RECT', child: Text('Riquadro')),
            DropdownMenuItem(value: 'TEXT', child: Text('Nota')),
          ],
          onChanged: (v) => setState(() => _type = v!),
        ),
        TextField(
          controller: _text,
          maxLength: 200,
          decoration: const InputDecoration(
            labelText: 'Testo annotazione (facoltativo)',
          ),
        ),
        LayoutBuilder(
          builder: (context, box) => Stack(
            children: [
              Image.memory(widget.bytes, width: box.maxWidth),
              Positioned.fill(
                child: LayoutBuilder(
                  builder: (context, size) => GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: (e) {
                      _start = e.localPosition;
                      _end = e.localPosition;
                    },
                    onPanUpdate: (e) => _end = e.localPosition,
                    onPanCancel: () {
                      _start = null;
                      _end = null;
                    },
                    onPanEnd: (_) {
                      if (_start == null ||
                          _end == null ||
                          _marks.length >= 40) {
                        return;
                      }
                      final a = _start!, b = _end!;
                      setState(
                        () => _marks.add({
                          'type': _type,
                          'text': _text.text,
                          'x': (a.dx / size.maxWidth).clamp(0, 1),
                          'y': (a.dy / size.maxHeight).clamp(0, 1),
                          'x2': (b.dx / size.maxWidth).clamp(0, 1),
                          'y2': (b.dy / size.maxHeight).clamp(0, 1),
                        }),
                      );
                      _start = null;
                      _end = null;
                    },
                    child: CustomPaint(painter: _AnnotationPainter(_marks)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class OfflineDossiersScreen extends StatefulWidget {
  const OfflineDossiersScreen({super.key});
  @override
  State<OfflineDossiersScreen> createState() => _OfflineDossiersScreenState();
}

class _OfflineDossiersScreenState extends State<OfflineDossiersScreen> {
  late Future<List<Map<String, dynamic>>> _packs =
      DossierRepository.offlineIndex();
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Fascicoli offline'),
      actions: [
        IconButton(
          tooltip: 'Aggiorna elenco',
          onPressed: () =>
              setState(() => _packs = DossierRepository.offlineIndex()),
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: _packs,
      builder: (context, s) {
        if (s.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (s.hasError) {
          return const Center(
            child: Text('Impossibile leggere i fascicoli di questo account.'),
          );
        }
        final rows = s.data ?? [];
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Copie cifrate di fascicoli e allegati scaricati. Sono personali e scadono dopo 24 ore.',
            ),
            const SizedBox(height: 16),
            if (rows.isEmpty)
              const Text(
                'Nessun fascicolo disponibile. Apri un impianto online e usa Scarica offline.',
              ),
            ...rows.map(
              (r) => Card(
                child: ListTile(
                  leading: const Icon(Icons.folder_open_outlined),
                  title: Text('${r['name']}'),
                  subtitle: Text(
                    'Scaricato ${_stamp(r['fetchedAt'])}\nValido fino al ${_stamp(r['validUntil'])}',
                  ),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => AntennaDossierScreen(
                        antennaId: '${r['antennaId']}',
                        startOffline: true,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
}
