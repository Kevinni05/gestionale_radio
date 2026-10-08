import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:firebase_storage/firebase_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_service.dart';
import 'api_endpoint.dart';
import 'api_http_client.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'local_report_attachment_store.dart';
import 'offline_sync_service.dart';
import 'report_submission_state.dart';
import 'report_draft_store.dart';

class ApiService {
  ApiService._();

  static final ApiService instance = ApiService._();
  static final LocalReportAttachmentStore _reportAttachmentStore =
      LocalReportAttachmentStore();
  static const _baseUrlKey = 'api_base_url';

  // Android emulator:
  // http://10.0.2.2:8080
  //
  // Telefono fisico via USB:
  // usa l'IP del PC nella rete locale, ad esempio:
  // http://192.168.1.100:8080
  static String _baseUrl = const String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8080',
  );

  static String get baseUrl => _baseUrl;
  static final _client = ApiHttpClient.instance;

  static String apiV1Url(String path) {
    final normalized = path.startsWith('/') ? path : '/$path';
    return '$_baseUrl/api/v1$normalized';
  }

  static Future<void> initializeEndpoint() async {
    final preferences = await SharedPreferences.getInstance();
    final savedUrl = preferences.getString(_baseUrlKey);
    if (!kReleaseMode && savedUrl != null && savedUrl.trim().isNotEmpty) {
      _baseUrl = _normalizeBaseUrl(savedUrl);
    }
    _baseUrl = _normalizeBaseUrl(_baseUrl);
  }

  static Future<void> initialize() async {
    await initializeEndpoint();
    await OfflineSyncService.instance.start(
      executor: instance._flushQueuedAction,
    );
  }

  static set baseUrl(String url) {
    if (kReleaseMode) {
      throw StateError('Il server di produzione è configurato al rilascio.');
    }
    _baseUrl = _normalizeBaseUrl(url);
    unawaited(_persistBaseUrl(_baseUrl));
  }

  static String _normalizeBaseUrl(String url) {
    return ApiEndpoint.normalize(url);
  }

  static Future<void> _persistBaseUrl(String url) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_baseUrlKey, url);
  }

  Future<Map<String, String>> get _headers async {
    final token = await AuthService.instance.requireIdToken();
    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
  }

  dynamic _data(http.Response response) {
    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic> && decoded['data'] != null) {
      return decoded['data'];
    }
    return decoded;
  }

  Future<dynamic> proRequest(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
  }) async {
    final request = http.Request(method, Uri.parse(apiV1Url('/pro/$path')))
      ..headers.addAll(await _headers);
    if (body != null) request.body = jsonEncode(body);
    final response = await http.Response.fromStream(
      await _client.send(request),
    );
    _check(response, 'Operazione Enterprise Pro non riuscita.');
    return _data(response);
  }

  Future<void> markNotification(String id, {bool acknowledge = false}) async {
    final response = await _client.post(
      Uri.parse(
        apiV1Url(
          '/operator/me/notifications/${Uri.encodeComponent(id)}/${acknowledge ? 'acknowledge' : 'read'}',
        ),
      ),
      headers: await _headers,
    );
    _check(response, 'Conferma della notifica non riuscita.');
  }

  Future<void> bindDeviceSession(String tenant, String uid) async {
    const storage = FlutterSecureStorage();
    final key = 'device_${base64Url.encode(utf8.encode('$tenant:$uid'))}';
    var installation = await storage.read(key: key);
    if (installation == null) {
      final random = math.Random.secure();
      installation = List.generate(
        16,
        (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      await storage.write(key: key, value: installation);
    }
    final response = await _client.post(
      Uri.parse(apiV1Url('/session/devices')),
      headers: await _headers,
      body: jsonEncode({
        'installationId': installation,
        'platform': defaultTargetPlatform.name,
      }),
    );
    _check(
      response,
      'Registrazione dispositivo non riuscita. Accedi nuovamente.',
    );
    await AuthService.instance.signInDeviceToken(
      (_data(response) as Map)['customToken'] as String,
    );
  }

  void _check(http.Response response, String message) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      dynamic decoded;
      try {
        decoded = jsonDecode(response.body);
      } catch (_) {
        decoded = null;
      }
      final serverMessage = decoded is Map ? decoded['message'] : null;
      if (response.statusCode == 408 ||
          response.statusCode == 425 ||
          response.statusCode == 429 ||
          response.statusCode >= 500) {
        throw _RetryableApiException(serverMessage?.toString() ?? message);
      }
      final errorMessage = serverMessage?.toString() ?? message;
      if (response.statusCode == 409) {
        throw SyncConflictException(errorMessage);
      }
      if (response.statusCode >= 400 && response.statusCode < 500) {
        throw PermanentSyncFailure(errorMessage);
      }
      throw Exception(errorMessage);
    }
  }

  String _newIdempotencyKey() {
    final random = math.Random.secure();
    final entropy = List<int>.generate(16, (_) => random.nextInt(256));
    return entropy.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }

  String _apiV1(String path) => apiV1Url(path);

  Future<List<dynamic>> getTasks() async {
    final response = await _client.get(
      Uri.parse(_apiV1('/tasks')),
      headers: await _headers,
    );
    _check(response, 'Errore caricamento task.');
    return _data(response) as List<dynamic>;
  }

  Future<List<Map<String, dynamic>>> getMyTasks() async {
    final response = await _client.get(
      Uri.parse(_apiV1('/operator/me/tasks')),
      headers: await _headers,
    );
    _check(response, 'Impossibile caricare gli incarichi.');
    return List<Map<String, dynamic>>.from(
      (_data(response) as List).map(
        (item) => Map<String, dynamic>.from(item as Map),
      ),
    );
  }

  Future<List<Map<String, dynamic>>> getMyNotifications() async {
    final response = await _client.get(
      Uri.parse(_apiV1('/operator/me/notifications')),
      headers: await _headers,
    );
    _check(response, 'Impossibile caricare le notifiche.');
    return List<Map<String, dynamic>>.from(
      (_data(response) as List).map(
        (item) => Map<String, dynamic>.from(item as Map),
      ),
    );
  }

  Future<List<Map<String, dynamic>>> getAlerts() async {
    final response = await _client.get(
      Uri.parse(_apiV1('/alerts')),
      headers: await _headers,
    );
    _check(response, 'Errore caricamento alert.');
    final decoded = _data(response);
    if (decoded is! List) {
      return const [];
    }
    return decoded
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  Future<Map<String, dynamic>> getUnreadAlertCount() async {
    final response = await _client.get(
      Uri.parse(_apiV1('/alerts/unread-count')),
      headers: await _headers,
    );
    _check(response, 'Errore caricamento conteggio alert.');
    return Map<String, dynamic>.from(_data(response));
  }

  Future<Map<String, dynamic>> markAlertAsRead(String alertId) async {
    final response = await _client.post(
      Uri.parse(_apiV1('/alerts/$alertId/read')),
      headers: await _headers,
    );
    _check(response, 'Errore aggiornamento alert.');
    return Map<String, dynamic>.from(_data(response));
  }

  Future<Map<String, dynamic>> getMyOperatorProfile() async {
    final response = await _client.get(
      Uri.parse(_apiV1('/operator/me')),
      headers: await _headers,
    );
    _check(response, 'Errore caricamento profilo operatore.');
    return Map<String, dynamic>.from(_data(response));
  }

  Future<Map<String, dynamic>> getAntennaDetails(String id) async {
    final response = await _client
        .get(
          Uri.parse(_apiV1('/antennas/${Uri.encodeComponent(id)}')),
          headers: await _headers,
        )
        .timeout(const Duration(seconds: 20));
    _check(response, 'Impossibile recuperare il nome dell’antenna.');
    return Map<String, dynamic>.from(_data(response));
  }

  Future<dynamic> updateMyOperatorProfile(Map<String, dynamic> profile) async {
    final response = await _client.put(
      Uri.parse(_apiV1('/operator/me')),
      headers: await _headers,
      body: jsonEncode(profile),
    );
    _check(response, 'Errore aggiornamento profilo operatore.');
    return _data(response);
  }

  Future<dynamic> createAntenna(Map<String, dynamic> antenna) async {
    final response = await _client.post(
      Uri.parse(_apiV1('/dashboard/antenne')),
      headers: await _headers,
      body: jsonEncode(antenna),
    );
    _check(response, 'Errore creazione antenna.');
    return _data(response);
  }

  Future<List<dynamic>> getAssetHistory(String assetId) async {
    final normalizedId = assetId.trim();
    if (normalizedId.isEmpty) {
      throw ArgumentError.value(assetId, 'assetId', 'Asset obbligatorio.');
    }
    final response = await _client.get(
      Uri.parse(
        _apiV1('/antennas/${Uri.encodeComponent(normalizedId)}/history'),
      ),
      headers: await _headers,
    );
    _check(response, 'Errore caricamento storia asset.');
    return List<dynamic>.from(_data(response) as List);
  }

  Future<List<Map<String, dynamic>>> getIncidents() async {
    final response = await _client.get(
      Uri.parse(_apiV1('/incidents')),
      headers: await _headers,
    );
    _check(response, 'Errore caricamento incident.');
    final decoded = _data(response);
    if (decoded is! List) {
      throw const FormatException('Elenco incident non valido.');
    }
    return decoded
        .map((item) {
          if (item is! Map) {
            throw const FormatException('Record incident non valido.');
          }
          return Map<String, dynamic>.from(item);
        })
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> createIncident({
    required String title,
    String? description,
    String severity = 'MEDIUM',
  }) async {
    final normalizedTitle = title.trim();
    if (normalizedTitle.isEmpty) {
      throw ArgumentError.value(
        title,
        'title',
        'Titolo incident obbligatorio.',
      );
    }
    final response = await _client.post(
      Uri.parse(_apiV1('/incidents')),
      headers: await _headers,
      body: jsonEncode({
        'title': normalizedTitle,
        if (description != null && description.trim().isNotEmpty)
          'description': description.trim(),
        'severity': severity,
      }),
    );
    _check(response, 'Errore creazione incident.');
    return Map<String, dynamic>.from(_data(response) as Map);
  }

  Future<Map<String, dynamic>> transitionIncident(
    String incidentId,
    String status, {
    String? rootCause,
    String? resolution,
  }) async {
    final normalizedId = incidentId.trim();
    if (normalizedId.isEmpty) {
      throw ArgumentError.value(
        incidentId,
        'incidentId',
        'Incident obbligatorio.',
      );
    }
    final normalizedStatus = status.trim().toUpperCase();
    if (normalizedStatus.isEmpty) {
      throw ArgumentError.value(
        status,
        'status',
        'Stato incident obbligatorio.',
      );
    }
    final response = await _client.post(
      Uri.parse(
        _apiV1('/incidents/${Uri.encodeComponent(normalizedId)}/transitions'),
      ),
      headers: await _headers,
      body: jsonEncode({
        'status': normalizedStatus,
        'rootCause': rootCause,
        'resolution': resolution,
      }),
    );
    _check(response, 'Errore aggiornamento incident.');
    return Map<String, dynamic>.from(_data(response) as Map);
  }

  Future<List<dynamic>> getTasksByOperator(String operatorId) async {
    final response = await _client.get(
      Uri.parse(_apiV1('/tasks/operator/$operatorId')),
      headers: await _headers,
    );
    _check(response, 'Errore caricamento task operatore.');
    return _data(response) as List<dynamic>;
  }

  Future<dynamic> getTask(String id) async {
    final response = await _client.get(
      Uri.parse(_apiV1('/tasks/$id')),
      headers: await _headers,
    );
    _check(response, 'Errore caricamento task.');
    return _data(response);
  }

  Future<dynamic> updateTaskStatus(
    String id,
    String status, {
    String? idempotencyKey,
  }) async {
    final requestKey = idempotencyKey ?? _newIdempotencyKey();
    final action = switch (status.trim().toUpperCase()) {
      'ASSIGNED' || 'ACCEPTED' => 'accept',
      'EN_ROUTE' => 'en-route',
      'IN_PROGRESS' => 'start',
      'WAITING' => 'wait',
      'COMPLETED' => throw ArgumentError.value(
        status,
        'status',
        'Il completamento richiede le coordinate GPS. Usa completeTaskWithLocation.',
      ),
      _ => throw ArgumentError.value(
        status,
        'status',
        'Stato mobile non supportato.',
      ),
    };
    return _runWithOfflineQueue(
      action: 'task_status_update',
      payload: {'id': id, 'status': status, 'idempotencyKey': requestKey},
      onlineCall: () async {
        final headers = await _headers;
        headers['Idempotency-Key'] = requestKey;
        final response = await _client
            .post(
              Uri.parse(apiV1Url('/operator/tasks/$id/$action')),
              headers: headers,
            )
            .timeout(const Duration(seconds: 20));
        _check(response, 'Errore aggiornamento task.');
        return _data(response);
      },
    );
  }

  Future<dynamic> completeTaskWithLocation(
    String id, {
    required double latitude,
    required double longitude,
    required double accuracy,
    String? idempotencyKey,
  }) async {
    final requestKey =
        idempotencyKey ??
        await OfflineSyncService.instance.persistentIdempotencyKey(
          'checkout_$id',
        );
    final payload = {
      'id': id,
      'latitude': latitude,
      'longitude': longitude,
      'accuracy': accuracy,
      'idempotencyKey': requestKey,
    };
    final result = await _runWithOfflineQueue(
      action: 'task_checkout',
      payload: payload,
      onlineCall: () async {
        final headers = await _headers;
        headers['Idempotency-Key'] = requestKey;
        final response = await _client
            .post(
              Uri.parse(_apiV1('/operator/tasks/$id/complete')),
              headers: headers,
              body: jsonEncode({
                'latitude': latitude,
                'longitude': longitude,
                'accuracy': accuracy,
              }),
            )
            .timeout(const Duration(seconds: 20));
        _check(response, 'Errore check-out GPS.');
        return _data(response);
      },
    );
    await OfflineSyncService.instance.clearPersistentIdempotencyKey(
      'checkout_$id',
    );
    return result;
  }

  Future<dynamic> checkInTask(
    String id, {
    required double latitude,
    required double longitude,
    required double accuracy,
    String? idempotencyKey,
  }) async {
    final requestKey = idempotencyKey ?? _newIdempotencyKey();
    final payload = {
      'id': id,
      'latitude': latitude,
      'longitude': longitude,
      'accuracy': accuracy,
      'idempotencyKey': requestKey,
    };
    return _runWithOfflineQueue(
      action: 'task_check_in',
      payload: payload,
      onlineCall: () async {
        final headers = await _headers;
        headers['Idempotency-Key'] = requestKey;
        final response = await _client
            .post(
              Uri.parse(_apiV1('/operator/tasks/$id/check-in')),
              headers: headers,
              body: jsonEncode({
                'latitude': latitude,
                'longitude': longitude,
                'accuracy': accuracy,
              }),
            )
            .timeout(const Duration(seconds: 20));
        _check(response, 'Errore check-in GPS.');
        return _data(response);
      },
    );
  }

  final Map<String, Future<dynamic>> _reportsInFlight = {};

  Future<QueuedSyncAction?> pendingMaintenanceReport({
    String? taskId,
    required String antennaId,
  }) async {
    final user = AuthService.instance.currentUser;
    if (user == null) return null;
    final tenant = (await user.getIdTokenResult()).claims?['tenantId']
        ?.toString();
    if (tenant == null) return null;
    return pendingReportFor(
      await OfflineSyncService.instance.pending(),
      actorUid: user.uid,
      tenantId: tenant,
      taskId: taskId,
      antennaId: antennaId,
    );
  }

  Future<dynamic> resumeMaintenanceReport({
    String? taskId,
    required String antennaId,
    String? requestKey,
  }) async {
    final pending = await pendingMaintenanceReport(
      taskId: taskId,
      antennaId: antennaId,
    );
    if (pending != null) {
      return submitMaintenanceReport(
        taskId: taskId,
        report: Map<String, dynamic>.from(pending.payload['report'] as Map),
      );
    }
    if (requestKey == null) return null;
    final user = AuthService.instance.currentUser;
    final tenant = (await user?.getIdTokenResult())?.claims?['tenantId']
        ?.toString();
    if (user == null || tenant == null) return null;
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(
      'report_receipt_${tenant}_${user.uid}_${taskId ?? antennaId}',
    );
    if (raw == null) return null;
    final receipt = jsonDecode(raw) as Map;
    return receipt['requestKey'] == requestKey ? receipt['result'] : null;
  }

  Future<dynamic> submitMaintenanceReport({
    String? taskId,
    required Map<String, dynamic> report,
    String? idempotencyKey,
    List<File> attachmentFiles = const <File>[],
    Map<String, Uint8List> attachmentBytes = const <String, Uint8List>{},
    List<Map<String, dynamic>>? stagedAttachments,
    String? expectedActorUid,
    String? expectedTenantId,
  }) async {
    final scope =
        '${AuthService.instance.currentUid}|${taskId ?? report['antennaId']}';
    final existing = _reportsInFlight[scope];
    if (existing != null) return existing;
    final sending = _submitMaintenanceReport(
      taskId: taskId,
      report: report,
      idempotencyKey: idempotencyKey,
      attachmentFiles: attachmentFiles,
      attachmentBytes: attachmentBytes,
      stagedAttachments: stagedAttachments,
      expectedActorUid: expectedActorUid,
      expectedTenantId: expectedTenantId,
    );
    _reportsInFlight[scope] = sending;
    try {
      return await sending;
    } finally {
      _reportsInFlight.remove(scope);
    }
  }

  Future<dynamic> _submitMaintenanceReport({
    String? taskId,
    required Map<String, dynamic> report,
    String? idempotencyKey,
    List<File> attachmentFiles = const <File>[],
    Map<String, Uint8List> attachmentBytes = const <String, Uint8List>{},
    List<Map<String, dynamic>>? stagedAttachments,
    String? expectedActorUid,
    String? expectedTenantId,
  }) async {
    final user = AuthService.instance.currentUser;
    final actorUid = user?.uid;
    if (user == null || actorUid == null || actorUid.isEmpty) {
      throw StateError('Operatore non autenticato.');
    }
    final tenantId =
        (await user.getIdTokenResult()).claims?['tenantId'] as String?;
    if (tenantId == null || tenantId.isEmpty) {
      throw StateError('Tenant non assegnato all\'identità autenticata.');
    }
    if (expectedActorUid != null && expectedActorUid != actorUid ||
        expectedTenantId != null && expectedTenantId != tenantId) {
      throw StateError('L\'identità attiva non corrisponde al report in coda.');
    }

    final queue = await OfflineSyncService.instance.pending();
    final pending = stagedAttachments == null
        ? pendingReportFor(
            queue,
            actorUid: actorUid,
            tenantId: tenantId,
            taskId: taskId,
            antennaId: report['antennaId']?.toString() ?? '',
            requestKey: idempotencyKey,
          )
        : null;
    if (pending != null) {
      final data = pending.payload;
      final result = await _submitMaintenanceReport(
        taskId: data['taskId']?.toString(),
        report: Map<String, dynamic>.from(data['report'] as Map),
        idempotencyKey: data['idempotencyKey'] as String,
        stagedAttachments: (data['stagedAttachments'] as List? ?? [])
            .map((r) => Map<String, dynamic>.from(r as Map))
            .toList(),
        expectedActorUid: actorUid,
        expectedTenantId: tenantId,
      );
      await OfflineSyncService.instance.remove(pending.id);
      return result;
    }
    final keyScope =
        'report_${tenantId}_${actorUid}_${taskId ?? report['antennaId']}';
    final requestKey =
        idempotencyKey ??
        await OfflineSyncService.instance.persistentIdempotencyKey(keyScope);
    final staged =
        stagedAttachments ??
        await _reportAttachmentStore.stage(
          requestKey: 'attempt_${requestKey}_${_newIdempotencyKey()}',
          files: attachmentFiles,
          bytes: attachmentBytes,
        );
    final queuePayload = <String, dynamic>{
      'taskId': taskId,
      'report': report,
      'idempotencyKey': requestKey,
      'actorUid': actorUid,
      'tenantId': tenantId,
      'stagedAttachments': staged,
      'keyScope': keyScope,
    };

    // Persist the immutable snapshot before networking, including when the
    // process is killed after the server commits but before receiving its reply.
    await OfflineSyncService.instance.enqueue(
      'maintenance_report',
      queuePayload,
    );
    try {
      final result = await _runWithOfflineQueue(
        action: 'maintenance_report',
        payload: queuePayload,
        onlineCall: () async {
          final currentUser = AuthService.instance.currentUser;
          if (currentUser?.uid != actorUid) {
            throw StateError(
              'Effettua l\'accesso con l\'operatore che ha creato il report.',
            );
          }
          final currentTenant =
              (await currentUser!.getIdTokenResult()).claims?['tenantId']
                  as String?;
          if (currentTenant != tenantId) {
            throw StateError(
              'Effettua l\'accesso con il tenant che ha creato il report.',
            );
          }

          final headers = await _headers;
          final submittedReport = Map<String, dynamic>.from(report);
          final rawAttachments = submittedReport['attachments'];
          final attachmentUrls = rawAttachments is List
              ? rawAttachments.map((item) => item.toString()).toList()
              : <String>[];
          final safeRequestKey = requestKey.replaceAll(
            RegExp(r'[^A-Za-z0-9_-]'),
            '_',
          );
          for (var index = 0; index < staged.length; index++) {
            final attachment = staged[index];
            final file = await _reportAttachmentStore.resolve(attachment);
            final name = attachment['name']?.toString() ?? 'attachment';
            if (await file.length() > 10000000) {
              throw StateError('Allegato troppo grande: limite 10 MB.');
            }
            final upload = await _client
                .post(
                  Uri.parse(_apiV1('/files')).replace(
                    queryParameters: {
                      'operationId': '${safeRequestKey}_$index',
                      'name': name,
                    },
                  ),
                  headers: {
                    ...headers,
                    'Content-Type': 'application/octet-stream',
                  },
                  body: await file.readAsBytes(),
                )
                .timeout(const Duration(seconds: 40));
            _check(upload, 'Caricamento allegato non riuscito.');
            final uploaded = _data(upload);
            if (uploaded is! Map || uploaded['reference'] is! String) {
              throw const FormatException(
                'Risposta upload allegato non valida.',
              );
            }
            attachmentUrls.add(uploaded['reference'] as String);
          }
          submittedReport['attachments'] = attachmentUrls;

          final path = taskId == null || taskId.isEmpty
              ? '/operator/reports'
              : '/operator/tasks/$taskId/report';
          headers['Idempotency-Key'] = requestKey;
          final response = await _client
              .post(
                Uri.parse(_apiV1(path)),
                headers: headers,
                body: jsonEncode(submittedReport),
              )
              .timeout(const Duration(seconds: 20));
          _check(response, 'Errore invio report.');
          return _data(response);
        },
      );
      final preferences = await SharedPreferences.getInstance();
      final submitted = result is Map ? result['report'] : null;
      await preferences.setString(
        'report_receipt_${tenantId}_${actorUid}_${taskId ?? report['antennaId']}',
        jsonEncode({
          'requestKey': requestKey,
          'result': {
            'report': {'id': submitted is Map ? submitted['id'] : null},
            'verificationUrl': result is Map ? result['verificationUrl'] : null,
          },
        }),
      );
      await ReportDraftStore().delete(
        ReportDraftStore.storageKey(
          tenantId: tenantId,
          operatorUid: actorUid,
          taskScope: taskId ?? report['antennaId'].toString(),
        ),
      );
      // Commit removal of the queue entry before deleting files: a crash after
      // acknowledgement must never leave a queued report pointing to missing files.
      for (final entry in await OfflineSyncService.instance.pending()) {
        if (entry.action == 'maintenance_report' &&
            entry.payload['actorUid'] == actorUid &&
            entry.payload['tenantId'] == tenantId &&
            entry.payload['idempotencyKey'] == requestKey) {
          await OfflineSyncService.instance.remove(entry.id);
        }
      }
      await _reportAttachmentStore.remove(staged);
      await OfflineSyncService.instance.clearPersistentIdempotencyKey(keyScope);
      if (taskId != null && taskId.isNotEmpty) {
        await OfflineSyncService.instance.clearPersistentIdempotencyKey(
          'report_$taskId',
        );
      }
      return result;
    } catch (error) {
      if (error is! ReportQueuedException && stagedAttachments == null) {
        for (final entry in await OfflineSyncService.instance.pending()) {
          if (entry.action == 'maintenance_report' &&
              entry.payload['actorUid'] == actorUid &&
              entry.payload['tenantId'] == tenantId &&
              entry.payload['idempotencyKey'] == requestKey) {
            await OfflineSyncService.instance.remove(entry.id);
          }
        }
      }
      final queued = (await OfflineSyncService.instance.pending()).any(
        (action) => action.payload['idempotencyKey']?.toString() == requestKey,
      );
      if (!queued) {
        await _reportAttachmentStore.remove(staged);
        if (idempotencyKey == null) {
          await OfflineSyncService.instance.clearPersistentIdempotencyKey(
            keyScope,
          );
        }
      }
      rethrow;
    }
  }

  Future<void> discardFailedSyncAction(String id) async {
    final service = OfflineSyncService.instance;
    final failed = await service.failedActions();
    QueuedSyncAction? target;
    for (final action in failed) {
      if (action.id == id) {
        target = action;
        break;
      }
    }
    if (target == null) return;

    final payload = target.payload;
    if (target.action == 'maintenance_report') {
      final keyScope = payload['keyScope']?.toString();
      if (keyScope != null) {
        await service.clearPersistentIdempotencyKey(keyScope);
      }
      final rawAttachments = payload['stagedAttachments'];
      if (rawAttachments is List) {
        final staged = rawAttachments
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
        await _reportAttachmentStore.remove(staged);
      }
      final taskId = payload['taskId']?.toString();
      if (taskId != null && taskId.isNotEmpty) {
        await service.clearPersistentIdempotencyKey('report_$taskId');
      }
    } else if (target.action == 'task_checkout') {
      final taskId = payload['id']?.toString();
      if (taskId != null && taskId.isNotEmpty) {
        await service.clearPersistentIdempotencyKey('checkout_$taskId');
      }
    }
    await service.remove(id);
  }

  Future<dynamic> _runWithOfflineQueue({
    required String action,
    required Map<String, dynamic> payload,
    required Future<dynamic> Function() onlineCall,
  }) async {
    final user = AuthService.instance.currentUser;
    if (user == null) {
      throw StateError('Accedi prima di registrare un’operazione.');
    }
    final claims = await user.getIdTokenResult();
    final tenantId = claims.claims?['tenantId']?.toString();
    if (tenantId == null || tenantId.isEmpty) {
      throw StateError('Tenant non assegnato.');
    }
    if (payload['actorUid'] != null && payload['actorUid'] != user.uid ||
        payload['tenantId'] != null && payload['tenantId'] != tenantId) {
      throw StateError(
        'La sessione è cambiata. Il report resta associato al suo autore.',
      );
    }
    payload['actorUid'] = user.uid;
    payload['tenantId'] = tenantId;
    Exception queuedFailure(String message) => action == 'maintenance_report'
        ? ReportQueuedException(message)
        : Exception(message);
    try {
      return await onlineCall();
    } on TimeoutException catch (_) {
      await OfflineSyncService.instance.enqueue(action, payload);
      throw queuedFailure(
        'Timeout di rete: l\'operazione è stata salvata e verrà sincronizzata automaticamente.',
      );
    } on SocketException catch (_) {
      await OfflineSyncService.instance.enqueue(action, payload);
      throw queuedFailure(
        'Connessione assente: l\'operazione è stata salvata e verrà sincronizzata automaticamente.',
      );
    } on http.ClientException catch (_) {
      await OfflineSyncService.instance.enqueue(action, payload);
      throw queuedFailure(
        'Connessione assente: l\'operazione è stata salvata e verrà sincronizzata automaticamente.',
      );
    } on FirebaseException catch (error) {
      if (!const {
        'storage/retry-limit-exceeded',
        'storage/unknown',
        'storage/network-request-failed',
      }.contains(error.code)) {
        rethrow;
      }
      await OfflineSyncService.instance.enqueue(action, payload);
      throw queuedFailure(
        'Storage temporaneamente non disponibile. Allegati e report sono in coda per il retry.',
      );
    } on _RetryableApiException catch (error) {
      await OfflineSyncService.instance.enqueue(action, payload);
      throw queuedFailure(
        'Servizio temporaneamente non disponibile: ${error.message}. Operazione in coda per il retry.',
      );
    }
  }

  Future<void> _flushQueuedAction(
    String action,
    Map<String, dynamic> payload,
  ) async {
    final user = AuthService.instance.currentUser;
    if (user == null) throw const SyncDeferredException();
    if (payload['actorUid'] == null || payload['tenantId'] == null) {
      throw PermanentSyncFailure(
        'Operazione precedente senza identità verificabile. Reinseriscila con l’account corretto.',
      );
    }
    if (payload['actorUid'] != user.uid) throw const SyncDeferredException();
    final claims = await user.getIdTokenResult();
    if (payload['tenantId'] != claims.claims?['tenantId']) {
      throw const SyncDeferredException();
    }
    switch (action) {
      case 'task_status_update':
        final taskId = payload['id']?.toString();
        final status = payload['status']?.toString();
        final idempotencyKey = payload['idempotencyKey']?.toString();
        if (taskId == null ||
            taskId.isEmpty ||
            status == null ||
            status.isEmpty) {
          throw ArgumentError('Task e stato mancanti nella coda offline.');
        }
        await updateTaskStatus(taskId, status, idempotencyKey: idempotencyKey);
        break;
      case 'maintenance_report':
        final report = payload['report'];
        final taskId = payload['taskId']?.toString();
        final idempotencyKey = payload['idempotencyKey']?.toString();
        final rawAttachments = payload['stagedAttachments'];
        final stagedAttachments = rawAttachments is List
            ? rawAttachments
                  .whereType<Map>()
                  .map((item) => Map<String, dynamic>.from(item))
                  .toList()
            : <Map<String, dynamic>>[];
        if (report is! Map<String, dynamic> && report is Map) {
          final normalized = Map<String, dynamic>.from(report);
          await submitMaintenanceReport(
            taskId: taskId,
            report: normalized,
            idempotencyKey: idempotencyKey,
            stagedAttachments: stagedAttachments,
            expectedActorUid: payload['actorUid']?.toString(),
            expectedTenantId: payload['tenantId']?.toString(),
          );
          break;
        }
        if (report is Map<String, dynamic>) {
          await submitMaintenanceReport(
            taskId: taskId,
            report: report,
            idempotencyKey: idempotencyKey,
            stagedAttachments: stagedAttachments,
            expectedActorUid: payload['actorUid']?.toString(),
            expectedTenantId: payload['tenantId']?.toString(),
          );
        } else {
          throw ArgumentError('Report mancante nella coda offline.');
        }
        break;
      case 'task_check_in':
        final taskId = payload['id']?.toString();
        final latitude = payload['latitude'];
        final longitude = payload['longitude'];
        final accuracy = payload['accuracy'] is num
            ? payload['accuracy']
            : 100.0;
        if (taskId == null ||
            taskId.isEmpty ||
            latitude is! num ||
            longitude is! num ||
            accuracy is! num) {
          throw ArgumentError(
            'Task e coordinate mancanti nella coda check-in.',
          );
        }
        await checkInTask(
          taskId,
          latitude: latitude.toDouble(),
          longitude: longitude.toDouble(),
          accuracy: accuracy.toDouble(),
          idempotencyKey: payload['idempotencyKey']?.toString(),
        );
        break;
      case 'task_checkout':
        final taskId = payload['id']?.toString();
        final latitude = payload['latitude'];
        final longitude = payload['longitude'];
        final accuracy = payload['accuracy'] is num
            ? payload['accuracy']
            : 100.0;
        if (taskId == null ||
            taskId.isEmpty ||
            latitude is! num ||
            longitude is! num ||
            accuracy is! num) {
          throw ArgumentError(
            'Task e coordinate mancanti nella coda check-out.',
          );
        }
        await completeTaskWithLocation(
          taskId,
          latitude: latitude.toDouble(),
          longitude: longitude.toDouble(),
          accuracy: accuracy.toDouble(),
          idempotencyKey: payload['idempotencyKey']?.toString(),
        );
        break;
      default:
        throw UnsupportedError(
          'Azione sincronizzazione non supportata: $action',
        );
    }
  }
}

class _RetryableApiException implements Exception {
  const _RetryableApiException(this.message);

  final String message;
}
