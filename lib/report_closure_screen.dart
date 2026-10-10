import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'theme/radiotech_glass.dart';
import 'package:image_picker/image_picker.dart';
import 'package:signature/signature.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'services/api_service.dart';
import 'services/maintenance_report_pdf.dart';
import 'services/app_navigation.dart';
import 'services/auth_service.dart';
import 'services/local_report_attachment_store.dart';
import 'services/report_draft_store.dart';
import 'services/session_service.dart';
import 'services/report_submission_state.dart';
import 'widgets/offline_sync_status_panel.dart';

class ReportClosureScreen extends StatefulWidget {
  final Map<String, bool> checklistResults;
  final String antennaId;
  final String? taskId;
  final String? antennaName;
  final Future<dynamic> Function(
    Map<String, dynamic>,
    List<File>,
    Map<String, Uint8List>,
  )?
  submitReport;
  final Future<dynamic> Function()? resumeReport;
  final Future<Position?> Function()? locate;
  final Future<Map<String, String>> Function()? loadIdentity;
  final Future<List<Map<String, dynamic>>> Function()? loadInventory;

  const ReportClosureScreen({
    required this.checklistResults,
    this.antennaId = 'ANT-987',
    this.taskId,
    this.antennaName,
    this.submitReport,
    this.resumeReport,
    this.locate,
    this.loadIdentity,
    this.loadInventory,
    super.key,
  });

  @override
  State<ReportClosureScreen> createState() => _ReportClosureScreenState();
}

