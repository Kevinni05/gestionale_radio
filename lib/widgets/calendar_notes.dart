import 'package:flutter/material.dart';
import '../services/company_api.dart';
import '../theme/radiotech_glass.dart';
import '../ai_hub_screen.dart' show CompanyRequest;

class CalendarNotes extends StatefulWidget {
  const CalendarNotes({super.key, this.request, this.compact = false});
  final CompanyRequest? request;
  final bool compact;
  @override
  State<CalendarNotes> createState() => _CalendarNotesState();
}

class _CalendarNotesState extends State<CalendarNotes> {
  late bool _expanded = !widget.compact;
  CompanyRequest get _request => widget.request ?? CompanyApi.instance.request;
  DateTime _day = DateUtils.dateOnly(DateTime.now());
  DateTime _start = DateUtils.dateOnly(DateTime.now());
  DateTime? _reminder;
  final _note = TextEditingController();
  List<Map> _notes = [];
  bool _loading = true, _saving = false;
  String? _error;
  String _key(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await _request('/calendar');
      if (!mounted) return;
      setState(() {
        _notes = (data as List).cast<Map>();
        _loading = false;
        _error = null;
        _select(_day);
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Note non disponibili. Riprova.';
        });
      }
    }
  }

  void _select(DateTime d) {
    _day = d;
    final n = _notes.where((n) => n['day'] == _key(d)).firstOrNull;
    _note.text = n?['note']?.toString() ?? '';
    _reminder = DateTime.tryParse(
      n?['reminderAt']?.toString() ?? '',
    )?.toLocal();
  }

  Future<void> _chooseReminder() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: _day.isBefore(today) ? today : _day,
      firstDate: today,
      lastDate: DateTime(today.year + 5),
    );
    if (picked == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(
        _reminder ?? DateTime.now().add(const Duration(hours: 1)),
      ),
    );
    if (time != null && mounted) {
      setState(
        () => _reminder = DateTime(
          picked.year,
          picked.month,
          picked.day,
          time.hour,
          time.minute,
        ),
      );
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await _request(
        '/calendar/${_key(_day)}',
        method: 'PUT',
        body: {
          'note': _note.text,
          'reminderAt': _reminder?.toUtc().toIso8601String(),
        },
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nota e promemoria salvati.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Salvataggio non riuscito. Verifica che il promemoria sia futuro e riprova.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => RadioTechGlass(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Note e promemoria',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            IconButton(
              tooltip: 'Settimana precedente',
              icon: const Icon(Icons.chevron_left),
              onPressed: () => setState(
                () => _start = DateTime(
                  _start.year,
                  _start.month,
                  _start.day - 7,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Settimana successiva',
              icon: const Icon(Icons.chevron_right),
              onPressed: () => setState(
                () => _start = DateTime(
                  _start.year,
                  _start.month,
                  _start.day + 7,
                ),
              ),
            ),
          ],
        ),
        if (_loading) const LinearProgressIndicator(),
        if (_error != null) TextButton(onPressed: _load, child: Text(_error!)),
        SizedBox(
          height: 110 * MediaQuery.textScalerOf(context).scale(1),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: 7,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final d = DateTime(_start.year, _start.month, _start.day + i);
              final chosen = DateUtils.isSameDay(d, _day);
              final note = _notes.any(
                (n) => n['day'] == _key(d) && '${n['note']}'.isNotEmpty,
              );
              return SizedBox(
                width: 90 * MediaQuery.textScalerOf(context).scale(1),
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.all(6),
                    backgroundColor: chosen
                        ? Theme.of(
                            context,
                          ).colorScheme.primary.withValues(alpha: .15)
                        : null,
                  ),
                  onPressed: _saving
                      ? null
                      : () => setState(() {
                          _select(d);
                          _expanded = true;
                        }),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        const [
                          'lun',
                          'mar',
                          'mer',
                          'gio',
                          'ven',
                          'sab',
                          'dom',
                        ][d.weekday - 1],
                      ),
                      Text(
                        '${d.day}',
                        style: const TextStyle(
                          fontSize: 23,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '${d.month}/${d.year}${note ? ' · ●' : ''}',
                        style: const TextStyle(fontSize: 10),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        if (_expanded) ...[
          const SizedBox(height: 16),
          Text('Nota del ${_day.day}/${_day.month}/${_day.year}'),
          const SizedBox(height: 8),
          TextField(
            controller: _note,
            enabled: !_saving && !_loading && _error == null,
            minLines: 3,
            maxLines: 8,
            maxLength: 4000,
            decoration: const InputDecoration(
              labelText: 'Nota personale',
              hintText: 'Appuntamento o verifica da ricordare',
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 12,
            children: [
              OutlinedButton.icon(
                onPressed: _saving ? null : _chooseReminder,
                icon: const Icon(Icons.notifications_outlined),
                label: Text(
                  _reminder == null
                      ? 'Imposta promemoria'
                      : '${_reminder!.day}/${_reminder!.month} ${_reminder!.hour.toString().padLeft(2, '0')}:${_reminder!.minute.toString().padLeft(2, '0')}',
                ),
              ),
              if (_reminder != null)
                TextButton(
                  onPressed: _saving
                      ? null
                      : () => setState(() => _reminder = null),
                  child: const Text('Rimuovi promemoria'),
                ),
              FilledButton.icon(
                onPressed: _saving || _loading || _error != null ? null : _save,
                icon: const Icon(Icons.save_outlined),
                label: Text(_saving ? 'Salvataggio…' : 'Salva nota'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Note sincronizzate con la web app. I promemoria richiedono il backend attivo e le notifiche abilitate.',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ],
    ),
  );
}
