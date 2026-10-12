import 'package:flutter_test/flutter_test.dart';
import 'package:gestionale_radio/features/reports/report_payload.dart';
import 'package:gestionale_radio/services/android_update_service.dart';

void main() {
  test(
    'technical snapshot remains immutable and checklist order does not affect version',
    () {
      final source = {'B': true, 'A': false};
      final payload = ReportPayload(
        checklist: source,
        measurements: {'Potenza (dBm)': -20},
      );
      source['A'] = true;
      expect(payload.checklist['A'], false);
      expect(
        payload.checklistVersion,
        ReportPayload(
          checklist: {'A': false, 'B': true},
          measurements: {},
        ).checklistVersion,
      );
      expect(payload.measurementUnits, {'Potenza (dBm)': 'dBm'});
      expect(() => payload.checklist['C'] = true, throwsUnsupportedError);
    },
  );
  test(
    'private APK site rejects alternate origin, credentials and insecure transport',
    () {
      const origin = 'https://updates.example.com';
      expect(
        AndroidUpdateService.isPrivateSiteUrl(
          Uri.parse('$origin/latest.json'),
          origin: origin,
        ),
        true,
      );
      for (final url in [
        'http://updates.example.com/a.apk',
        'https://evil.example/a.apk',
        'https://user@updates.example.com/a.apk',
        'https://updates.example.com:8443/a.apk',
        'https://updates.example.com/a.apk?token=x',
      ]) {
        expect(
          AndroidUpdateService.isPrivateSiteUrl(Uri.parse(url), origin: origin),
          false,
        );
      }
      expect(
        AndroidUpdateService.isPrivateSiteUrl(Uri.parse('$origin/a.apk')),
        false,
      );
    },
  );
}