class _ReportClosureScreenState extends State<ReportClosureScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late AnimationController _animationController;
  late final Map<String, bool> _checks;
  final TextEditingController _notesController = TextEditingController();
  final TextEditingController _centralAlertController = TextEditingController();
  final TextEditingController _partSearchController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  late final SignatureController _signatureController;
  final List<XFile> _attachments = [];
  final List<_MeasurementRow> _measurementRows = [];
  final Map<String, int> _partsUsed = {};
  final Map<String, Map<String, dynamic>> _partsCatalog = {};
  bool _inventoryLoading = false;
  String? _inventoryError;
  bool _hasCentralAlert = false;
  bool _isFormValid = false;
  bool _isSubmitting = false;
  bool _restoringDraft = false;
  bool _reportQueued = false;
  String? _queuedKey;
  String? _submissionError;
  String _submissionStage = 'Preparazione del report…';
  late final Future<Map<String, String>> _identityFuture;
  Timer? _draftSaveTimer;
  String? _draftKey;
  final ReportDraftStore _draftStore = ReportDraftStore();
  final LocalReportAttachmentStore _attachmentStore =
      LocalReportAttachmentStore();

  @override
  void initState() {
    super.initState();
    _checks = Map.of(widget.checklistResults);
    WidgetsBinding.instance.addObserver(this);
    _identityFuture = _loadIdentity();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _animationController.forward();
    _signatureController = SignatureController(
      penStrokeWidth: 2,
      penColor: Colors.white,
      exportBackgroundColor: Colors.white,
      exportPenColor: Colors.black,
      onDrawEnd: _scheduleDraftSave,
    );

    _notesController.addListener(_updateFormValidity);
    _centralAlertController.addListener(_updateFormValidity);

    final uid = AuthService.instance.currentUid;
    final tenantId = SessionService.instance.tenantId;
    if (uid != null && tenantId != null) {
      _draftKey = ReportDraftStore.storageKey(
        tenantId: tenantId,
        operatorUid: uid,
        taskScope: widget.taskId ?? widget.antennaId,
      );
      unawaited(_restoreDraft());
      unawaited(_restorePendingSubmission());
    }
    unawaited(_loadInventory());
    unawaited(_loadAntennaChecklist());
  }

  Future<void> _loadAntennaChecklist() async {
    if (widget.antennaId.trim().isEmpty ||
        widget.antennaId == 'GENERICO') return;
    try {
      final antenna = await ApiService.instance.getAntennaDetails(widget.antennaId);
      final raw = antenna['checklist_template'] ?? antenna['checklistTemplate'];
      if (raw is! List || !mounted) return;
      setState(() {
        for (final item in raw) {
          if (item is String && item.trim().isNotEmpty) {
            _checks.putIfAbsent(item.trim(), () => false);
          }
        }
      });
    } catch (_) {
      // Preserve editable report and existing draft when offline.
    }
  }

  void _normalizeLegacyParts() {
    for (final key in _partsUsed.keys.toList()) {
      if (_partsCatalog.containsKey(key)) continue;
      final matches = _partsCatalog.values
          .where(
            (item) =>
                item['name'].toString().trim().toLowerCase() ==
                    key.trim().toLowerCase() ||
                item['sku']?.toString().trim().toLowerCase() ==
                    key.trim().toLowerCase(),
          )
          .toList();
      if (matches.length == 1) {
        final quantity = _partsUsed.remove(key)!;
        final id = matches.single['id'] as String;
        _partsUsed[id] = (_partsUsed[id] ?? 0) + quantity;
      } else if (_partsUsed[key] == 0) {
        _partsUsed.remove(key);
      }
    }
  }

  void _applyInventory(List<Map<String, dynamic>> items) {
    if (!mounted) return;
    setState(() {
      _partsCatalog.clear();
      for (final item in items) {
        final id = item['id']?.toString(), name = item['name']?.toString();
        if (id == null || id.isEmpty || name == null || name.isEmpty) continue;
        _partsCatalog[id] = {...item, 'id': id};
        _partsUsed.putIfAbsent(id, () => 0);
      }
      _normalizeLegacyParts();
    });
  }

  Future<void> _loadInventory() async {
    final uid = AuthService.instance.currentUid;
    final tenant = SessionService.instance.tenantId;
    final cacheKey = uid != null && tenant != null
        ? 'report_inventory_${tenant}_$uid'
        : null;
    SharedPreferences? preferences;
    if (cacheKey != null) {
      preferences = await SharedPreferences.getInstance();
      if (!mounted ||
          uid != AuthService.instance.currentUid ||
          tenant != SessionService.instance.tenantId) {
        return;
      }
      try {
        final cached = preferences.getString(cacheKey);
        if (cached != null) {
          _applyInventory(
            List<Map<String, dynamic>>.from(
              (jsonDecode(cached) as List).map(
                (item) => Map<String, dynamic>.from(item as Map),
              ),
            ),
          );
        }
      } catch (_) {
        /* An invalid cache does not replace the server catalog. */
      }
    }
    if (widget.loadInventory == null && uid == null || !mounted) return;
    setState(() {
      _inventoryLoading = true;
      _inventoryError = null;
    });
    try {
      final items =
          await (widget.loadInventory?.call() ??
                  ApiService.instance.getMyInventory())
              .timeout(const Duration(seconds: 12));
      if (!mounted ||
          uid != AuthService.instance.currentUid ||
          tenant != SessionService.instance.tenantId) {
        return;
      }
      _applyInventory(items);
      if (cacheKey != null && preferences != null) {
        await preferences.setString(cacheKey, jsonEncode(items));
      }
    } catch (_) {
      if (mounted &&
          uid == AuthService.instance.currentUid &&
          tenant == SessionService.instance.tenantId) {
        setState(
          () => _inventoryError = _partsCatalog.isEmpty
              ? 'Magazzino non disponibile. Riprova prima di indicare i pezzi utilizzati.'
              : 'Magazzino offline: sono mostrati gli ultimi articoli caricati.',
        );
      }
    } finally {
      if (mounted) setState(() => _inventoryLoading = false);
    }
  }

  List<Map<String, dynamic>> _materialsForSubmission() {
    return _partsUsed.entries.where((entry) => entry.value > 0).map((entry) {
      final item = _partsCatalog[entry.key];
      if (item == null) {
        throw StateError(
          'Il pezzo «${entry.key}» della bozza non corrisponde al magazzino. Rimuovilo e seleziona l’articolo corretto.',
        );
      }
      return <String, dynamic>{
        'inventoryId': item['id'],
        'sku': item['sku'] ?? '',
        'name': item['name'],
        'quantity': entry.value,
      };
    }).toList();
  }

  Future<Map<String, String>> _loadIdentity() async {
    if (widget.loadIdentity != null) return widget.loadIdentity!();
    var antenna = widget.antennaName ?? 'Nome impianto non disponibile';
    var operator = AuthService.instance.currentUser?.displayName ?? 'Operatore';
    if (AuthService.instance.currentUid != null) {
      await Future.wait([
        () async {
          try {
            final data = await ApiService.instance
                .getAntennaDetails(widget.antennaId)
                .timeout(const Duration(seconds: 8));
            final name = data['name']?.toString().trim();
            if (name != null && name.isNotEmpty) antenna = name;
          } catch (_) {
            /* Keep the supplied name if the server is unavailable. */
          }
        }(),
        () async {
          try {
            final data = await ApiService.instance
                .getMyOperatorProfile()
                .timeout(const Duration(seconds: 8));
            final name = data['fullName']?.toString().trim();
            if (name != null && name.isNotEmpty) operator = name;
          } catch (_) {
            /* Firebase display name is the offline fallback. */
          }
        }(),
      ]);
    }
    return {'antennaName': antenna, 'operatorName': operator};
  }

  void _stage(String label) {
    if (mounted) setState(() => _submissionStage = label);
  }

  Future<void> _restorePendingSubmission() async {
    try {
      final pending = await ApiService.instance.pendingMaintenanceReport(
        taskId: widget.taskId,
        antennaId: widget.antennaId,
      );
      if (mounted && pending != null) {
        setState(() {
          _reportQueued = true;
          _queuedKey = pending.payload['idempotencyKey']?.toString();
        });
      }
    } catch (_) {
      /* The draft stays available if queue or identity cannot be read. */
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _draftSaveTimer?.cancel();
    _animationController.dispose();
    _notesController.dispose();
    _centralAlertController.dispose();
    _partSearchController.dispose();
    for (final row in _measurementRows) {
      row.dispose();
    }
    _signatureController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _draftSaveTimer?.cancel();
      unawaited(_saveDraft());
    }
  }

  void _updateFormValidity() {
    final isValid =
        _notesController.text.trim().isNotEmpty &&
        (!_hasCentralAlert || _centralAlertController.text.trim().isNotEmpty);
    if (mounted && !_restoringDraft && _isFormValid != isValid) {
      setState(() => _isFormValid = isValid);
    } else {
      _isFormValid = isValid;
    }
    _scheduleDraftSave();
  }

  _MeasurementRow _newMeasurementRow({String name = '', String value = ''}) {
    final row = _MeasurementRow(name: name, value: value);
    row.nameController.addListener(_scheduleDraftSave);
    row.valueController.addListener(_scheduleDraftSave);
    return row;
  }

  void _scheduleDraftSave() {
    if (_restoringDraft || _draftKey == null || !mounted) return;
    _draftSaveTimer?.cancel();
    _draftSaveTimer = Timer(const Duration(milliseconds: 400), () {
      unawaited(_saveDraft());
    });
  }

  Future<void> _saveDraft({bool force = false}) async {
    final key = _draftKey;
    if (key == null || _restoringDraft || _isSubmitting && !force) return;

    await _draftStore.save(key, {
      'notes': _notesController.text,
      'checklist': Map<String, bool>.of(_checks),
      'centralAlert': _centralAlertController.text,
      'hasCentralAlert': _hasCentralAlert,
      'parts': Map<String, int>.from(_partsUsed),
      'measurements': _measurementRows
          .map(
            (row) => {
              'name': row.nameController.text,
              'value': row.valueController.text,
            },
          )
          .toList(),
      'signaturePoints': _signatureController.points
          .map(
            (point) => {
              'x': point.offset.dx,
              'y': point.offset.dy,
              'type': point.type.name,
              'pressure': point.pressure,
            },
          )
          .toList(),
      'attachments': _attachments
          .map((file) => {'name': file.name, 'path': file.path})
          .toList(),
    });
  }

  Future<void> _restoreDraft() async {
    final key = _draftKey;
    if (key == null) return;
    final draft = await _draftStore.load(key);
    if (draft == null || !mounted) return;

    _restoringDraft = true;
    if (draft['checklist'] is Map) {
      _checks
        ..clear()
        ..addAll(
          Map<String, dynamic>.from(
            draft['checklist'] as Map,
          ).map((k, v) => MapEntry(k, v == true)),
        );
    }
    _notesController.text = draft['notes']?.toString() ?? '';
    _centralAlertController.text = draft['centralAlert']?.toString() ?? '';
    _hasCentralAlert = draft['hasCentralAlert'] == true;

    final rawParts = draft['parts'];
    if (rawParts is Map) {
      for (final entry in rawParts.entries) {
        if (entry.value is num) {
          _partsUsed[entry.key.toString()] = (entry.value as num).toInt();
        }
      }
    }
    _normalizeLegacyParts();

    final rows = <_MeasurementRow>[];
    final rawMeasurements = draft['measurements'];
    if (rawMeasurements is List) {
      for (final rawRow in rawMeasurements.whereType<Map>()) {
        rows.add(
          _newMeasurementRow(
            name: rawRow['name']?.toString() ?? '',
            value: rawRow['value']?.toString() ?? '',
          ),
        );
      }
    }

    final restoredPoints = <Point>[];
    final rawPoints = draft['signaturePoints'];
    if (rawPoints is List) {
      for (final rawPoint in rawPoints.whereType<Map>()) {
        final x = rawPoint['x'];
        final y = rawPoint['y'];
        final pressure = rawPoint['pressure'];
        if (x is! num || y is! num || pressure is! num) continue;
        final typeName = rawPoint['type']?.toString();
        final type = PointType.values.firstWhere(
          (candidate) => candidate.name == typeName,
          orElse: () => PointType.tap,
        );
        restoredPoints.add(
          Point(Offset(x.toDouble(), y.toDouble()), type, pressure.toDouble()),
        );
      }
    }
    _signatureController.points = restoredPoints;

    final restoredAttachments = <XFile>[];
    final rawAttachments = draft['attachments'];
    if (rawAttachments is List) {
      for (final rawAttachment in rawAttachments.whereType<Map>()) {
        try {
          final file = await _attachmentStore.resolve(
            Map<String, dynamic>.from(rawAttachment),
          );
          restoredAttachments.add(XFile(file.path));
        } on StateError {
          continue;
        }
      }
    }

    if (!mounted) return;
    setState(() {
      _measurementRows.addAll(rows);
      _attachments.addAll(restoredAttachments);
    });
    _restoringDraft = false;
    _updateFormValidity();
  }

  Future<void> _clearDraft() async {
    _draftSaveTimer?.cancel();
    for (final attachment in _attachments) {
      await _attachmentStore.remove([
        {'name': attachment.name, 'path': attachment.path},
      ]);
    }
    final key = _draftKey;
    if (key != null) await _draftStore.delete(key);
  }

  Future<void> _pickAttachment(ImageSource source) async {
    final pickedFile = await _picker.pickImage(
      source: source,
      imageQuality: 75,
      maxWidth: 2000,
      maxHeight: 2000,
    );
    if (pickedFile != null) {
      var savedFile = pickedFile;
      final draftKey = _draftKey;
      if (draftKey != null) {
        final staged = await _attachmentStore.stage(
          requestKey:
              'draft_${draftKey}_${DateTime.now().microsecondsSinceEpoch}',
          files: [File(pickedFile.path)],
        );
        savedFile = XFile(staged.single['path']!);
      }
      setState(() {
        _attachments.add(savedFile);
      });
      _scheduleDraftSave();
    }
  }

  void _updatePartQuantity(String part, int delta) {
    setState(() {
      final current = _partsUsed[part] ?? 0;
      final next = (current + delta).clamp(0, 99);
      _partsUsed[part] = next;
    });
    _scheduleDraftSave();
  }

  void _toggleCentralAlert(bool value) {
    setState(() {
      _hasCentralAlert = value;
      if (!value) {
        _centralAlertController.clear();
      }
      _updateFormValidity();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Chiusura intervento',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        backgroundColor: const Color(0xF210111A),
      ),
      bottomNavigationBar: _buildActionBar(context),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 920),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildFormHeader(context),
                      const SizedBox(height: 16),
                      if (_isSubmitting) ...[
                        const LinearProgressIndicator(),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            _submissionStage,
                            key: const ValueKey('report-send-progress'),
                          ),
                        ),
                      ],
                      if (_reportQueued)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: _submissionNotice(
                            context,
                            'Salvato sul telefono',
                            'La centrale non ha ancora confermato la ricezione. Riprova invio riprende il report originale e i suoi allegati; i campi restano protetti fino alla conferma.',
                            Icons.cloud_upload_outlined,
                          ),
                        ),
                      if (_submissionError != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: _submissionNotice(
                            context,
                            'Invio da verificare',
                            _submissionError!,
                            Icons.error_outline,
                          ),
                        ),
                      const OfflineSyncStatusPanel(),
                      AbsorbPointer(
                        absorbing: _isSubmitting || _reportQueued,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _reportSection(
                              context,
                              'CONTROLLI ESEGUITI',
                              Icons.fact_check_outlined,
                              _buildChecklistSummary(context),
                            ),
                            _reportSection(
                              context,
                              'NOTE OPERATIVE',
                              Icons.edit_note,
                              _buildAnimatedTextField(context),
                              subtitle:
                                  'Descrivi il lavoro effettuato e l’esito dell’intervento. Campo obbligatorio.',
                            ),
                            _reportSection(
                              context,
                              'ALLEGATI FOTO',
                              Icons.photo_camera_outlined,
                              Column(
                                children: [
                                  _buildAttachmentButtons(context),
                                  const SizedBox(height: 12),
                                  _buildAttachmentPreview(context),
                                ],
                              ),
                            ),
                            _reportSection(
                              context,
                              'MISURE TECNICHE',
                              Icons.monitor_heart_outlined,
                              _buildMeasurements(context),
                              subtitle:
                                  'Indica parametro, unità e valore misurato.',
                            ),
                            _reportSection(
                              context,
                              'PEZZI SOSTITUITI',
                              Icons.inventory_2_outlined,
                              _buildPartsGrid(context),
                            ),
                            _reportSection(
                              context,
                              'CENTRALE OPERATIVA',
                              Icons.notification_important_outlined,
                              Column(
                                children: [
                                  _buildCentralAlertToggle(context),
                                  if (_hasCentralAlert) ...[
                                    const SizedBox(height: 14),
                                    _buildCentralAlertField(context),
                                  ],
                                ],
                              ),
                            ),
                            _reportSection(
                              context,
                              'FIRMA',
                              Icons.draw_outlined,
                              _buildSignatureSection(context),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _reportSection(
    BuildContext context,
    String title,
    IconData icon,
    Widget child, {
    String? subtitle,
  }) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: RadioTechGlass(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                icon,
                color: Theme.of(context).colorScheme.primary,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(child: _buildSectionTitle(context, title)),
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: const TextStyle(color: Color(0xFFAAAAB4), height: 1.5),
            ),
          ],
          const SizedBox(height: 16),
          child,
        ],
      ),
    ),
  );

  Widget _submissionNotice(
    BuildContext context,
    String title,
    String message,
    IconData icon,
  ) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0x33452324),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFF55515F)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(message, style: const TextStyle(height: 1.5)),
            ],
          ),
        ),
      ],
    ),
  );
  Widget _buildChecklistSummary(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.assignment_turned_in,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Lista di controllo (${_checks.length})',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ..._checks.entries.map(
            (entry) => AnimatedContainer(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 180),
              decoration: BoxDecoration(
                color: entry.value
                    ? Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: .06)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Material(
                color: Colors.transparent,
                child: CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(entry.key),
                  value: entry.value,
                  onChanged: _isSubmitting || _reportQueued
                      ? null
                      : (value) {
                          setState(() => _checks[entry.key] = value ?? false);
                          _scheduleDraftSave();
                        },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return FadeTransition(
      opacity: _animationController,
      child: Text(
        title,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.5,
        ),
      ),
    );
  }

  Widget _buildFormHeader(BuildContext context) {
    final completeCount = _checks.values.where((v) => v).length;
    final hasAlerts = _hasCentralAlert;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.task_alt,
              color: Theme.of(context).colorScheme.primary,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'REPORT DI CHIUSURA',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Controlli superati: $completeCount/${_checks.length}. Allegati, pezzi sostituiti e alert centrali saranno inclusi nel PDF.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildStatusBadge(
                      context,
                      'ALLEGATI: ${_attachments.length}',
                    ),
                    _buildStatusBadge(
                      context,
                      'PEZZI: ${_partsUsed.values.fold(0, (sum, v) => sum + v)}',
                    ),
                    _buildStatusBadge(
                      context,
                      hasAlerts
                          ? 'Segnalazione attiva'
                          : 'Nessuna segnalazione',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(BuildContext context, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildAnimatedTextField(BuildContext context) {
    return SlideTransition(
      position: Tween<Offset>(begin: const Offset(0.3, 0), end: Offset.zero)
          .animate(
            CurvedAnimation(
              parent: _animationController,
              curve: const Interval(0.2, 0.8, curve: Curves.easeOut),
            ),
          ),
      child: TextField(
        key: const ValueKey('report-notes'),
        controller: _notesController,
        maxLines: 5,
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: InputDecoration(
          filled: true,
          fillColor: Theme.of(
            context,
          ).colorScheme.surfaceContainer.withValues(alpha: 0.8),
          hintText:
              'Inserisci dettagli, pezzi sostituiti, anomalie rilevate...',
          hintStyle: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 14,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(
              color: Colors.white.withValues(alpha: 0.1),
              width: 1.5,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(
              color: Theme.of(context).colorScheme.primary,
              width: 2,
            ),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 16,
          ),
        ),
      ),
    );
  }

  Widget _buildAttachmentButtons(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final width = bounds.maxWidth < 420
          ? bounds.maxWidth
          : (bounds.maxWidth - 12) / 2;
      return Wrap(
        spacing: 12,
        runSpacing: 10,
        children: [
          SizedBox(
            width: width,
            child: OutlinedButton.icon(
              onPressed: () => _pickAttachment(ImageSource.camera),
              icon: const Icon(Icons.camera_alt_outlined),
              label: const Text('Scatta una foto'),
            ),
          ),
          SizedBox(
            width: width,
            child: OutlinedButton.icon(
              onPressed: () => _pickAttachment(ImageSource.gallery),
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Scegli dalla galleria'),
            ),
          ),
        ],
      );
    },
  );
  Widget _buildMeasurements(BuildContext context) {
    return Column(
      children: [
        ..._measurementRows.asMap().entries.map((entry) {
          final index = entry.key;
          final row = entry.value;
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: LayoutBuilder(
              builder: (context, bounds) {
                final name = TextField(
                  key: ValueKey('measurement-name-$index'),
                  controller: row.nameController,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Parametro e unità',
                    hintText: 'Es. Potenza RX (dBm)',
                  ),
                );
                final value = TextField(
                  key: ValueKey('measurement-value-$index'),
                  controller: row.valueController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  decoration: const InputDecoration(labelText: 'Valore'),
                );
                final remove = IconButton(
                  tooltip: 'Rimuovi misura',
                  onPressed: () {
                    setState(() => _measurementRows.removeAt(index).dispose());
                    _scheduleDraftSave();
                  },
                  icon: const Icon(Icons.remove_circle_outline),
                );
                if (bounds.maxWidth < 420 ||
                    MediaQuery.textScalerOf(context).scale(1) > 1.3) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      name,
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: value),
                          const SizedBox(width: 8),
                          remove,
                        ],
                      ),
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: name),
                    const SizedBox(width: 12),
                    Expanded(flex: 2, child: value),
                    remove,
                  ],
                );
              },
            ),
          );
        }),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () {
              setState(() => _measurementRows.add(_newMeasurementRow()));
              _scheduleDraftSave();
            },
            icon: const Icon(Icons.add),
            label: const Text('Aggiungi misura'),
          ),
        ),
      ],
    );
  }

  Map<String, double> _readMeasurements() {
    final measurements = <String, double>{};
    final normalizedNames = <String>{};
    for (final row in _measurementRows) {
      final name = row.nameController.text.trim();
      final rawValue = row.valueController.text.trim();
      if (name.isEmpty && rawValue.isEmpty) continue;
      if (name.isEmpty || rawValue.isEmpty) {
        throw StateError('Parametro e valore della misura sono obbligatori.');
      }
      final value = double.tryParse(rawValue.replaceAll(',', '.'));
      if (value == null || !value.isFinite) {
        throw StateError(
          'Il valore della misura deve essere un numero valido.',
        );
      }
      if (!normalizedNames.add(name.toLowerCase())) {
        throw StateError('Il parametro "$name" è stato inserito più volte.');
      }
      measurements[name] = value;
    }
    return measurements;
  }

  Widget _buildAttachmentPreview(BuildContext context) {
    if (_attachments.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.08),
            width: 1.5,
          ),
        ),
        child: Text(
          'Nessuna immagine allegata. Aggiungi foto per documentare il guasto.',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 14,
          ),
        ),
      );
    }

    return SizedBox(
      height: 110,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _attachments.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final attachment = _attachments[index];
          return Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.file(
                  File(attachment.path),
                  width: 110,
                  height: 110,
                  fit: BoxFit.cover,
                ),
              ),
              Positioned(
                right: 6,
                top: 6,
                child: GestureDetector(
                  onTap: () {
                    final removed = _attachments[index];
                    setState(() {
                      _attachments.removeAt(index);
                    });
                    unawaited(
                      _attachmentStore.remove([
                        {'name': removed.name, 'path': removed.path},
                      ]),
                    );
                    _scheduleDraftSave();
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black.withValues(alpha: 0.55),
                    ),
                    padding: const EdgeInsets.all(6),
                    child: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPartsGrid(BuildContext context) {
    final query = _partSearchController.text.trim().toLowerCase();
    final rows = _partsUsed.entries.where((entry) {
      final item = _partsCatalog[entry.key];
      return query.isEmpty ||
          '${item?['name'] ?? entry.key} ${item?['sku'] ?? ''}'
              .toLowerCase()
              .contains(query);
    });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_inventoryLoading) const LinearProgressIndicator(),
        if (_inventoryError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              _inventoryError!,
              style: const TextStyle(color: Color(0xFFAAAAB4)),
            ),
          ),
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('report-material-search'),
                controller: _partSearchController,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Cerca nel magazzino',
                  hintText: 'Nome o codice articolo',
                ),
              ),
            ),
            IconButton(
              onPressed: _inventoryLoading ? null : _loadInventory,
              tooltip: 'Aggiorna magazzino',
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (rows.isEmpty)
          const Text(
            'Nessun articolo disponibile. Puoi aggiornare il magazzino o inviare il report senza prelievi.',
          ),
        ...rows.map((entry) {
          final item = _partsCatalog[entry.key];
          final name = item?['name']?.toString() ?? entry.key;
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainer,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          item == null
                              ? 'Pezzo della vecchia bozza: seleziona l’articolo corretto'
                              : '${item['sku'] ?? ''} · disponibili: ${item['quantity'] ?? '—'} ${item['unit'] ?? ''}',
                          style: const TextStyle(
                            color: Color(0xFFAAAAB4),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    key: ValueKey('material-decrease-${entry.key}'),
                    onPressed: () => _updatePartQuantity(entry.key, -1),
                    tooltip: 'Riduci $name',
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  Text(
                    entry.value.toString(),
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                  ),
                  IconButton(
                    key: ValueKey('material-increase-${entry.key}'),
                    onPressed: item == null
                        ? null
                        : () => _updatePartQuantity(entry.key, 1),
                    tooltip: 'Aumenta $name',
                    icon: const Icon(Icons.add_circle_outline),
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildCentralAlertToggle(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 1.5,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              'Invia segnalazione alla centrale operativa',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 14,
              ),
            ),
          ),
          Switch(
            value: _hasCentralAlert,
            activeThumbColor: Theme.of(context).colorScheme.secondary,
            onChanged: _toggleCentralAlert,
          ),
        ],
      ),
    );
  }

  Widget _buildCentralAlertField(BuildContext context) {
    return TextField(
      controller: _centralAlertController,
      maxLines: 3,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        filled: true,
        fillColor: Theme.of(
          context,
        ).colorScheme.surfaceContainer.withValues(alpha: 0.8),
        hintText: 'Dettaglia la segnalazione per la centrale operativa...',
        hintStyle: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontSize: 14,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: Colors.white.withValues(alpha: 0.1),
            width: 1.5,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: Theme.of(context).colorScheme.primary,
            width: 2,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 16,
        ),
      ),
    );
  }

  Widget _buildSignatureSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(context, 'FIRMA OPERATORE'),
        const SizedBox(height: 12),
        Container(
          height: 150,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Signature(
              controller: _signatureController,
              backgroundColor: Colors.transparent,
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () {
              _signatureController.clear();
              _scheduleDraftSave();
            },
            icon: const Icon(Icons.clear),
            label: const Text('Pulisci firma'),
          ),
        ),
      ],
    );
  }

  Widget _buildActionBar(BuildContext context) => Material(
    color: const Color(0xFF191A24),
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: LayoutBuilder(
          builder: (context, bounds) {
            final buttons = [
              OutlinedButton(
                onPressed: _isSubmitting
                    ? null
                    : () => Navigator.of(context).pop(),
                child: const Text('Torna all’intervento'),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  disabledBackgroundColor: const Color(0xFF282832),
                  disabledForegroundColor: const Color(0xFFC5C5D0),
                ),
                key: const ValueKey('submit-report'),
                onPressed: !_isSubmitting && (_isFormValid || _reportQueued)
                    ? _submitReport
                    : null,
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFFC5C5D0),
                        ),
                      )
                    : Icon(
                        _reportQueued
                            ? Icons.cloud_sync_outlined
                            : Icons.send_outlined,
                      ),
                label: Text(
                  _isSubmitting
                      ? 'Invio in corso…'
                      : _reportQueued
                      ? 'Riprova invio'
                      : 'Invia report',
                ),
              ),
            ];
            if (bounds.maxWidth < 420 ||
                MediaQuery.textScalerOf(context).scale(1) > 1.3) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [buttons[1], const SizedBox(height: 6), buttons[0]],
              );
            }
            return Row(
              children: [
                Expanded(child: buttons[0]),
                const SizedBox(width: 12),
                Expanded(child: buttons[1]),
              ],
            );
          },
        ),
      ),
    ),
  );
  Future<void> _submitReport() async {
    if (_isSubmitting || !_isFormValid && !_reportQueued) return;
    setState(() => _isSubmitting = true);
    try {
      FocusScope.of(context).unfocus();
      setState(() => _submissionError = null);
      _draftSaveTimer?.cancel();
      await _saveDraft(force: true);
      _stage('Verifica di eventuali invii precedenti…');
      final resumed = widget.resumeReport != null
          ? await widget.resumeReport!()
          : await ApiService.instance.resumeMaintenanceReport(
              taskId: widget.taskId,
              antennaId: widget.antennaId,
              requestKey: _queuedKey,
            );
      if (resumed != null) {
        await _clearDraft();
        if (mounted) {
          await _showSuccessDialog(resumed);
        }
        return;
      }
      if (_reportQueued) {
        throw StateError(
          'Il report in coda non è più disponibile. Controlla i report inviati prima di creare una nuova submission.',
        );
      }
      final materials = _materialsForSubmission();
      _stage('Verifica della posizione GPS…');
      final location = await (widget.locate ?? _currentLocation)();
      if (widget.taskId != null && location == null) {
        throw StateError(
          'La posizione GPS è obbligatoria per chiudere il task. Verifica i permessi e riprova.',
        );
      }
      final attachmentBytes = <String, Uint8List>{};
      final signatureBytes = await _signatureController.toPngBytes();
      if (signatureBytes != null && signatureBytes.isNotEmpty) {
        attachmentBytes['signature_${DateTime.now().microsecondsSinceEpoch}.png'] =
            signatureBytes;
      }

      final measurements = _readMeasurements();

      final submittedAt = DateTime.now();
      final report = <String, dynamic>{
        'antennaId': widget.antennaId,
        'checklist': _checks,
        'description': _notesController.text.trim(),
        'workPerformed': _notesController.text.trim(),
        'findings': _hasCentralAlert ? _centralAlertController.text.trim() : '',
        'operatorNotes': _notesController.text.trim(),
        'materialsUsed': materials,
        'measurements': measurements,
        'attachments': <String>[],
        'completedAt': submittedAt.toUtc().toIso8601String(),
      };

      if (location != null) {
        report['latitude'] = location.latitude;
        report['longitude'] = location.longitude;
      }

      _stage('Generazione del PDF con foto e firma…');
      final identity = await _identityFuture;
      final photos = <ReportPhoto>[];
      for (final attachment in _attachments) {
        photos.add(
          ReportPhoto(attachment.name, await attachment.readAsBytes()),
        );
      }
      final pdfBytes = await MaintenanceReportPdf.build(
        antennaId: widget.antennaId,
        antennaName: identity['antennaName']!,
        operatorName: identity['operatorName']!,
        submittedAt: submittedAt,
        taskId: widget.taskId,
        notes: _notesController.text.trim(),
        findings: _hasCentralAlert ? _centralAlertController.text.trim() : '',
        checklist: _checks,
        materials: materials,
        measurements: measurements,
        photos: photos,
        signature: signatureBytes,
      );
      attachmentBytes['report_${DateTime.now().microsecondsSinceEpoch}.pdf'] =
          pdfBytes;

      if (_hasCentralAlert) {
        _stage('Invio comunicazione urgente alla centrale…');
        await ApiService.instance.sendCentralUrgentSignal(
          description: _centralAlertController.text,
          assetId: widget.antennaId,
          taskId: widget.taskId,
        );
      }

      _stage('Caricamento allegati e invio alla centrale…');
      final submission = widget.submitReport != null
          ? await widget.submitReport!(
              report,
              _attachments.map((a) => File(a.path)).toList(),
              attachmentBytes,
            )
          : await ApiService.instance.submitMaintenanceReport(
              taskId: widget.taskId,
              report: report,
              attachmentFiles: _attachments
                  .map((attachment) => File(attachment.path))
                  .toList(),
              attachmentBytes: attachmentBytes,
            );
      await _clearDraft();

      if (!mounted) return;
      await _showSuccessDialog(submission);
    } catch (error) {
      if (!mounted) return;
      if (error is ReportQueuedException) {
        await _restorePendingSubmission();
        if (!mounted) return;
        setState(() => _submissionError = null);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
        return;
      }
      setState(
        () => _submissionError = error
            .toString()
            .replaceFirst('Exception: ', '')
            .replaceFirst('Bad state: ', ''),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Invio report non riuscito: $error')),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<Position?> _currentLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }
    return Geolocator.getCurrentPosition().timeout(const Duration(seconds: 20));
  }

  Future<void> _showSuccessDialog(dynamic result) async {
    if (mounted) setState(() => _isSubmitting = false);
    AppNavigation.refreshTasks();
    final report = result is Map ? result['report'] : null;
    final id = report is Map ? report['id']?.toString() : null;
    final receivedAt = report is Map
        ? DateTime.tryParse(report['submittedAt']?.toString() ?? '')
        : null;
    final verification = result is Map
        ? result['verificationUrl']?.toString()
        : null;
    // A standard dialog needs no route animation controller to display its content.
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        key: const ValueKey('report-send-success'),
        scrollable: true,
        icon: const Icon(Icons.cloud_done_outlined, size: 40),
        title: const Text('Report inviato'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'La centrale ha confermato la ricezione del report e degli allegati. Il report è in attesa di revisione.',
            ),
            if (id != null) ...[
              const SizedBox(height: 12),
              Text('Riferimento: $id'),
            ],
            if (receivedAt != null) ...[
              const SizedBox(height: 8),
              Text('Ricevuto: ${receivedAt.toLocal()}'),
            ],
            if (verification != null && verification.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('Verifica integrità del report'),
              SelectableText(
                verification,
                style: Theme.of(dialogContext).textTheme.bodySmall,
              ),
            ],
          ],
        ),
        actions: [
          FilledButton(
            key: const ValueKey('close-report-success'),
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Torna agli incarichi'),
          ),
        ],
      ),
    );
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop(result);
    }
  }
}

class _MeasurementRow {
  _MeasurementRow({String name = '', String value = ''})
    : nameController = TextEditingController(text: name),
      valueController = TextEditingController(text: value);

  final TextEditingController nameController;
  final TextEditingController valueController;

  void dispose() {
    nameController.dispose();
    valueController.dispose();
  }
}
