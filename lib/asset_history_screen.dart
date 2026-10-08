import 'services/italian_labels.dart';
import 'package:flutter/material.dart';
import 'theme/radiotech_glass.dart';

import 'services/api_service.dart';

class AssetHistoryScreen extends StatefulWidget {
  final String assetId;
  final String assetName;
  final Future<List<dynamic>> Function(String assetId)? loadHistory;

  const AssetHistoryScreen({
    required this.assetId,
    required this.assetName,
    this.loadHistory,
    super.key,
  });

  @override
  State<AssetHistoryScreen> createState() => _AssetHistoryScreenState();
}

class _AssetHistoryScreenState extends State<AssetHistoryScreen> {
  late Future<List<dynamic>> _historyFuture;

  @override
  void initState() {
    super.initState();
    _historyFuture = _loadHistory();
  }

  Future<List<dynamic>> _loadHistory() {
    final loader = widget.loadHistory;
    if (loader != null) {
      return Future.sync(() => loader(widget.assetId));
    }
    return ApiService.instance.getAssetHistory(widget.assetId);
  }

  void _reload() {
    setState(() {
      _historyFuture = _loadHistory();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Storia asset'),
        actions: [
          IconButton(
            tooltip: 'Aggiorna',
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<List<dynamic>>(
        future: _historyFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _MessageView(
              icon: Icons.cloud_off_outlined,
              message: 'Impossibile caricare la storia dell’asset.',
              actionLabel: 'Riprova',
              onAction: _reload,
            );
          }

          final records = snapshot.data ?? const <dynamic>[];
          if (records.isEmpty) {
            return _MessageView(
              icon: Icons.history,
              message: 'Nessuna attività registrata per ${widget.assetName}.',
            );
          }

          try {
            final entries = records.map(_recordMap).toList(growable: false);
            return RefreshIndicator(
              onRefresh: () async => _reload(),
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: entries.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 12),
                itemBuilder: (context, index) =>
                    _HistoryCard(record: entries[index]),
              ),
            );
          } on FormatException {
            return const _MessageView(
              icon: Icons.warning_amber_outlined,
              message: 'Il server ha restituito un record storia non valido.',
            );
          }
        },
      ),
    );
  }

  Map<String, dynamic> _recordMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    throw const FormatException('Record storia non valido.');
  }
}

class _HistoryCard extends StatelessWidget {
  final Map<String, dynamic> record;

  const _HistoryCard({required this.record});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final recordType = _text(record['recordType'])?.toUpperCase() ?? 'ATTIVITÀ';
    final title =
        _firstText(record, const [
          'title',
          'taskName',
          'reportTitle',
          'workOrderTitle',
        ]) ??
        (recordType == 'REPORT' ? 'Rapporto di manutenzione' : 'Intervento');
    final status = _firstText(record, const ['status', 'reviewStatus']);
    final timestamp = _dateText(record['timestamp']);
    final summary = _firstText(record, const [
      'summary',
      'description',
      'notes',
    ]);
    final facts = <(String, String)>[
      if (status != null) ('Stato', italianLabel(status)),
      if (_firstText(record, const ['operatorName', 'technicianName'])
          case final value?)
        ('Tecnico', value),
      if (_firstText(record, const ['taskId', 'reportId']) case final value?)
        ('Riferimento', value),
    ];

    return Card(
      color: Colors.transparent,
      child: RadioTechGlass(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  recordType == 'REPORT'
                      ? Icons.assignment_turned_in_outlined
                      : Icons.build_outlined,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(title, style: theme.textTheme.titleMedium),
                ),
                Text(
                  recordType,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.secondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            if (timestamp != null) ...[
              const SizedBox(height: 8),
              Text(timestamp, style: theme.textTheme.bodySmall),
            ],
            if (summary != null) ...[
              const SizedBox(height: 12),
              Text(summary, style: theme.textTheme.bodyMedium),
            ],
            for (final (label, value) in facts) ...[
              const SizedBox(height: 8),
              _FactRow(label: label, value: value),
            ],
          ],
        ),
      ),
    );
  }
}

class _FactRow extends StatelessWidget {
  final String label;
  final String value;

  const _FactRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 92,
          child: Text(label, style: Theme.of(context).textTheme.bodySmall),
        ),
        Expanded(child: Text(value)),
      ],
    );
  }
}

class _MessageView extends StatelessWidget {
  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _MessageView({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 42, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 12),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

String? _firstText(Map<String, dynamic> values, List<String> keys) {
  for (final key in keys) {
    final value = _text(values[key]);
    if (value != null) {
      return value;
    }
  }
  return null;
}

String? _text(dynamic value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

String? _dateText(dynamic value) {
  final text = _text(value);
  if (text == null) return null;
  final date = DateTime.tryParse(text)?.toLocal();
  if (date == null) return text;
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  return '$day/$month/${date.year} $hour:$minute';
}
