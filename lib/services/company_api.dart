import 'dart:convert';
import 'dart:math';
import 'api_service.dart';
import 'api_http_client.dart';
import 'auth_service.dart';

class CompanyApi {
  static final instance = CompanyApi();
  final _client = ApiHttpClient(requestTimeout: const Duration(seconds: 55));
  static String operationId() => List.generate(
    24,
    (_) => Random.secure().nextInt(16).toRadixString(16),
  ).join();
  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
  }) async {
    final uid = AuthService.instance.currentUid;
    final token = await AuthService.instance.requireIdToken();
    final headers = {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    final url = Uri.parse(ApiService.apiV1Url(path));
    final response = switch (method) {
      'POST' => await _client.post(
        url,
        headers: headers,
        body: jsonEncode(body),
      ),
      'PUT' => await _client.put(url, headers: headers, body: jsonEncode(body)),
      'PATCH' => await _client.patch(
        url,
        headers: headers,
        body: jsonEncode(body),
      ),
      _ => await _client.get(url, headers: headers),
    };
    if (uid != AuthService.instance.currentUid) {
      throw CompanyApiException(
        'Sessione cambiata. Apri nuovamente la sezione.',
      );
    }
    dynamic data;
    try {
      data = jsonDecode(response.body);
    } catch (_) {
      throw CompanyApiException(
        'Risposta del server non valida. Verifica il collegamento HTTPS e riprova.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CompanyApiException(
        data is Map
            ? (data['message']?.toString() ??
                  'Servizio non disponibile (${response.statusCode}).')
            : 'Servizio non disponibile.',
      );
    }
    return data;
  }
}

class CompanyApiException implements Exception {
  final String message;
  const CompanyApiException(this.message);
  @override
  String toString() => message;
}
