import 'offline_sync_service.dart';

class ReportQueuedException implements Exception {
  const ReportQueuedException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// A retry sends the immutable queued snapshot, rather than regenerating files.
QueuedSyncAction? pendingReportFor(
  List<QueuedSyncAction> queue, {
  required String actorUid,
  required String tenantId,
  required String? taskId,
  required String antennaId,
  String? requestKey,
}) {
  for (final entry in queue) {
    final data = entry.payload;
    if (entry.action != 'maintenance_report' ||
        data['actorUid'] != actorUid ||
        data['tenantId'] != tenantId) {
      continue;
    }
    final report = data['report'];
    final sameTarget = taskId != null && taskId.isNotEmpty
        ? data['taskId'] == taskId
        : (data['taskId'] == null || data['taskId'] == '') &&
              report is Map &&
              report['antennaId'] == antennaId;
    if (sameTarget &&
        (requestKey == null || data['idempotencyKey'] == requestKey)) {
      return entry;
    }
  }
  return null;
}
