import 'services/italian_labels.dart';
import 'package:flutter/material.dart';
import 'theme/radiotech_glass.dart';
import 'theme/radiotech_content.dart';
import 'package:uuid/uuid.dart';
import 'services/api_service.dart';
import 'services/session_service.dart';
import 'services/auth_service.dart';
import 'offline_packs_screen.dart';
import 'security_pro_screen.dart';
import 'services/app_branding.dart';

class ProSuiteScreen extends StatefulWidget {
  const ProSuiteScreen({super.key, this.loadResource});
  final Future<dynamic> Function(String)? loadResource;
  @override
  State<ProSuiteScreen> createState() => _ProSuiteScreenState();
}

class _ProSuiteScreenState extends State<ProSuiteScreen> {
  Future<dynamic> _get(String path) =>
      (widget.loadResource ?? (path) => ApiService.instance.proRequest(path))(
        path,
      );
  List<Map<String, dynamic>> _catalog = [], _records = [];
  Map<String, dynamic>? _module;
  String? _error;
  bool _loading = true;
  int _epoch = 0;
  String _search = '';
  bool _actionPending = false;
  final Map<String, String> _actionOperations = {};
  static const _labels = <String, String>{
    'ARCHIVE': 'Archivia',
    'GENERATE': 'Genera incarico in scadenza',
    'SUBMIT': 'Invia per approvazione',
    'APPROVE': 'Approva',
    'REJECT': 'Rifiuta',
    'RECEIVE': 'Registra consegna',
    'PUBLISH': 'Pubblica',
    'ACKNOWLEDGE': 'Conferma presa in carico',
    'LOAD': 'Carica dal magazzino',
    'RESERVE': 'Riserva',
    'CONSUME': 'Registra consumo',
    'RETURN': 'Restituisci',
    'ASSIGN': 'Crea incarico',
    'RESOLVE': 'Chiudi',
    'PAUSE': 'Sospendi SLA',
    'RESUME': 'Riprendi SLA',
    'REVOKE': 'Revoca dispositivo',
    'ENABLE': 'Attiva integrazione',
    'DISABLE': 'Disattiva integrazione',
  };
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final epoch = ++_epoch;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_catalog.isEmpty) {
        final data = await _get('catalog');
        if (!mounted || epoch != _epoch) return;
        _catalog = (data as List)
            .map((r) => Map<String, dynamic>.from(r as Map))
            .toList();
        _module = _catalog.isEmpty ? null : _catalog.first;
      }
      if (_module != null) {
        final data = await _get(_module!['id'] as String);
        if (!mounted || epoch != _epoch) return;
        _records = (data['records'] as List)
            .map((r) => Map<String, dynamic>.from(r as Map))
            .toList();
        if (data['partial'] == true) {
          _error = 'Risultati parziali: limite di 1000 registrazioni.';
        }
      }
    } catch (e) {
      if (mounted && epoch == _epoch) _error = e.toString();
    } finally {
      if (mounted && epoch == _epoch) setState(() => _loading = false);
    }
  }

  Future<void> _edit([Map<String, dynamic>? record]) async {
    final module = _module;
    if (module == null) return;
    try {
      final options = <String, List<Map<String, dynamic>>>{};
      for (final field in module['fields'] as List) {
        final type = field['type'] as String;
        if (type.startsWith('ref:')) {
          final data = await _get('options/${type.substring(4)}');
          options[field['key'] as String] = (data as List)
              .map((v) => Map<String, dynamic>.from(v as Map))
              .toList();
        }
      }
      if (!mounted) return;
      final changed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) =>
              _ProEditor(module: module, record: record, options: options),
        ),
      );
      if (changed == true && mounted) await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _action(Map<String, dynamic> record, String action) async {
    if (_actionPending) return;
    final quantity = TextEditingController(), reason = TextEditingController();
    final numeric = {'LOAD', 'RESERVE', 'CONSUME', 'RETURN'}.contains(action);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_labels[action] ?? action),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(record['name']?.toString() ?? ''),
              if (numeric)
                TextField(
                  controller: quantity,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Quantità intera',
                  ),
                ),
              if (action == 'PAUSE')
                TextField(
                  controller: reason,
                  maxLength: 2000,
                  decoration: const InputDecoration(
                    labelText: 'Motivo della sospensione',
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Conferma'),
          ),
        ],
      ),
    );
    final qty = int.tryParse(quantity.text) ?? 0, note = reason.text;
    quantity.dispose();
    reason.dispose();
    if (confirmed != true || !mounted) return;
    if ((numeric && qty <= 0) || (action == 'PAUSE' && note.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Compila i campi obbligatori.')),
      );
      return;
    }
    final operationKey =
        '${_module!['id']}:${record['id']}:${record['version']}:$action:$qty:$note';
    final operationId = _actionOperations.putIfAbsent(
      operationKey,
      () => const Uuid().v4(),
    );
    setState(() => _actionPending = true);
    try {
      await ApiService.instance.proRequest(
        '${_module!['id']}/${record['id']}/actions',
        method: 'POST',
        body: {
          'action': action,
          'quantity': qty,
          'reason': note,
          'expectedVersion': record['version'],
          'operationId': operationId,
        },
      );
      if (mounted) await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _actionPending = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Row(
        children: [
          Image.asset(
            'assets/brand/radiotech-symbol-v1.png',
            width: 28,
            height: 28,
            semanticLabel: 'Logo ${AppBranding.name}',
          ),
          const SizedBox(width: 10),
          const Flexible(
            child: Text('Enterprise Pro', overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
      actions: [
        IconButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const SecurityProScreen()),
          ),
          icon: const Icon(Icons.security),
          tooltip: 'Sicurezza e accessi',
        ),
        if (!SessionService.instance.isCustomer)
          IconButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const OfflinePacksScreen(),
              ),
            ),
            icon: const Icon(Icons.offline_pin_outlined),
            tooltip: 'Pacchetti offline',
          ),
        if (SessionService.instance.isCustomer ||
            SessionService.instance.managementOnly)
          IconButton(
            onPressed: () => AuthService.instance.signOut(),
            icon: const Icon(Icons.logout),
            tooltip: 'Esci',
          ),
        IconButton(
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    floatingActionButton:
        _module == null ||
            _module!['writable'] == false ||
            {
              'analytics',
              'audit',
              'orders',
              'deliveries',
            }.contains(_module!['id']) ||
            (SessionService.instance.isCustomer && _module!['id'] != 'requests')
        ? null
        : FloatingActionButton(
            onPressed: _loading ? null : () => _edit(),
            child: const Icon(Icons.add),
          ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : RadioTechContent(
            child: RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  if (_catalog.isNotEmpty)
                    DropdownButtonFormField<String>(
                      initialValue: _module?['id'] as String?,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Sezione'),
                      items: _catalog
                          .map(
                            (m) => DropdownMenuItem(
                              value: m['id'] as String,
                              child: Text(
                                m['title'] as String,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (id) {
                        _module = _catalog.firstWhere((m) => m['id'] == id);
                        _load();
                      },
                    ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(_error!),
                    ),
                  const SizedBox(height: 16),
                  TextField(
                    decoration: const InputDecoration(labelText: 'Cerca'),
                    onChanged: (v) => setState(() => _search = v.toLowerCase()),
                  ),
                  if (_records.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('Nessuna registrazione.'),
                    ),
                  ..._records
                      .where(
                        (r) => r.toString().toLowerCase().contains(_search),
                      )
                      .map(
                        (r) => Card(
                          margin: const EdgeInsets.only(top: 12),
                          color: Colors.transparent,
                          child: RadioTechGlass(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  r['name']?.toString() ?? '',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                                Text(
                                  '${italianLabel(r['status'])} · Revisione ${r['version']}',
                                ),
                                ...(_module!['fields'] as List)
                                    .where(
                                      (f) =>
                                          f['key'] != 'name' &&
                                          r[f['key']] != null,
                                    )
                                    .map(
                                      (f) => Padding(
                                        padding: const EdgeInsets.only(top: 8),
                                        child: SelectableText(
                                          '${f['label']}: ${r[f['key']]}',
                                        ),
                                      ),
                                    ),
                                if (r['responseOverdue'] == true ||
                                    r['resolutionOverdue'] == true)
                                  const Text('⚠ SLA oltre scadenza'),
                                if (r['summary'] is Map)
                                  ...(r['summary'] as Map).entries.map(
                                    (entry) => Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: SelectableText(
                                        '${entry.key}: ${entry.value}',
                                      ),
                                    ),
                                  ),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    if (_module!['writable'] != false &&
                                        (!SessionService.instance.isCustomer ||
                                            _module!['id'] == 'requests'))
                                      TextButton(
                                        onPressed: () => _edit(r),
                                        child: const Text('Modifica'),
                                      ),
                                    ...(_module!['actions'] as List).map(
                                      (a) => OutlinedButton(
                                        onPressed: _actionPending
                                            ? null
                                            : () => _action(r, a as String),
                                        child: Text(_labels[a] ?? a.toString()),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                ],
              ),
            ),
          ),
  );
}

class _ProEditor extends StatefulWidget {
  const _ProEditor({
    required this.module,
    required this.record,
    required this.options,
  });
  final Map<String, dynamic> module;
  final Map<String, dynamic>? record;
  final Map<String, List<Map<String, dynamic>>> options;
  @override
  State<_ProEditor> createState() => _ProEditorState();
}

class _ProEditorState extends State<_ProEditor> {
  final _form = GlobalKey<FormState>();
  final _controllers = <String, TextEditingController>{};
  final _selections = <String, String?>{};
  bool _busy = false;
  String? _error;
  final _operationId = const Uuid().v4();
  @override
  void initState() {
    super.initState();
    for (final f in widget.module['fields'] as List) {
      final key = f['key'] as String;
      _controllers[key] = TextEditingController(
        text: widget.record?[key]?.toString() ?? '',
      );
      _selections[key] = widget.record?[key]?.toString();
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate() || _busy) return;
    final fields = <String, dynamic>{};
    for (final f in widget.module['fields'] as List) {
      final key = f['key'] as String, type = f['type'] as String;
      final value =
          (type.startsWith('ref:') || type.startsWith('select:')
                  ? _selections[key]
                  : _controllers[key]!.text)
              ?.trim();
      if (value == null || value.isEmpty) continue;
      fields[key] = {'number', 'positive'}.contains(type)
          ? double.parse(value)
          : type == 'datetime'
          ? DateTime.parse(value).toUtc().toIso8601String()
          : value;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ApiService.instance.proRequest(
        '${widget.module['id']}${widget.record == null ? '' : '/${widget.record!['id']}'}',
        method: widget.record == null ? 'POST' : 'PUT',
        body: {
          'fields': fields,
          'expectedVersion': widget.record?['version'] ?? 0,
          'operationId': _operationId,
        },
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.record == null ? 'Nuova registrazione' : 'Modifica'),
    ),
    body: RadioTechContent(
      child: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              widget.module['title'] as String,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            ...(widget.module['fields'] as List).map((f) {
              final key = f['key'] as String,
                  type = f['type'] as String,
                  label = f['label'] as String,
                  required = f['required'] == true;
              if (type.startsWith('ref:') || type.startsWith('select:')) {
                final options =
                    widget.options[key] ??
                    type
                        .substring(7)
                        .split(',')
                        .map((v) => <String, dynamic>{'id': v, 'name': v})
                        .toList();
                final selected = options.any((v) => v['id'] == _selections[key])
                    ? _selections[key]
                    : null;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: DropdownButtonFormField<String>(
                    initialValue: selected,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: label),
                    items: options
                        .map(
                          (v) => DropdownMenuItem(
                            value: v['id'] as String,
                            child: Text(
                              v['name'] as String,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: _busy ? null : (v) => _selections[key] = v,
                    validator: (v) => required && (v == null || v.isEmpty)
                        ? 'Obbligatorio'
                        : null,
                  ),
                );
              }
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: TextFormField(
                  controller: _controllers[key],
                  enabled: !_busy,
                  decoration: InputDecoration(
                    labelText: label,
                    helperText: type == 'datetime'
                        ? 'Data ISO: 2026-10-06T14:00:00+02:00'
                        : null,
                  ),
                  maxLines: type == 'textarea' ? 5 : 1,
                  maxLength: type == 'textarea' ? 32000 : 500,
                  keyboardType: {'number', 'positive'}.contains(type)
                      ? const TextInputType.numberWithOptions(decimal: true)
                      : TextInputType.text,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return required ? 'Obbligatorio' : null;
                    }
                    if ({'number', 'positive'}.contains(type)) {
                      final n = double.tryParse(v);
                      if (n == null ||
                          !n.isFinite ||
                          n < 0 ||
                          (type == 'positive' && n <= 0)) {
                        return 'Numero non valido';
                      }
                    }
                    if (type == 'datetime' && DateTime.tryParse(v) == null) {
                      return 'Data non valida';
                    }
                    return null;
                  },
                ),
              );
            }),
            if (_error != null) Text(_error!),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: Text(_busy ? 'Salvataggio…' : 'Salva'),
            ),
          ],
        ),
      ),
    ),
  );
}
