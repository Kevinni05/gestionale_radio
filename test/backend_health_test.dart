import 'package:flutter_test/flutter_test.dart';
import 'package:gestionale_radio/services/backend_health.dart';

void main() {
  test('accepts only the expected healthy RadioTech backend identity', () {
    expect(
      BackendHealth.isHealthyRadioTech(
        statusCode: 200,
        body: '{"status":"UP","service":"radiotech-backend"}',
      ),
      isTrue,
    );

    for (final body in [
      '{"status":"UP","service":"another-service"}',
      '{"status":"DOWN","service":"radiotech-backend"}',
      '{"status":"UP"}',
      '[]',
      'not-json',
    ]) {
      expect(
        BackendHealth.isHealthyRadioTech(statusCode: 200, body: body),
        isFalse,
        reason: body,
      );
    }

    expect(
      BackendHealth.isHealthyRadioTech(
        statusCode: 503,
        body: '{"status":"UP","service":"radiotech-backend"}',
      ),
      isFalse,
    );
  });
}
