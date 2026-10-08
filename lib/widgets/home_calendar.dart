import 'package:flutter/material.dart';
import '../models/task_summary.dart';
import '../theme/radiotech_glass.dart';
import '../theme/radiotech_theme.dart';
import 'radiotech_clock.dart';

class HomeCalendar extends StatefulWidget {
  const HomeCalendar({
    super.key,
    required this.tasks,
    required this.onOpenTask,
    required this.onOpenAgenda,
    this.onRefresh,
    this.loading = false,
    this.error = false,
    this.now,
  });
  final List<Map<String, dynamic>> tasks;
  final ValueChanged<String> onOpenTask;
  final VoidCallback onOpenAgenda;
  final VoidCallback? onRefresh;
  final bool loading, error;
  final DateTime? now;
  @override
  State<HomeCalendar> createState() => _HomeCalendarState();
}

class _HomeCalendarState extends State<HomeCalendar> {
  late DateTime _selected, _month;
  String _filter = 'Attivi';
  bool _showAllUndated = false;
  final _search = TextEditingController();
  DateTime get _today => widget.now ?? DateTime.now();
  static DateTime _date(DateTime d) => DateTime(d.year, d.month, d.day);
  static bool _same(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
  @override
  void initState() {
    super.initState();
    _selected = _date(_today);
    _month = DateTime(_selected.year, _selected.month);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<TaskSummary> get _tasks =>
      TaskSummary.ordered(widget.tasks.map(TaskSummary.new), _today)
          .where(
            (t) =>
                t.matches(_search.text) &&
                switch (_filter) {
                  'Attivi' => !t.archived && !t.awaitingReview,
                  'In revisione' => t.awaitingReview,
                  _ => true,
                },
          )
          .toList();
  void _move(int offset) => setState(() {
    _month = DateTime(_month.year, _month.month + offset);
    _selected = _month;
  });
  void _goToday() => setState(() {
    _selected = _date(_today);
    _month = DateTime(_selected.year, _selected.month);
  });
  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selected,
      firstDate: DateTime(1900),
      lastDate: DateTime(2200),
      helpText: 'Vai a una data',
    );
    if (date != null && mounted) {
      setState(() {
        _selected = date;
        _month = DateTime(date.year, date.month);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tasks = _tasks;
    final daily = tasks
        .where((t) => t.dueAt != null && _same(t.dueAt!, _selected))
        .toList();
    final undated = tasks.where((t) => t.dueAt == null).toList();
    final upcoming =
        tasks
            .where(
              (t) =>
                  t.dueAt != null &&
                  !_date(t.dueAt!).isBefore(_date(_today)) &&
                  !t.archived &&
                  !t.awaitingReview,
            )
            .toList()
          ..sort((a, b) => a.dueAt!.compareTo(b.dueAt!));
    return RadioTechGlass(
      key: const ValueKey('home-calendar'),
      padding: const EdgeInsets.all(16),
      radius: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.calendar_month_outlined, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Calendario',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                tooltip: 'Apri agenda completa',
                onPressed: widget.onOpenAgenda,
                icon: const Icon(Icons.open_in_new, size: 20),
              ),
              IconButton(
                tooltip: 'Aggiorna calendario',
                onPressed: widget.loading ? null : widget.onRefresh,
                icon: const Icon(Icons.refresh, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Scadenze e attività assegnate, giorno per giorno.',
            style: TextStyle(
              color: RadioTechTheme.muted,
              fontSize: 12,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              IconButton(
                tooltip: 'Mese precedente',
                onPressed: () => _move(-1),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: TextButton(
                  onPressed: _pickDate,
                  child: Text(
                    '${ItalianDate.months[_month.month - 1]} ${_month.year}',
                    key: const ValueKey('calendar-month'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Mese successivo',
                onPressed: () => _move(1),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _goToday,
              icon: const Icon(Icons.today_outlined, size: 18),
              label: const Text('Oggi'),
            ),
          ),
          _grid(tasks),
          const SizedBox(height: 12),
          const Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _Legend(color: RadioTechTheme.coral, label: 'Attività'),
              _Legend(color: RadioTechTheme.mist, label: 'Oggi'),
            ],
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Cerca nel calendario',
              prefixIcon: Icon(Icons.search),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: ['Attivi', 'In revisione', 'Tutti']
                .map(
                  (f) => ChoiceChip(
                    label: Text(f),
                    selected: _filter == f,
                    onSelected: (_) => setState(() => _filter = f),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 20),
          Text(
            ItalianDate.day(_selected),
            key: const ValueKey('calendar-selected-date'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          if (widget.loading) const LinearProgressIndicator(),
          if (widget.error) ...[
            const Text(
              'Attività non disponibili. Verifica la connessione e riprova.',
            ),
            TextButton(
              onPressed: widget.onRefresh,
              child: const Text('Riprova'),
            ),
          ] else if (!widget.loading && daily.isEmpty)
            const Text(
              'Nessuna attività per questo giorno.',
              style: TextStyle(color: RadioTechTheme.muted),
            ),
          ...daily.map(_task),
          if (!widget.error && !widget.loading && upcoming.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text(
              'Prossime scadenze',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            ...upcoming.take(3).map(_task),
          ],
          if (!widget.error && !widget.loading && undated.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text(
              'Senza data · ${undated.length}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            ...(_showAllUndated ? undated : undated.take(3)).map(_task),
            if (undated.length > 3)
              TextButton(
                onPressed: () =>
                    setState(() => _showAllUndated = !_showAllUndated),
                child: Text(
                  _showAllUndated
                      ? 'Mostra meno attività'
                      : 'Vedi tutte le attività senza data',
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _grid(List<TaskSummary> tasks) {
    final first = DateTime(_month.year, _month.month);
    final days = DateTime(_month.year, _month.month + 1, 0).day;
    final offset = first.weekday - 1;
    final cells = ((offset + days + 6) ~/ 7) * 7;
    const weekdays = ['L', 'M', 'M', 'G', 'V', 'S', 'D'];
    return Column(
      children: [
        Row(
          children: weekdays
              .map(
                (d) => Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      d,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: RadioTechTheme.muted,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        for (var row = 0; row < cells ~/ 7; row++)
          Row(
            children: [
              for (var col = 0; col < 7; col++)
                Expanded(child: _day(row * 7 + col - offset + 1, days, tasks)),
            ],
          ),
      ],
    );
  }

  Widget _day(int number, int days, List<TaskSummary> tasks) {
    final height =
        52.0 + (MediaQuery.textScalerOf(context).scale(13) - 13).clamp(0, 20);
    if (number < 1 || number > days) return SizedBox(height: height);
    final date = DateTime(_month.year, _month.month, number);
    final count = tasks
        .where((t) => t.dueAt != null && _same(t.dueAt!, date))
        .length;
    final selected = _same(date, _selected), today = _same(date, _today);
    return Semantics(
      label: '${ItalianDate.day(date)}, $count attività',
      selected: selected,
      button: true,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Material(
          color: selected ? const Color(0x99452324) : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
              color: selected
                  ? RadioTechTheme.coral
                  : today
                  ? RadioTechTheme.mist
                  : Colors.transparent,
            ),
          ),
          child: InkWell(
            key: ValueKey(
              'calendar-day-${date.year}-${date.month}-${date.day}',
            ),
            borderRadius: BorderRadius.circular(8),
            onTap: () => setState(() => _selected = date),
            child: SizedBox(
              height: height - 4,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '$number',
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: today || selected
                          ? FontWeight.w700
                          : FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    height: 5,
                    child: count > 0
                        ? Container(
                            width: 5,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: RadioTechTheme.coral,
                            ),
                          )
                        : null,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _task(TaskSummary task) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Material(
      color: const Color(0x551B1C26),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: RadioTechTheme.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => widget.onOpenTask(task.id),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const Icon(Icons.assignment_outlined, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${task.statusLabel} · Priorità ${task.priorityLabel}',
                      style: const TextStyle(
                        color: RadioTechTheme.muted,
                        fontSize: 11,
                        height: 1.5,
                      ),
                    ),
                    if (task.dueAt != null)
                      Text(
                        '${ItalianDate.day(task.dueAt!)} · ${ItalianDate.time(task.dueAt!).substring(0, 5)}',
                        style: const TextStyle(
                          color: RadioTechTheme.muted,
                          fontSize: 11,
                          height: 1.5,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right, size: 18),
            ],
          ),
        ),
      ),
    ),
  );
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});
  final Color color;
  final String label;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 6),
      Text(
        label,
        style: const TextStyle(color: RadioTechTheme.muted, fontSize: 11),
      ),
    ],
  );
}
