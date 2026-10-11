import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'local_operational_store.dart';

class SyncDeferredException implements Exception {
  const SyncDeferredException();
}

class QueuedSyncAction {
  QueuedSyncAction({
    required this.id,
    required this.action,
    required this.payload,
    required this.createdAt,
    this.retryCount = 0,
    this.nextAttemptAt,
    this.lastError,
    this.failed = false,
  });

  final String id;
  final String action;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final int retryCount;
  final DateTime? nextAttemptAt;
  final String? lastError;
  final bool failed;

  QueuedSyncAction copyWith({
    String? id,
    String? action,
    Map<String, dynamic>? payload,
    DateTime? createdAt,
    int? retryCount,
    DateTime? nextAttemptAt,
    String? lastError,
    bool? failed,
    bool clearRetryState = false,
    bool clearNextAttemptAt = false,
  }) {
    return QueuedSyncAction(
      id: id ?? this.id,
      action: action ?? this.action,
      payload: payload ?? this.payload,
      createdAt: createdAt ?? this.createdAt,
      retryCount: retryCount ?? this.retryCount,
      nextAttemptAt: clearRetryState || clearNextAttemptAt
          ? null
          : nextAttemptAt ?? this.nextAttemptAt,
      lastError: clearRetryState ? null : lastError ?? this.lastError,
      failed: failed ?? this.failed,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'action': action,
    'payload': payload,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'retryCount': retryCount,
    'nextAttemptAt': nextAttemptAt?.toUtc().toIso8601String(),
    'lastError': lastError,
    'failed': failed,
  };

  factory QueuedSyncAction.fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString().trim() ?? '';
    final action = json['action']?.toString().trim() ?? '';
    final payload = json['payload'];
    final createdAt = DateTime.tryParse(json['createdAt']?.toString() ?? '');
    final retryCount = int.tryParse(json['retryCount']?.toString() ?? '0');
    final nextRaw = json['nextAttemptAt']?.toString();
    final nextAttemptAt = nextRaw == null || nextRaw.isEmpty
        ? null
        : DateTime.tryParse(nextRaw);

    if (id.isEmpty ||
        action.isEmpty ||
        payload is! Map ||
        createdAt == null ||
        retryCount == null ||
        retryCount < 0 ||
        nextRaw != null && nextRaw.isNotEmpty && nextAttemptAt == null) {
      throw const FormatException('Record della coda offline non valido.');
    }

    return QueuedSyncAction(
      id: id,
      action: action,
      payload: Map<String, dynamic>.from(payload),
      createdAt: createdAt,
      retryCount: retryCount,
      nextAttemptAt: nextAttemptAt,
      lastError: json['lastError']?.toString(),
      failed: json['failed'] == true,
    );
  }
}

class PermanentSyncFailure implements Exception {
  const PermanentSyncFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

class SyncConflictException extends PermanentSyncFailure {
  const SyncConflictException(super.message);
}

class _QueueSnapshot {
  const _QueueSnapshot({
    required this.items,
    required this.revision,
    required this.encoded,
  });

  final List<QueuedSyncAction> items;
  final int revision;
  final String encoded;
}

class OfflineSyncService {
  OfflineSyncService._();

  static final OfflineSyncService instance = OfflineSyncService._();
  final LocalOperationalStore _store = LocalOperationalStore.instance;

  static const String _queueKey = 'offline_sync_queue';
  static const String _queueBackupKey = 'offline_sync_queue_backup';
  static const int _queueFormatVersion = 2;
  static const int maxQueueItems = 200;
  static const int maxRetryAttempts = 8;
  static const Duration _baseRetryDelay = Duration(seconds: 30);
  static const Duration _maxRetryDelay = Duration(hours: 1);

  Timer? _timer;
  Future<void> Function(String action, Map<String, dynamic> payload)? _executor;
  bool _retryInProgress = false;
  bool _retryRequested = false;
  bool _queueCorrupted = false;
  Future<void>? _queueAccess;

  Future<T> _serialize<T>(Future<T> Function() action) async {
    final previous = _queueAccess;
    final released = Completer<void>.sync();
    _queueAccess = released.future;
    try {
      if (previous != null) {
        await previous;
      }
      return await action();
    } finally {
      if (identical(_queueAccess, released.future)) {
        _queueAccess = null;
      }
      released.complete();
    }
  }

  bool get queueCorrupted => _queueCorrupted;

