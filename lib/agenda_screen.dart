import 'package:flutter/material.dart';
import 'theme/radiotech_glass.dart';
import 'models/task_summary.dart';
import 'services/api_service.dart';
import 'tasks_screen.dart';

class AgendaScreen extends StatefulWidget {
  const AgendaScreen({super.key, this.loadTasks, this.now});
  final Future<List<Map<String, dynamic>>> Function()? loadTasks;
  final DateTime? now;

  @override
  State<AgendaScreen> createState() => _AgendaScreenState();
}

class _AgendaScreenState extends State<AgendaScreen> {
  late Future<List<Map<String, dynamic>>> _future;
  String _period = 'Oggi';
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() =>
      (widget.loadTasks ?? ApiService.instance.getMyTasks)();

  Future<void> _refresh() async {
    final future = _load();
    setState(() {
      _future = future;
    });
    try {
      await future;
    } catch (_) {
      // The error and retry action are rendered by FutureBuilder.
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matches(TaskSummary task, DateTime now) {
    if (task.archived || task.awaitingReview || !task.matches(_search.text)) {
      return false;
    }
    final date = task.dueAt;
    final today = DateTime(now.year, now.month, now.day);
    return switch (_period) {
      'Scaduti' => task.overdueAt(now),
      'Senza data' => date == null,
      '7 giorni' =>
        date != null &&
            !date.isBefore(today) &&
            date.isBefore(DateTime(today.year, today.month, today.day + 7)),
      _ =>
        date != null &&
            date.year == now.year &&
            date.month == now.month &&
            date.day == now.day,
    };
  }

  Future<void> _openTask(TaskSummary task) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) =>
            TasksScreen(highlightTaskId: task.id, loadTasks: widget.loadTasks),
      ),
    );
    if (mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Agenda interventi'),
      actions: [
        IconButton(
          onPressed: _refresh,
          icon: const Icon(Icons.refresh),
          tooltip: 'Aggiorna agenda',
        ),
      ],
    ),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    const Text(
                      'Agenda non disponibile. Controlla la connessione.',
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _refresh,
                      child: const Text('Riprova'),
                    ),
                  ],
                );
              }
              final now = widget.now ?? DateTime.now();
              final tasks =
                  (snapshot.data ?? [])
                      .map(TaskSummary.new)
                      .where((task) => _matches(task, now))
                      .toList()
                    ..sort(
                      (a, b) => (a.dueAt ?? DateTime(9999)).compareTo(
                        b.dueAt ?? DateTime(9999),
                      ),
                    );
              return RefreshIndicator(
                onRefresh: _refresh,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(20),
                  children: [
                    const Text(
                      'Scadenze dei tuoi incarichi attivi. Orari locali del dispositivo.',
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _search,
                      decoration: const InputDecoration(
                        labelText: 'Cerca incarico o asset',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: ['Oggi', '7 giorni', 'Scaduti', 'Senza data']
                          .map(
                            (period) => ChoiceChip(
                              label: Text(period),
                              selected: _period == period,
                              onSelected: (_) =>
                                  setState(() => _period = period),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 20),
                    Text('${tasks.length} incarichi per questo filtro'),
                    if (tasks.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 32),
                        child: Text(
                          'Nessun incarico previsto per questo filtro.',
                        ),
                      ),
                    ...tasks.map(
                      (task) => Card(
                        color: Colors.transparent,
                        child: RadioTechGlass(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                task.title,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                task.dueAt == null
                                    ? 'Scadenza da definire'
                                    : MaterialLocalizations.of(
                                        context,
                                      ).formatFullDate(task.dueAt!),
                              ),
                              if (task.dueAt != null)
                                Text(
                                  MaterialLocalizations.of(
                                    context,
                                  ).formatTimeOfDay(
                                    TimeOfDay.fromDateTime(task.dueAt!),
                                    alwaysUse24HourFormat: true,
                                  ),
                                ),
                              const SizedBox(height: 8),
                              Text(
                                '${task.antennaId ?? "Nessun asset"} · ${task.priorityLabel} · ${task.statusLabel}',
                              ),
                              if (task.overdueAt(now))
                                Text(
                                  'Scadenza superata',
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                ),
                              const SizedBox(height: 12),
                              OutlinedButton.icon(
                                onPressed: () => _openTask(task),
                                icon: const Icon(Icons.assignment_outlined),
                                label: const Text('Apri incarico'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    ),
  );
}
