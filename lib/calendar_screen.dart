import 'package:flutter/material.dart';
import 'agenda_screen.dart';
import 'tasks_screen.dart';
import 'services/api_service.dart';
import 'services/app_navigation.dart';
import 'widgets/home_calendar.dart';
import 'widgets/calendar_notes.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key, this.initialTasks});
  final Future<List<Map<String, dynamic>>>? initialTasks;
  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen>
    with WidgetsBindingObserver {
  late Future<List<Map<String, dynamic>>> _tasks;
  @override
  void initState() {
    super.initState();
    _tasks = widget.initialTasks ?? ApiService.instance.getMyTasks();
    WidgetsBinding.instance.addObserver(this);
    AppNavigation.tasksRevision.addListener(_reload);
  }

  void _reload() {
    if (mounted) setState(() => _tasks = ApiService.instance.getMyTasks());
  }

  Future<void> _refresh() async {
    _reload();
    try {
      await _tasks;
    } catch (_) {
      /* The calendar displays the error and retry action. */
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _reload();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AppNavigation.tasksRevision.removeListener(_reload);
    super.dispose();
  }

  Future<void> _open(Widget screen) async {
    await Navigator.of(
      context,
    ).push<void>(MaterialPageRoute(builder: (_) => screen));
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.transparent,
    appBar: AppBar(title: const Text('Calendario')),
    body: RefreshIndicator(
      onRefresh: _refresh,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 32),
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _tasks,
              builder: (context, snapshot) => Column(
                children: [
                  HomeCalendar(
                    tasks: snapshot.data ?? const [],
                    loading:
                        snapshot.connectionState == ConnectionState.waiting,
                    error: snapshot.hasError,
                    onRefresh: _reload,
                    onOpenAgenda: () => _open(const AgendaScreen()),
                    onOpenTask: (id) => _open(TasksScreen(highlightTaskId: id)),
                  ),
                  const SizedBox(height: 18),
                  const CalendarNotes(),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
