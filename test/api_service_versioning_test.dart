import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gestionale_radio/services/api_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'versioned API helper keeps the mobile client on /api/v1 routes',
    () async {
      SharedPreferences.setMockInitialValues({});
      final original = ApiService.baseUrl;
      ApiService.baseUrl = 'http://localhost:8080';

      expect(
        ApiService.apiV1Url('/tasks'),
        'http://localhost:8080/api/v1/tasks',
      );
      expect(
        ApiService.apiV1Url('operator/tasks/abc/accept'),
        'http://localhost:8080/api/v1/operator/tasks/abc/accept',
      );

      ApiService.baseUrl = original;
      await Future<void>.delayed(Duration.zero);
    },
  );
}
