import 'api_http_client.dart';
import 'dart:convert';

import 'auth_service.dart';

class BackendAuthService {
  BackendAuthService({required this.baseUrl});

  final String baseUrl;

  final AuthService _authService = AuthService.instance;

  Future<Map<String, dynamic>> login() async {
    final token = await _authService.requireIdToken();

    final response = await ApiHttpClient.instance.post(
      Uri.parse('$baseUrl/api/v1/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'idToken': token}),
    );

    final Map<String, dynamic> data = jsonDecode(response.body);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(data['error'] ?? 'Errore autenticazione backend.');
    }

    return data;
  }
}
