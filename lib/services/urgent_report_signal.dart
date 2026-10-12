import 'dart:math';

/// Immutable payload and stable identity for an urgent signal attached to a draft.
/// Persist [toJson] before sending; persist the receipt before continuing the report.
class UrgentReportSignal {
  final String operationId;
  final String description;
  final String assetId;
  final String? taskId;
  final bool confirmed;

  const UrgentReportSignal({
    required this.operationId,
    required this.description,
    required this.assetId,
    this.taskId,
    this.confirmed = false,
  });

  factory UrgentReportSignal.prepare({
    required String description,
    required String assetId,
    String? taskId,
  }) {
    final random = Random.secure();
    final id = List.generate(
      16,
      (_) => random.nextInt(256),
    ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    return UrgentReportSignal(
      operationId: 'urgent-$id',
      description: description.trim(),
      assetId: assetId,
      taskId: taskId,
    );
  }

  factory UrgentReportSignal.fromJson(Map<String, dynamic> data) {
    final id = data['operationId'];
    final description = data['description'];
    final asset = data['assetId'];
    if (id is! String ||
        id.isEmpty ||
        description is! String ||
        description.trim().isEmpty ||
        asset is! String) {
      throw const FormatException(
        'Stato della segnalazione urgente non valido.',
      );
    }
    return UrgentReportSignal(
      operationId: id,
      description: description,
      assetId: asset,
      taskId: data['taskId'] as String?,
      confirmed: data['confirmed'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
    'operationId': operationId,
    'description': description,
    'assetId': assetId,
    'taskId': taskId,
    'confirmed': confirmed,
  };

  Future<UrgentReportSignal> deliver(
    Future<void> Function(UrgentReportSignal signal) send,
  ) async {
    if (confirmed) return this;
    await send(this);
    return UrgentReportSignal(
      operationId: operationId,
      description: description,
      assetId: assetId,
      taskId: taskId,
      confirmed: true,
    );
  }
}
