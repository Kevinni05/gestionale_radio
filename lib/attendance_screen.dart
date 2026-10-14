import 'services/auth_service.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'services/attendance_clock.dart';
import 'services/company_api.dart';
import 'services/session_service.dart';
import 'widgets/personal_badge.dart';
import 'theme/radiotech_glass.dart';

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});
  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen>
    with WidgetsBindingObserver {
  final _clock = AttendanceClock();
  Map<String, dynamic>? _roster, _report;
  String? _error;
  bool _busy = false;
  late String _month;
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final now = DateTime.now();
    _month = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    unawaited(_refresh(initial: true));
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  Future<void> _refresh({bool initial = false}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (initial) {
        await _clock.load();
      } else {
        await _clock.sync();
      }
      final data = await Future.wait([
        CompanyApi.instance.request('/workforce/me/roster/$_month'),
        CompanyApi.instance.request('/workforce/me/attendance?month=$_month'),
      ]);
      if (!mounted) return;
      setState(() {
        _roster = Map<String, dynamic>.from(data[0] as Map);
        _report = Map<String, dynamic>.from(data[1] as Map);
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _punch(String action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _clock.punch(action);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _clock.queue.isEmpty
                  ? 'Timbratura confermata dal server.'
                  : 'Timbratura salvata sul dispositivo, in attesa di conferma.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (mounted && _clock.queue.isEmpty) await _refresh();
  }

  String _hours(dynamic value) {
    final m = (value as num? ?? 0).toInt();
    return '${m ~/ 60}:${(m % 60).toString().padLeft(2, '0')}';
  }

  String _date(dynamic value) {
    final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    if (date == null) return '—';
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  Widget _card(String title, List<Widget> children) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: RadioTechGlass(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    ),
  );
  Future<void> _changeMonth(int offset) async {
    final parts = _month.split('-').map(int.parse).toList();
    final date = DateTime(parts[0], parts[1] + offset);
    setState(() {
      _month = '${date.year}-${date.month.toString().padLeft(2, '0')}';
      _roster = null;
      _report = null;
    });
    await _refresh();
  }

  Future<void> _pdf() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final bytes = await CompanyApi.instance.rosterPdf(_month);
      if (mounted) {
        await Printing.sharePdf(
          bytes: bytes,
          filename: 'RADIOTECH-turni-$_month.pdf',
        );
      }
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

  Future<void> _correct(Map row) async {
    var start = DateTime.parse(row['startedAt'].toString()).toLocal();
    var end = DateTime.parse(row['endedAt'].toString()).toLocal();
    final breaks = TextEditingController(text: '${row['breakMinutes'] ?? 0}');
    final reason = TextEditingController();
    final sent = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) {
          Future<void> pick(bool entry) async {
            final initial = entry ? start : end;
            final day = await showDatePicker(
              context: context,
              initialDate: initial,
              firstDate: DateTime(2020),
              lastDate: DateTime.now().add(const Duration(days: 1)),
            );
            if (day == null || !context.mounted) return;
            final time = await showTimePicker(
              context: context,
              initialTime: TimeOfDay.fromDateTime(initial),
            );
            if (time == null || !context.mounted) return;
            update(() {
              final selected = DateTime(
                day.year,
                day.month,
                day.day,
                time.hour,
                time.minute,
              );
              if (entry) {
                start = selected;
              } else {
                end = selected;
              }
            });
          }

          return AlertDialog(
            title: const Text('Richiedi correzione'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Seleziona gli orari corretti. Gli originali resteranno nello storico.',
                  ),
                  ListTile(
                    title: const Text('Entrata'),
                    subtitle: Text(_date(start.toIso8601String())),
                    trailing: const Icon(Icons.edit_calendar),
                    onTap: () => pick(true),
                  ),
                  ListTile(
                    title: const Text('Uscita'),
                    subtitle: Text(_date(end.toIso8601String())),
                    trailing: const Icon(Icons.edit_calendar),
                    onTap: () => pick(false),
                  ),
                  TextField(
                    controller: breaks,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Pausa (minuti)',
                    ),
                  ),
                  TextField(
                    controller: reason,
                    maxLength: 1000,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: 'Motivazione'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Annulla'),
              ),
              FilledButton(
                onPressed: () {
                  if (reason.text.trim().isNotEmpty &&
                      end.isAfter(start) &&
                      int.tryParse(breaks.text) != null) {
                    Navigator.pop(context, true);
                  }
                },
                child: const Text('Invia richiesta'),
              ),
            ],
          );
        },
      ),
    );
    if (sent == true && mounted) {
      setState(() => _busy = true);
      try {
        await CompanyApi.instance.request(
          '/workforce/me/attendance/corrections',
          method: 'POST',
          body: {
            'sessionId': row['id'],
            'startedAt': start.toUtc().toIso8601String(),
            'endedAt': end.toUtc().toIso8601String(),
            'breakMinutes': int.parse(breaks.text),
            'reason': reason.text.trim(),
            'expectedVersion': row['version'],
          },
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Richiesta inviata al responsabile.')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(e.toString())));
        }
      } finally {
        if (mounted) setState(() => _busy = false);
      }
      if (mounted) await _refresh();
    }
    breaks.dispose();
    reason.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shift = _clock.displayState;
    final status = shift?['status'];
    final slots = (_roster?['slots'] as List? ?? []).cast<Map>();
    final today = DateTime.now();
    final todayDate =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    final todaySlots = slots.where((s) => s['date'] == todayDate).toList();
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Presenze e turni'),
          actions: [
            IconButton(
              onPressed: _busy ? null : () => _refresh(),
              icon: const Icon(Icons.refresh),
              tooltip: 'Sincronizza',
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Badge'),
              Tab(text: 'Calendario'),
              Tab(text: 'Storico'),
            ],
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              if (_busy) const LinearProgressIndicator(),
              if (_clock.queue.isNotEmpty || _clock.syncError != null)
                MaterialBanner(
                  content: Text(
                    '${_clock.queue.length} timbrature in attesa. ${_clock.syncError ?? "Sincronizzazione da completare."}',
                  ),
                  actions: [
                    TextButton(
                      onPressed: _busy ? null : () => _refresh(),
                      child: const Text('Riprova'),
                    ),
                  ],
                ),
              Expanded(
                child: TabBarView(
                  children: [
                    ListView(
                      padding: const EdgeInsets.all(18),
                      children: [
                        _card('Il mio badge digitale', [
                          Text(
                            AuthService.instance.currentUser?.displayName ??
                                _clock.state?['name']?.toString() ??
                                'Operatore',
                          ),
                          Text(
                            'Identificativo: ${SessionService.instance.operatorId ?? "—"}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          Text(
                            status == 'ACTIVE'
                                ? 'In servizio'
                                : status == 'BREAK'
                                ? 'In pausa'
                                : status == 'OFF_DUTY'
                                ? 'Fuori servizio'
                                : 'Collegati per leggere lo stato',
                          ),
                          if (_clock.queue.isNotEmpty)
                            const Text(
                              'Stato locale previsto; le timbrature attendono conferma.',
                            ),
                          const SizedBox(height: 12),
                          if (todaySlots.isEmpty)
                            const Text(
                              'Nessun turno previsto disponibile per oggi.',
                            ),
                          for (final slot in todaySlots)
                            Text(
                              '${slot['label']} · ${_date(slot['startAt'])} → ${_date(slot['endAt'])} · ${slot['site']}',
                            ),
                          const SizedBox(height: 16),
                          if (shift != null)
                            Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: [
                                if (status == 'OFF_DUTY')
                                  FilledButton.icon(
                                    onPressed: _busy
                                        ? null
                                        : () => _punch('START'),
                                    icon: const Icon(Icons.login),
                                    label: const Text('Registra entrata'),
                                  ),
                                if (status == 'ACTIVE')
                                  OutlinedButton(
                                    onPressed: _busy
                                        ? null
                                        : () => _punch('BREAK'),
                                    child: const Text('Inizia pausa'),
                                  ),
                                if (status == 'BREAK')
                                  FilledButton(
                                    onPressed: _busy
                                        ? null
                                        : () => _punch('RESUME'),
                                    child: const Text('Riprendi servizio'),
                                  ),
                                if (status != 'OFF_DUTY')
                                  FilledButton.icon(
                                    onPressed: _busy
                                        ? null
                                        : () => _punch('END'),
                                    icon: const Icon(Icons.logout),
                                    label: const Text('Registra uscita'),
                                  ),
                              ],
                            ),
                          const SizedBox(height: 14),
                          Text(
                            'Attività confermata: ${_hours(_clock.state?['workMinutes'])} · Pausa: ${_hours(_clock.state?['restMinutes'])}',
                          ),
                          const Text(
                            'Chiudere l’app non registra l’uscita. Le ore restano soggette a validazione.',
                            style: TextStyle(fontSize: 12),
                          ),
                        ]),
                        PersonalBadge(
                          operatorId: SessionService.instance.operatorId,
                        ),
                        if (_error != null)
                          Text('Calendario o storico non disponibile: $_error'),
                      ],
                    ),
                    ListView(
                      padding: const EdgeInsets.all(18),
                      children: [
                        _card('Calendario personale', [
                          Row(
                            children: [
                              IconButton(
                                onPressed: _busy
                                    ? null
                                    : () => _changeMonth(-1),
                                icon: const Icon(Icons.chevron_left),
                              ),
                              Expanded(
                                child: Text(
                                  _month,
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              IconButton(
                                onPressed: _busy ? null : () => _changeMonth(1),
                                icon: const Icon(Icons.chevron_right),
                              ),
                            ],
                          ),
                          Text(
                            _roster?['status'] == 'PUBLISHED'
                                ? 'Versione ${_roster!['revision']} · Pubblicata ${_date(_roster!['publishedAt'])}'
                                : 'Calendario non ancora pubblicato.',
                          ),
                          Text(
                            'Fuso calendario: ${_roster?['zone'] ?? "—"}. Gli orari qui sono mostrati nel fuso del telefono.',
                          ),
                          FilledButton.icon(
                            onPressed:
                                _busy || _roster?['status'] != 'PUBLISHED'
                                ? null
                                : _pdf,
                            icon: const Icon(Icons.picture_as_pdf),
                            label: const Text(
                              'Scarica / condividi PDF personale',
                            ),
                          ),
                        ]),
                        for (final s in slots)
                          _card('${s['date']} · ${s['label']}', [
                            Text(
                              '${_date(s['startAt'])} → ${_date(s['endAt'])}',
                            ),
                            Text(
                              '${s['site']} · Pausa ${s['breakMinutes']} min · ${_hours(s['workMinutes'])} ore previste',
                            ),
                          ]),
                        if (_error != null) Text(_error!),
                      ],
                    ),
                    ListView(
                      padding: const EdgeInsets.all(18),
                      children: [
                        _card('Riepilogo $_month', [
                          Text(
                            'Pianificate ${_hours(_report?['plannedMinutes'])} · Registrate ${_hours(_report?['registeredMinutes'])} · Approvate ${_hours(_report?['approvedMinutes'])}',
                          ),
                        ]),
                        for (final row
                            in (_report?['sessions'] as List? ?? [])
                                .cast<Map>())
                          _card(
                            '${_date(row['startedAt'])} → ${_date(row['endedAt'])}',
                            [
                              Text(
                                '${_hours(row['workMinutes'])} ore · Pausa ${_hours(row['breakMinutes'])}',
                              ),
                              Text(switch (row['reviewStatus']) {
                                'APPROVED' => 'Approvato',
                                'PENDING' => 'Correzione in attesa',
                                'REJECTED' => 'Correzione respinta',
                                _ => 'Da validare',
                              }),
                              if (row['approved'] is Map)
                                Text(
                                  'Orari validati: ${_date(row['approved']['startedAt'])} → ${_date(row['approved']['endedAt'])}',
                                ),
                              if (row['status'] == 'OFF_DUTY' &&
                                  row['reviewStatus'] != 'PENDING')
                                TextButton(
                                  onPressed: _busy ? null : () => _correct(row),
                                  child: const Text('Richiedi correzione'),
                                ),
                            ],
                          ),
                        for (final a
                            in (_report?['anomalies'] as List? ?? [])
                                .cast<Map>())
                          _card('Da verificare', [
                            Text(a['message'].toString()),
                          ]),
                        if (_error != null) Text(_error!),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
