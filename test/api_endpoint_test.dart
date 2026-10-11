import 'package:flutter_test/flutter_test.dart';
import 'package:gestionale_radio/services/api_endpoint.dart';

void main() {
  test(
    'release rejects cleartext, credentials and ambiguous server addresses',
    () {
      for (final value in [
        'http://api.example.org',
        'https://localhost',
        'https://10.0.2.2',
        'https://user:pass@api.example.org',
        'https://api.example.org/path',
        'https://api.example.org?token=secret',
        'api.example.org',
        'https://api.example.invalid',
      ]) {
        expect(
          () => ApiEndpoint.normalize(value, release: true),
          throwsFormatException,
          reason: value,
        );
      }
      expect(
        ApiEndpoint.normalize(' https://api.example.org/ ', release: true),
        'https://api.example.org',
      );
      expect(
        ApiEndpoint.normalize('http://10.0.2.2:8080', release: false),
        'http://10.0.2.2:8080',
      );
    },
  );
}
