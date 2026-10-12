import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestionale_radio/features/reports/report_payload.dart';
import 'package:gestionale_radio/services/maintenance_report_pdf.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('generate synthetic report with the production PDF builder', () async {
    final path = Platform.environment['RADIOTECH_QA_PDF'];
    if (path == null || path.isEmpty) {
      throw StateError('Explicit private QA output required.');
    }
    final technical = ReportPayload(
      checklist: {'Controllo QA': true},
      measurements: {'Frequenza (MHz)': 450},
    );
    final inputFile = File('$path.input.json');
    final input = inputFile.existsSync()
        ? jsonDecode(inputFile.readAsStringSync()) as Map
        : <String, dynamic>{};
    final bytes = await MaintenanceReportPdf.build(
      antennaId: input['antennaId']?.toString() ?? 'qa-asset',
      antennaName: 'RadioTech QA asset',
      operatorName: 'RadioTech QA technician',
      submittedAt: input['submittedAt'] != null
          ? DateTime.parse(input['submittedAt'].toString())
          : DateTime.utc(2026, 10, 12),
      taskId: input['taskId']?.toString() ?? 'qa-task',
      notes: 'RadioTech synthetic acceptance report',
      findings: 'No anomalies',
      checklist: technical.checklist,
      checklistVersion: technical.checklistVersion,
      materials: [
        {
          'inventoryId': input['inventoryId'] ?? 'qa-stock',
          'name': 'QA connector',
          'quantity': 1,
        },
      ],
      measurements: technical.measurements,
      photos: [],
      signature: null,
    );
    await File(path).writeAsBytes(bytes, flush: true);
    await File(
      '$path.json',
    ).writeAsString(jsonEncode(technical.technicalFields), flush: true);
    expect(bytes.take(4).toList(), [37, 80, 68, 70]);
  });
}
