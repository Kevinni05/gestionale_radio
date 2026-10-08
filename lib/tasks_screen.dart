import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'backend_settings_screen.dart';
import 'package:geolocator/geolocator.dart';
import 'models/task_summary.dart';
import 'services/api_service.dart';
import 'services/app_navigation.dart';
import 'theme/radiotech_glass.dart';
import 'report_closure_screen.dart';

class TasksScreen extends StatefulWidget {
  const TasksScreen({
    super.key,
    this.loadTasks,
    this.highlightTaskId,
    this.changeStatus,
    this.checkIn,
    this.reportBuilder,
  });
  final Future<List<Map<String, dynamic>>> Function()? loadTasks;
  final String? highlightTaskId;
  final Future<void> Function(String, String)? changeStatus;
  final Future<void> Function(String)? checkIn;
  final Widget Function(TaskSummary)? reportBuilder;
  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> with WidgetsBindingObserver {
  late Future<List<Map<String, dynamic>>> _future;
  final _search = TextEditingController();
  final _busy = <String>{};
  String _filter = 'Attivi';
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AppNavigation.tasksRevision.addListener(_reloadFromNotification);
    if (widget.highlightTaskId != null) _filter = 'Tutti';
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() =>
      (widget.loadTasks ?? ApiService.instance.getMyTasks)();
  void _reloadFromNotification() {
    if (mounted) _refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _reloadFromNotification();
  }

  Future<void> _refresh() async {
    final future = _load();
    setState(() {
      _future = future;
    });
    try {
      await future;
    } catch (_) {
      /* FutureBuilder displays the failure. */
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AppNavigation.tasksRevision.removeListener(_reloadFromNotification);
    _search.dispose();
    super.dispose();
  }

  Future<void> _act(TaskSummary task) async {
    final action = task.nextAction;
    if (action == null || _busy.contains(task.id)) return;
    if (action == 'REPORT') {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              widget.reportBuilder?.call(task) ??
              ReportClosureScreen(
                checklistResults: const {},
                antennaId: task.antennaId ?? 'GENERICO',
                taskId: task.id,
              ),
        ),
      );
      if (mounted) await _refresh();
      return;
    }
    setState(() => _busy.add(task.id));
    try {
      if (action == 'CHECKED_IN') {
        if (widget.checkIn != null) {
          await widget.checkIn!(task.id);
        } else {
          if (!await Geolocator.isLocationServiceEnabled()) {
            throw StateError('Attiva la posizione del dispositivo.');
          }
          var permission = await Geolocator.checkPermission();
          if (permission == LocationPermission.denied) {
            permission = await Geolocator.requestPermission();
          }
          if (permission == LocationPermission.denied ||
              permission == LocationPermission.deniedForever) {
            throw StateError(
              'Consenti la posizione nelle impostazioni del dispositivo.',
            );
          }
          final position = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              timeLimit: Duration(seconds: 15),
            ),
          );
          await ApiService.instance.checkInTask(
            task.id,
            latitude: position.latitude,
            longitude: position.longitude,
            accuracy: position.accuracy,
          );
        }
      } else {
        if (widget.changeStatus != null) {
          await widget.changeStatus!(task.id, action);
        } else {
          await ApiService.instance.updateTaskStatus(task.id, action);
        }
      }
      AppNavigation.refreshTasks();
      if (mounted) await _refresh();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _busy.remove(task.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('I miei incarichi'),
        actions: [
          if (!kReleaseMode)
            IconButton(
              tooltip: 'Connessione al server',
              icon: const Icon(Icons.dns_outlined),
              onPressed: () async {
                await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => const BackendSettingsScreen(),
                  ),
                );
                if (mounted) _refresh();
              },
            ),
          IconButton(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
            tooltip: 'Aggiorna incarichi',
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _future,
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
                          const Icon(Icons.cloud_off_outlined, size: 48),
                          const SizedBox(height: 16),
                          const Text(
                            'Impossibile caricare gli incarichi. Controlla la connessione e riprova.',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: _refresh,
                            child: const Text('Riprova'),
                          ),
                          if (!kReleaseMode)
                            TextButton(
                              onPressed: () async {
                                await Navigator.of(context).push<bool>(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const BackendSettingsScreen(),
                                  ),
                                );
                                if (mounted) _refresh();
                              },
                              child: const Text('Verifica il server'),
                            ),
                        ],
                      ),
                    ),
                  );
                }
                final now = DateTime.now();
                final all = TaskSummary.ordered(
                  (snapshot.data ?? []).map(TaskSummary.new),
                  now,
                );
                final visible = all
                    .where(
                      (t) =>
                          t.matches(_search.text) &&
                          switch (_filter) {
                            'Attivi' => !t.archived && !t.awaitingReview,
                            'Scaduti' => t.overdueAt(now),
                            'In revisione' => t.awaitingReview,
                            _ => true,
                          },
                    )
                    .toList();
                final highlightedIndex = visible.indexWhere(
                  (task) => task.id == widget.highlightTaskId,
                );
                if (highlightedIndex > 0) {
                  visible.insert(0, visible.removeAt(highlightedIndex));
                }
                return RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      Text(
                        'La tua giornata sul campo',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Priorità, scadenze e avanzamento degli interventi assegnati.',
                      ),
                      const SizedBox(height: 20),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final columns =
                              MediaQuery.textScalerOf(context).scale(12) > 16
                              ? 1
                              : 3;
                          final width =
                              (constraints.maxWidth - 12 * (columns - 1)) /
                              columns;
                          return Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              _metric(
                                'Attivi',
                                all
                                    .where(
                                      (t) => !t.archived && !t.awaitingReview,
                                    )
                                    .length,
                                Icons.assignment_outlined,
                                width,
                              ),
                              _metric(
                                'Scaduti',
                                all.where((t) => t.overdueAt(now)).length,
                                Icons.timer_outlined,
                                width,
                              ),
                              _metric(
                                'In revisione',
                                all.where((t) => t.awaitingReview).length,
                                Icons.fact_check_outlined,
                                width,
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        controller: _search,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          labelText: 'Cerca incarichi',
                          prefixIcon: Icon(Icons.search),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: ['Attivi', 'Scaduti', 'In revisione', 'Tutti']
                            .map(
                              (value) => ChoiceChip(
                                label: Text(value),
                                selected: _filter == value,
                                onSelected: (_) =>
                                    setState(() => _filter = value),
                              ),
                            )
                            .toList(),
                      ),
                      const SizedBox(height: 16),
                      if (visible.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(32),
                          child: Text(
                            'Nessun incarico per questo filtro.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ...visible.map(
                        (task) => Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: _card(task, now),
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

  Widget _metric(String label, int count, IconData icon, double width) =>
      SizedBox(
        width: width,
        height: 140 * MediaQuery.textScalerOf(context).scale(12) / 12,
        child: Card(
          margin: EdgeInsets.zero,
          color: Colors.transparent,
          child: RadioTechGlass(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  icon,
                  color: Theme.of(context).colorScheme.secondary,
                  size: 20,
                ),
                const SizedBox(height: 8),
                Text(
                  '$count',
                  style: const TextStyle(
                    fontSize: 28,
                    height: 1.2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(label, style: const TextStyle(fontSize: 11, height: 1.3)),
              ],
            ),
          ),
        ),
      );

  Widget _card(TaskSummary task, DateTime now) {
    const labels = {
      'ACCEPTED': 'Accetta incarico',
      'EN_ROUTE': 'Inizia trasferimento',
      'CHECKED_IN': 'Check-in GPS',
      'IN_PROGRESS': 'Inizia lavoro',
      'REPORT': 'Compila rapporto',
    };
    final due = task.dueAt;
    return Card(
      margin: EdgeInsets.zero,
      color: Colors.transparent,
      shape: task.id == widget.highlightTaskId
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(
                color: Theme.of(context).colorScheme.primary,
                width: 2,
              ),
            )
          : null,
      child: RadioTechGlass(
        padding: const EdgeInsets.all(18),
        highlight: task.id == widget.highlightTaskId,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(label: Text(task.priorityLabel)),
                Chip(label: Text(task.statusLabel)),
                if (task.overdueAt(now))
                  const Chip(
                    label: Text('SCADUTO'),
                    avatar: Icon(Icons.warning_amber),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(task.title, style: Theme.of(context).textTheme.titleLarge),
            if (task.data['description'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(task.data['description'].toString()),
              ),
            const SizedBox(height: 12),
            Text('Asset: ${task.antennaId ?? 'Non associato'}'),
            if (due != null)
              Text(
                'Scadenza: ${due.day.toString().padLeft(2, '0')}/${due.month.toString().padLeft(2, '0')}/${due.year} ${due.hour.toString().padLeft(2, '0')}:${due.minute.toString().padLeft(2, '0')}',
              ),
            if (task.nextAction != null) ...[
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _busy.contains(task.id) ? null : () => _act(task),
                icon: _busy.contains(task.id)
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.arrow_forward),
                label: Text(labels[task.nextAction] ?? 'Apri'),
              ),
            ],
            if (task.awaitingReview)
              const Padding(
                padding: EdgeInsets.only(top: 16),
                child: Text(
                  'Rapporto inviato. In attesa della verifica del responsabile.',
                ),
              ),
          ],
        ),
      ),
    );
  }
}
