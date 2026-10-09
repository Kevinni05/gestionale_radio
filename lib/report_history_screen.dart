import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:printing/printing.dart';
import 'services/company_api.dart';
import 'services/report_document_service.dart';
import 'theme/radiotech_glass.dart';
import 'theme/radiotech_content.dart';
import 'ai_hub_screen.dart' show CompanyRequest;
import 'models/task_summary.dart';
import 'services/app_navigation.dart';
import 'services/app_branding.dart';

class OperatorHistoryScreen extends StatefulWidget {
  const OperatorHistoryScreen({
    super.key,
    this.request,
    this.loadPdf,
    this.savePdf,
  });
  final CompanyRequest? request;
  final Future<Uint8List> Function(Map)? loadPdf;
  final Future<bool> Function(Uint8List, String)? savePdf;
  @override
  State<OperatorHistoryScreen> createState() => _OperatorHistoryScreenState();
}

class _OperatorHistoryScreenState extends State<OperatorHistoryScreen>
    with WidgetsBindingObserver {
  late Future<List<Map>> _reports = _load();
  final _search = TextEditingController();
  final _documents = <String, Future<Uint8List>>{};
  final _busy = <String>{};
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AppNavigation.tasksRevision.addListener(_refreshHistory);
  }

  void _refreshHistory() {
    if (mounted) _reload();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshHistory();
  }

  Future<List<Map>> _load() async {
    final request = widget.request ?? CompanyApi.instance.request;
    Future<dynamic> loadTasks() async {
      try {
        return await request('/operator/me/tasks');
      } catch (_) {
        return <dynamic>[];
      }
    }

    final results = await Future.wait([
      request('/operator/me/reports'),
      // Reports remain accessible even when the supplementary task lookup fails.
      loadTasks(),
    ]);
    dynamic unwrap(dynamic v) => v is Map ? v['data'] : v;
    final tasks = {
      for (final t in (unwrap(results[1]) as List? ?? []).cast<Map>())
        t['id'].toString(): t,
    };
    final records = <String, Map>{};
    final reports = (unwrap(results[0]) as List? ?? []).cast<Map>().toList()
      ..sort((a, b) => _time(b).compareTo(_time(a)));
    for (final report in reports) {
      final task = tasks[report['taskId']?.toString()];
      final record = <String, dynamic>{
        ...report,
        'taskTitle':
            report['taskTitle'] ??
            task?['title'] ??
            'Intervento senza compito assegnato',
        'antennaName': report['antennaName'] ?? task?['antennaName'],
        'completedAt': report['completedAt'] ?? task?['completedAt'],
        'updatedAt': report['updatedAt'] ?? task?['updatedAt'],
      };
      records.putIfAbsent(_id(record), () => record);
    }
    for (final task in tasks.values) {
      if (!const {
        'COMPLETED',
        'CLOSED',
        'APPROVED',
        'REPORT_SUBMITTED',
      }.contains(TaskSummary(Map<String, dynamic>.from(task)).status)) {
        continue;
      }
      records.putIfAbsent(
        task['id'].toString(),
        () => {
          ...task,
          'taskId': task['id'],
          'taskTitle': task['title'] ?? 'Intervento',
          'operatorNotes': task['description'],
          'submittedAt': task['completedAt'] ?? task['updatedAt'],
          'attachments': [],
        },
      );
    }
    return records.values.toList()
      ..sort((a, b) => _time(b).compareTo(_time(a)));
  }

  static String _id(Map record) {
    final taskId = record['taskId']?.toString().trim();
    return taskId != null && taskId.isNotEmpty
        ? taskId
        : record['id'].toString();
  }

  static String _time(Map r) =>
      '${r['submittedAt'] ?? r['completedAt'] ?? r['updatedAt'] ?? r['createdAt'] ?? ''}';
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AppNavigation.tasksRevision.removeListener(_refreshHistory);
    _search.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    _documents.clear();
    final future = _load();
    setState(() {
      _reports = future;
    });
    try {
      await _reports;
    } catch (_) {
      /* FutureBuilder displays the failure. */
    }
  }

  Future<void> _document(Map r, {required bool download}) async {
    final id = _id(r);
    if (_busy.contains(id)) return;
    setState(() => _busy.add(id));
    try {
      final bytes = await _documents.putIfAbsent(
        id,
        () => (widget.loadPdf ?? ReportDocumentService.summary)(r),
      );
      if (!mounted) return;
      if (download) {
        final saved = await (widget.savePdf ?? ReportDocumentService.save)(
          bytes,
          ReportDocumentService.filename(r),
        );
        if (mounted && saved) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('PDF salvato nella posizione scelta.'),
            ),
          );
        }
      } else {
        await Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => Scaffold(
              appBar: AppBar(title: const Text('PDF riepilogativo')),
              body: PdfPreview(
                build: (_) async => bytes,
                pdfFileName: ReportDocumentService.filename(r),
                canChangeOrientation: false,
                canChangePageFormat: false,
                allowPrinting: true,
                allowSharing: true,
              ),
            ),
          ),
        );
      }
    } catch (_) {
      _documents.remove(id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'PDF non disponibile. Verifica la connessione e riprova.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Storico interventi'),
      actions: [
        IconButton(
          onPressed: _reload,
          tooltip: 'Aggiorna storico',
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: RadioTechContent(
      child: FutureBuilder<List<Map>>(
        future: _reports,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: FilledButton(
                  onPressed: _reload,
                  child: const Text('Caricamento non riuscito. Riprova'),
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final all = snapshot.data!;
          final list = all
              .where(
                (r) =>
                    '${r['taskTitle']} ${r['antennaName']} ${r['operatorNotes']} ${r['operatorName']}'
                        .toLowerCase()
                        .contains(_search.text.toLowerCase()),
              )
              .toList();
          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                Text(
                  '${all.length} interventi registrati',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Consulta il riepilogo e salva il solo PDF dell’intervento.',
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Cerca compito, impianto o note',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
                const SizedBox(height: 20),
                if (list.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Nessun intervento corrisponde alla ricerca.'),
                  ),
                for (final r in list)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: RadioTechGlass(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.assignment_turned_in_outlined,
                                size: 24,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  '${r['taskTitle']}',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Wrap(
                            spacing: 12,
                            runSpacing: 8,
                            children: [
                              Text(
                                _status(r['status']),
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(_date(_time(r))),
                            ],
                          ),
                          if (r['antennaName'] != null) ...[
                            const SizedBox(height: 8),
                            Text('Impianto: ${r['antennaName']}'),
                          ],
                          const SizedBox(height: 12),
                          Text(
                            '${r['operatorNotes'] ?? r['description'] ?? 'Nessuna nota disponibile'}',
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 18),
                          OutlinedButton.icon(
                            onPressed: _busy.contains(_id(r))
                                ? null
                                : () => _document(r, download: false),
                            icon: const Icon(Icons.picture_as_pdf_outlined),
                            label: const Text('Apri PDF riepilogativo'),
                          ),
                          const SizedBox(height: 10),
                          FilledButton.icon(
                            key: ValueKey('download-${_id(r)}'),
                            onPressed: _busy.contains(_id(r))
                                ? null
                                : () => _document(r, download: true),
                            icon: const Icon(Icons.download_rounded),
                            label: Text(
                              _busy.contains(_id(r))
                                  ? 'Preparazione PDF…'
                                  : 'Scarica PDF',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    ),
  );
  static String _status(dynamic v) =>
      const {
        'SUBMITTED': 'Da revisionare',
        'APPROVED': 'Approvato',
        'REJECTED': 'Rifiutato',
        'COMPLETED': 'Completato',
        'REPORT_SUBMITTED': 'Report inviato',
        'CLOSED': 'Chiuso',
      }[v] ??
      'Registrato';
  static String _date(dynamic v) {
    final d = DateTime.tryParse('$v')?.toLocal();
    return d == null
        ? 'Data non disponibile'
        : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} · ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }
}

class ReportFileScreen extends StatefulWidget {
  final String reference;
  const ReportFileScreen({required this.reference, super.key});
  @override
  State<ReportFileScreen> createState() => _ReportFileScreenState();
}

class _ReportFileScreenState extends State<ReportFileScreen> {
  late Future<Uint8List> _data = _read();
  Future<Uint8List> _read() async {
    final ref = widget.reference;
    if (RegExp(r'^radiotech-file:[a-f0-9]{64}$').hasMatch(ref)) {
      final result = await CompanyApi.instance.request(
        '/files/${ref.substring(15)}',
      );
      return base64Decode(result['base64'] as String);
    }
    final uri = Uri.tryParse(ref);
    if (uri?.scheme != 'https' ||
        uri?.host != 'firebasestorage.googleapis.com') {
      throw StateError('Riferimento allegato non consentito.');
    }
    final data = await FirebaseStorage.instance
        .refFromURL(ref)
        .getData(10 * 1024 * 1024);
    if (data == null) throw StateError('Allegato non disponibile.');
    return data;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Allegato del report')),
    body: FutureBuilder<Uint8List>(
      future: _data,
      builder: (context, s) {
        if (s.hasError) {
          return Center(
            child: FilledButton(
              onPressed: () => setState(() => _data = _read()),
              child: const Text('Allegato non disponibile. Riprova'),
            ),
          );
        }
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        final bytes = s.data!;
        if (bytes.length >= 5 &&
            ascii.decode(bytes.sublist(0, 5), allowInvalid: true) == '%PDF-') {
          return PdfPreview(
            build: (_) async => bytes,
            canChangeOrientation: false,
            canChangePageFormat: false,
            pdfFileName: 'Report-${AppBranding.assetPrefix}.pdf',
          );
        }
        return InteractiveViewer(
          child: Center(
            child: Image.memory(
              bytes,
              errorBuilder: (_, _, _) => const Text(
                'Formato non visualizzabile. Apri il PDF completo del report.',
              ),
            ),
          ),
        );
      },
    ),
  );
}
