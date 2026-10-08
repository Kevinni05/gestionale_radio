import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:shared_preferences/shared_preferences.dart';

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
    final payload = json['payload'];
    return QueuedSyncAction(
      id: json['id']?.toString() ?? '',
      action: json['action']?.toString() ?? 'unknown',
      payload: payload is Map
          ? Map<String, dynamic>.from(payload)
          : <String, dynamic>{},
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now().toUtc(),
      retryCount: int.tryParse(json['retryCount']?.toString() ?? '0') ?? 0,
      nextAttemptAt: DateTime.tryParse(json['nextAttemptAt']?.toString() ?? ''),
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

class OfflineSyncService {
  OfflineSyncService._();

  static final OfflineSyncService instance = OfflineSyncService._();

  static const String _queueKey = 'offline_sync_queue';
  static const String _queueBackupKey = 'offline_sync_queue_backup';
  static const int maxRetryAttempts = 8;
  static const Duration _baseRetryDelay = Duration(seconds: 30);
  static const Duration _maxRetryDelay = Duration(hours: 1);

  Timer? _timer;
  Future<void> Function(String action, Map<String, dynamic> payload)? _executor;
  bool _retryInProgress = false;
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
      await retryPending();
    });
    await retryPending();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _executor = null;
  }

  Future<void> enqueue(String action, Map<String, dynamic> payload) =>
      _serialize(() async {
        final prefs = await SharedPreferences.getInstance();
        final current = await _loadQueue();
        final idempotencyKey = payload['idempotencyKey']?.toString();
        if (idempotencyKey != null && idempotencyKey.isNotEmpty) {
          final alreadyQueued = current.any(
            (entry) =>
                entry.action == action &&
                entry.payload['actorUid'] == payload['actorUid'] &&
                entry.payload['tenantId'] == payload['tenantId'] &&
                entry.payload['idempotencyKey']?.toString() == idempotencyKey,
          );
          if (alreadyQueued) return;
        }

        final item = QueuedSyncAction(
          id: '${DateTime.now().microsecondsSinceEpoch}_$action',
          action: action,
          payload: payload,
          createdAt: DateTime.now().toUtc(),
        );
        current.add(item);
        final encoded = jsonEncode(current.map((e) => e.toJson()).toList());
        await prefs.setString(_queueKey, encoded);
        await prefs.setString(_queueBackupKey, encoded);
      });

  Future<String> persistentIdempotencyKey(String scope) async {
    if (scope.isEmpty) {
      throw ArgumentError.value(
        scope,
        'scope',
        'Lo scope della chiave è obbligatorio.',
      );
    }
    final preferences = await SharedPreferences.getInstance();
    final preferenceKey = 'offline_idempotency_$scope';
    final existing = preferences.getString(preferenceKey);
    if (existing != null && existing.isNotEmpty) return existing;

    final random = math.Random.secure();
    final entropy = List<int>.generate(16, (_) => random.nextInt(256));
    final generated = entropy
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    await preferences.setString(preferenceKey, generated);
    return generated;
  }

  Future<void> clearPersistentIdempotencyKey(String scope) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove('offline_idempotency_$scope');
  }

  Future<List<QueuedSyncAction>> pending() async {
    return _serialize(_loadQueue);
  }

  Future<List<QueuedSyncAction>> failedActions() async {
    return (await pending()).where((entry) => entry.failed).toList();
  }

  Future<void> remove(String id) => _serialize(() async {
    final prefs = await SharedPreferences.getInstance();
    final queue = await _loadQueue();
    final filtered = queue.where((entry) => entry.id != id).toList();
    final encoded = jsonEncode(filtered.map((e) => e.toJson()).toList());
    await prefs.setString(_queueKey, encoded);
    await prefs.setString(_queueBackupKey, encoded);
  });

  Future<void> clear() => _serialize(() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_queueKey);
    await prefs.remove(_queueBackupKey);
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
    if (_executor == null || _retryInProgress) {
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
        if (item.failed ||
            !force &&
                item.nextAttemptAt != null &&
                item.nextAttemptAt!.isAfter(DateTime.now().toUtc())) {
          continue;
        }
        try {
          await _executor!(item.action, item.payload);
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
    }
  }

  String _errorText(Object error) {
    final text = error.toString();
    return text.length <= 500 ? text : text.substring(0, 500);
  }

  Future<List<QueuedSyncAction>> _loadQueue() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_queueKey);
    final backupRaw = prefs.getString(_queueBackupKey);

    final hasPrimary = raw != null && raw.trim().isNotEmpty;
    final hasBackup = backupRaw != null && backupRaw.trim().isNotEmpty;
    final parsed = hasPrimary ? _decodeQueue(raw) : null;
    if (parsed != null) {
      _queueCorrupted = false;
      await prefs.setString(_queueBackupKey, raw!);
      return parsed;
    }

    final backupParsed = hasBackup ? _decodeQueue(backupRaw) : null;
    if (backupParsed != null) {
      _queueCorrupted = false;
      await prefs.setString(_queueKey, backupRaw!);
      return backupParsed;
    }

    if (hasPrimary || hasBackup) {
      _queueCorrupted = true;
      throw StateError(
        'La coda offline è corrotta e non è stato possibile recuperare il backup.',
      );
    }

    _queueCorrupted = false;
    return <QueuedSyncAction>[];
  }

  List<QueuedSyncAction>? _decodeQueue(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return <QueuedSyncAction>[];
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return null;
      }
      if (decoded.any((entry) => entry is! Map)) {
        return null;
      }

      return decoded
          .map(
            (entry) =>
                QueuedSyncAction.fromJson(Map<String, dynamic>.from(entry)),
          )
          .toList();
    } catch (_) {
      return null;
    }
  }

  Future<void> _replace(String id, QueuedSyncAction updated) =>
      _serialize(() async {
        final prefs = await SharedPreferences.getInstance();
        final queue = await _loadQueue();
        final replaced = queue.map((entry) {
          if (entry.id == id) {
            return updated;
          }
          return entry;
        }).toList();
        final encoded = jsonEncode(replaced.map((e) => e.toJson()).toList());
        await prefs.setString(_queueKey, encoded);
        await prefs.setString(_queueBackupKey, encoded);
      });
}
