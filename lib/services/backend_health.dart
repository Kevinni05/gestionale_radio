import 'dart:convert';

class BackendHealth {
  const BackendHealth._();

  static bool isHealthyRadioTech({
    required int statusCode,
    required String body,
  }) {
    if (statusCode != 200) return false;
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) return false;
      return decoded['status'] == 'UP' &&
          decoded['service'] == 'radiotech-backend';
    } catch (_) {
      return false;
    }
  }
}
