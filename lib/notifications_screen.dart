import 'package:flutter/material.dart';
import 'theme/radiotech_glass.dart';
import 'services/api_service.dart';
import 'tasks_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({
    super.key,
    this.loadNotifications,
    this.onOpenTask,
  });
  final Future<List<Map<String, dynamic>>> Function()? loadNotifications;
  final void Function(String)? onOpenTask;
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late Future<List<Map<String, dynamic>>> _future;
  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() =>
      (widget.loadNotifications ?? ApiService.instance.getMyNotifications)();

  Future<void> _refresh() async {
    final future = _load();
    setState(() {
      _future = future;
    });
    try {
      await future;
    } catch (_) {
      /* The list shows the failure. */
    }
  }

  void _openTask(String id) {
    if (widget.onOpenTask != null) {
      widget.onOpenTask!(id);
    } else {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => TasksScreen(highlightTaskId: id),
        ),
      );
    }
  }

  String _time(Object? value) {
    final time = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    if (time == null) return '';
    return '${time.day.toString().padLeft(2, '0')}/${time.month.toString().padLeft(2, '0')}/${time.year} '
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Notifiche e avvisi'),
      actions: [
        IconButton(
          onPressed: _refresh,
          icon: const Icon(Icons.refresh),
          tooltip: 'Aggiorna notifiche',
        ),
      ],
    ),
    body: FutureBuilder<List<Map<String, dynamic>>>(
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
                  const Icon(Icons.cloud_off_rounded),
                  const SizedBox(height: 12),
                  Text(
                    'Impossibile caricare le notifiche.\n${snapshot.error}',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _refresh,
                    child: const Text('Riprova'),
                  ),
                ],
              ),
            ),
          );
        }
        final notifications = snapshot.data ?? const [];
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            itemCount: notifications.isEmpty ? 1 : notifications.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              if (notifications.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 60),
                  child: Text(
                    'Nessuna notifica al momento.',
                    textAlign: TextAlign.center,
                  ),
                );
              }
              final item = notifications[index];
              final taskId = item['taskId']?.toString().trim() ?? '';
              return Card(
                color: Colors.transparent,
                child: RadioTechGlass(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.notifications_active_outlined),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              item['title']?.toString() ??
                                  'Comunicazione operativa',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(item['message']?.toString() ?? ''),
                      if (item['id'] != null)
                        Wrap(
                          spacing: 8,
                          children: [
                            TextButton(
                              onPressed: () async {
                                try {
                                  await ApiService.instance.markNotification(
                                    item['id'].toString(),
                                  );
                                  if (mounted) await _refresh();
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text(e.toString())),
                                    );
                                  }
                                }
                              },
                              child: Text(
                                (item['readAt']?.toString() ?? '').isEmpty
                                    ? 'Segna come letta'
                                    : 'Letta',
                              ),
                            ),
                            TextButton(
                              onPressed: () async {
                                try {
                                  await ApiService.instance.markNotification(
                                    item['id'].toString(),
                                    acknowledge: true,
                                  );
                                  if (mounted) await _refresh();
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text(e.toString())),
                                    );
                                  }
                                }
                              },
                              child: Text(
                                (item['acknowledgedAt']?.toString() ?? '')
                                        .isEmpty
                                    ? 'Conferma ricezione'
                                    : 'Ricezione confermata',
                              ),
                            ),
                          ],
                        ),
                      const SizedBox(height: 10),
                      Text(
                        _time(item['createdAt']),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (taskId.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: () => _openTask(taskId),
                          icon: const Icon(Icons.assignment_outlined),
                          label: const Text('Apri incarico'),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    ),
  );
}
