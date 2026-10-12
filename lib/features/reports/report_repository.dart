import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/api_service.dart';

/// Application operations are independent of report widgets and animation.
class ReportRepository {
  ReportRepository(this.api);
  final ApiService api;
  Future<List<Map<String, dynamic>>> inventory() => api.getMyInventory();
  Future<Map<String, dynamic>> asset(String id) => api.getAntennaDetails(id);
  Future<dynamic> submit(
    Map<String, dynamic> report,
    List<File> files,
    Map<String, Uint8List> bytes, {
    String? taskId,
  }) => api.submitMaintenanceReport(
    report: report,
    attachmentFiles: files,
    attachmentBytes: bytes,
    taskId: taskId,
  );
}

final reportRepositoryProvider = Provider<ReportRepository>(
  (ref) => ReportRepository(ApiService.instance),
);