  Future<void> start({
    required Future<void> Function(String action, Map<String, dynamic> payload)
    executor,
    Duration interval = const Duration(seconds: 30),
  }) async {
    _executor = executor;
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) async {
      final state = WidgetsBinding.instance.lifecycleState;
      if (state == null || state == AppLifecycleState.resumed) {
        try {
          await retryPending();
        } catch (_) {
          // A storage/platform error must preserve the queue and not become an
          // unhandled timer error. A resume/manual retry can try again.
        }
      }
    });
    await retryPending();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _executor = null;
    _retryRequested = false;
  }

  Future<void> enqueue(
    String action,
    Map<String, dynamic> payload,
  ) => _serialize(() async {
    final normalizedAction = action.trim();
    if (normalizedAction.isEmpty) {
      throw ArgumentError.value(
        action,
        'action',
        'Azione offline obbligatoria.',
      );
    }
    try {
      jsonEncode(payload);
    } on JsonUnsupportedObjectError {
      throw ArgumentError.value(
        payload,
        'payload',
        'Il payload offline deve essere serializzabile.',
      );
    }

    final current = await _loadQueue();
    final idempotencyKey = payload['idempotencyKey']?.toString();
    if (idempotencyKey != null && idempotencyKey.isNotEmpty) {
      final alreadyQueued = current.any(
        (entry) =>
            entry.action == normalizedAction &&
            entry.payload['actorUid'] == payload['actorUid'] &&
            entry.payload['tenantId'] == payload['tenantId'] &&
            entry.payload['idempotencyKey']?.toString() == idempotencyKey,
      );
      if (alreadyQueued) return;
    }
    if (current.length >= maxQueueItems) {
      throw StateError(
        'Coda offline piena: risolvi o rimuovi alcune operazioni prima di continuare.',
      );
    }

    current.add(
      QueuedSyncAction(
        id: '${DateTime.now().microsecondsSinceEpoch}_$normalizedAction',
        action: normalizedAction,
        payload: Map<String, dynamic>.from(payload),
        createdAt: DateTime.now().toUtc(),
      ),
    );
    await _persistQueue(current);
  });

  Future<String> persistentIdempotencyKey(String scope) => _serialize(() async {
    if (scope.isEmpty) {
      throw ArgumentError.value(
        scope,
        'scope',
        'Lo scope della chiave è obbligatorio.',
      );
    }
    final preferenceKey = 'offline_idempotency_$scope';
    final existing = await _store.read(preferenceKey);
    if (existing != null && existing.isNotEmpty) {
      await _store.adoptValidated({preferenceKey: existing});
      return existing;
    }

    final random = math.Random.secure();
    final entropy = List<int>.generate(16, (_) => random.nextInt(256));
    final generated = entropy
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    await _store.write(preferenceKey, generated);
    return generated;
  });

  Future<void> clearPersistentIdempotencyKey(String scope) async {
    await _store.delete('offline_idempotency_$scope');
  }

  Future<List<QueuedSyncAction>> pending() async {
    return _serialize(_loadQueue);
  }

  Future<List<QueuedSyncAction>> failedActions() async {
    return (await pending()).where((entry) => entry.failed).toList();
  }

  Future<void> remove(String id) => _serialize(() async {
    final queue = await _loadQueue();
    final filtered = queue.where((entry) => entry.id != id).toList();
    if (filtered.length == queue.length) return;
    await _persistQueue(filtered);
  });

  Future<void> clear() => _serialize(() async {
    await _store.writeAll({_queueKey: null, _queueBackupKey: null});
    _queueCorrupted = false;
  });

  Future<void> retryFailed(String id) async {
    final queue = await pending();
    for (final item in queue) {
      if (item.id == id && item.failed) {
        await _replace(
          id,
          item.copyWith(failed: false, retryCount: 0, clearRetryState: true),
        );
        await retryPending(force: true);
        return;
      }
    }
  }

  static Duration retryDelayForAttempt(int failedAttempts) {
    final exponent = (failedAttempts - 1).clamp(0, 10);
    final seconds = (_baseRetryDelay.inSeconds * (1 << exponent)).clamp(
      _baseRetryDelay.inSeconds,
      _maxRetryDelay.inSeconds,
    );
    return Duration(seconds: seconds);
  }

  Future<void> retryPending({bool force = false}) async {
    if (_executor == null) {
      return;
    }
    if (_retryInProgress) {
      _retryRequested = _retryRequested || force;
      return;
    }

    _retryInProgress = true;
    try {
      List<QueuedSyncAction> queue;
      try {
        queue = await pending();
      } on StateError {
        return;
      }
      if (queue.isEmpty) {
        return;
      }

      final queuedSnapshot = List<QueuedSyncAction>.from(queue);
      for (final item in queuedSnapshot) {
        // stop() or a replacement executor must not turn a paused replay into
        // a null call (and charge a retry to the next account's queued work).
        final executor = _executor;
        if (executor == null) break;
        if (item.failed ||
            !force &&
                item.nextAttemptAt != null &&
                item.nextAttemptAt!.isAfter(DateTime.now().toUtc())) {
          continue;
        }
        try {
          await executor(item.action, Map<String, dynamic>.from(item.payload));
          await remove(item.id);
        } on SyncDeferredException {
          // A different account or no account is active. Preserve retry budget.
          continue;
        } on PermanentSyncFailure catch (failure) {
          final updated = item.copyWith(
            failed: true,
            lastError: _errorText(failure),
            clearNextAttemptAt: true,
          );
          await _replace(item.id, updated);
        } catch (error) {
          final retryCount = item.retryCount + 1;
          final exhausted = retryCount >= maxRetryAttempts;
          final updated = item.copyWith(
            retryCount: retryCount,
            failed: exhausted,
            nextAttemptAt: exhausted
                ? null
                : DateTime.now().toUtc().add(retryDelayForAttempt(retryCount)),
            lastError: _errorText(error),
          );
          await _replace(item.id, updated);
        }
      }
    } finally {
      _retryInProgress = false;
      if (_retryRequested) {
        _retryRequested = false;
        await retryPending(force: true);
      }
    }
  }

  String _errorText(Object error) {
    final text = error.toString();
    return text.length <= 500 ? text : text.substring(0, 500);
  }

  Future<List<QueuedSyncAction>> _loadQueue() async {
    final primaryRaw = await _store.read(_queueKey);
    final backupRaw = await _store.read(_queueBackupKey);
    final hasPrimary = primaryRaw != null && primaryRaw.trim().isNotEmpty;
    final hasBackup = backupRaw != null && backupRaw.trim().isNotEmpty;
    final primary = hasPrimary ? _decodeSnapshot(primaryRaw) : null;
    final backup = hasBackup ? _decodeSnapshot(backupRaw) : null;

    if (primary == null && backup == null) {
      if (hasPrimary || hasBackup) {
        _queueCorrupted = true;
        throw StateError(
          'La coda offline è corrotta e non è stato possibile recuperare il backup.',
        );
      }
      _queueCorrupted = false;
      return <QueuedSyncAction>[];
    }

    late final _QueueSnapshot selected;
    if (primary != null && backup != null) {
      selected = primary.revision >= backup.revision ? primary : backup;
    } else {
      selected = primary ?? backup!;
    }
    _queueCorrupted = false;

    // Repair only a stale or corrupt slot. A read must never replace a newer
    // recovery copy with an older queue revision.
    if (primary?.encoded != selected.encoded ||
        backup?.encoded != selected.encoded) {
      await _store.writeAll({
        _queueBackupKey: selected.encoded,
        _queueKey: selected.encoded,
      });
    } else {
      await _store.adoptValidated({
        _queueBackupKey: selected.encoded,
        _queueKey: selected.encoded,
      });
    }
    return List<QueuedSyncAction>.from(selected.items);
  }

  _QueueSnapshot? _decodeSnapshot(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        final items = _decodeItems(decoded);
        if (items == null) return null;
        return _QueueSnapshot(items: items, revision: 0, encoded: raw);
      }
      if (decoded is! Map ||
          decoded['version'] != _queueFormatVersion ||
          decoded['revision'] is! int ||
          (decoded['revision'] as int) < 0 ||
          decoded['items'] is! List) {
        return null;
      }
      final items = _decodeItems(decoded['items'] as List);
      if (items == null) return null;
      return _QueueSnapshot(
        items: items,
        revision: decoded['revision'] as int,
        encoded: raw,
      );
    } catch (_) {
      return null;
    }
  }

  List<QueuedSyncAction>? _decodeItems(List<dynamic> rawItems) {
    if (rawItems.length > maxQueueItems ||
        rawItems.any((entry) => entry is! Map)) {
      return null;
    }
    try {
      return rawItems
          .map(
            (entry) => QueuedSyncAction.fromJson(
              Map<String, dynamic>.from(entry as Map),
            ),
          )
          .toList(growable: true);
    } catch (_) {
      return null;
    }
  }

  Future<void> _persistQueue(List<QueuedSyncAction> queue) async {
    if (queue.length > maxQueueItems) {
      throw StateError('Coda offline oltre il limite consentito.');
    }
    final primary = _decodeSnapshot(await _store.read(_queueKey));
    final backup = _decodeSnapshot(await _store.read(_queueBackupKey));
    final revision =
        math.max(primary?.revision ?? 0, backup?.revision ?? 0) + 1;
    final encoded = jsonEncode({
      'version': _queueFormatVersion,
      'revision': revision,
      'items': queue.map((entry) => entry.toJson()).toList(growable: false),
    });

    // Both encrypted copies commit in one SQLite transaction on Android.
    // Development preferences preserve the existing backup-first behavior.
    await _store.writeAll({_queueBackupKey: encoded, _queueKey: encoded});
  }

  Future<void> _replace(String id, QueuedSyncAction updated) =>
      _serialize(() async {
        final queue = await _loadQueue();
        var found = false;
        final replaced = queue.map((entry) {
          if (entry.id == id) {
            found = true;
            return updated;
          }
          return entry;
        }).toList();
        if (!found) return;
        await _persistQueue(replaced);
      });
}
