import 'dart:convert';
import 'package:crypto/crypto.dart';

/// The same immutable technical values feed the PDF, queue and API.
class ReportPayload {
  ReportPayload({
    required Map<String, bool> checklist,
    required Map<String, double> measurements,
  }) : checklist = Map.unmodifiable(checklist),
       measurements = Map.unmodifiable(measurements);
  final Map<String, bool> checklist;
  final Map<String, double> measurements;
  String get checklistVersion {
    final names = checklist.keys.toList()..sort();
    return 'sha256:${sha256.convert(utf8.encode(jsonEncode(names)))}';
  }

  Map<String, String> get measurementUnits {
    final units = <String, String>{};
    for (final name in measurements.keys) {
      final match = RegExp(r'\(([^()]{1,24})\)\s*$').firstMatch(name);
      if (match != null) units[name] = match.group(1)!.trim();
    }
    return units;
  }

  Map<String, dynamic> get technicalFields => {
    'checklist': checklist,
    'checklistVersion': checklistVersion,
    'measurements': measurements,
    'measurementUnits': measurementUnits,
  };
}
