import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math';
import 'api_service.dart';
import 'session_service.dart';
import 'api_http_client.dart';
import 'auth_service.dart';
import 'dart:typed_data';

class CompanyApi {
  static final instance = CompanyApi();
  final _client = ApiHttpClient();
  static String operationId() => List.generate(
    24,
    (_) => Random.secure().nextInt(16).toRadixString(16),
  ).join();
  Future<Uint8List> readAttachment(String id) async {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(id)) {
      throw const CompanyApiException('Allegato non valido.');
    }
    final uid = AuthService.instance.currentUid;
    final revision = AuthService.instance.sessionRevision;
    final tenant = SessionService.instance.tenantId;
    bool changed() =>
        uid != AuthService.instance.currentUid ||
        revision != AuthService.instance.sessionRevision ||
        tenant != SessionService.instance.tenantId;
    final token = await AuthService.instance.requireIdToken();
    final response = await _client.send(
      http.Request('GET', Uri.parse(ApiService.apiV1Url('/files/$id/content')))
        ..headers['Authorization'] = 'Bearer $token',
    );
    if (changed()) {
      await response.stream.listen((_) {}).cancel();
      throw const CompanyApiException('Sessione cambiata.');
    }
    if (response.statusCode == 404) {
      await response.stream.listen((_) {}).cancel();
      final legacy = await request('/files/$id') as Map;
      final encoded = legacy['base64'];
      if (changed() || encoded is! String || encoded.length > 14000000) {
        throw const CompanyApiException('Allegato non disponibile.');
      }
      final bytes = base64Decode(encoded);
      if (bytes.length > 10000000) {
        throw const CompanyApiException('Allegato troppo grande.');
      }
      return bytes;
    }
    if (response.statusCode != 200) {
      await response.stream.listen((_) {}).cancel();
      throw const CompanyApiException(
        'Download non autorizzato o non disponibile.',
      );
    }
    if ((response.contentLength ?? 0) > 10000000) {
      await response.stream.listen((_) {}).cancel();
      throw const CompanyApiException('Allegato troppo grande.');
    }
    final bytes = BytesBuilder(copy: false);
    int length = 0;
    await for (final chunk in response.stream) {
      if (changed()) throw const CompanyApiException('Sessione cambiata.');
      length += chunk.length;
      if (length > 10000000) {
        throw const CompanyApiException('Allegato troppo grande.');
      }
      bytes.add(chunk);
    }
    if (changed()) {
      throw const CompanyApiException('Sessione cambiata.');
    }
    return bytes.takeBytes();
  }

  Future<Uint8List> rosterPdf(String month) async {
    if (!RegExp(r'^\d{4}-\d{2}$').hasMatch(month)) {
      throw const CompanyApiException('Mese non valido.');
    }
    final uid = AuthService.instance.currentUid;
    final revision = AuthService.instance.sessionRevision;
    final tenant = SessionService.instance.tenantId;
    final token = await AuthService.instance.requireIdToken();
    final response = await _client.get(
      Uri.parse(ApiService.apiV1Url('/workforce/me/roster/$month/pdf')),
      headers: {'Authorization': 'Bearer $token', 'Accept': 'application/pdf'},
    );
    if (uid != AuthService.instance.currentUid ||
        revision != AuthService.instance.sessionRevision ||
        tenant != SessionService.instance.tenantId) {
      throw const CompanyApiException('Sessione cambiata.');
    }
    if (response.statusCode != 200 ||
        !(response.headers['content-type'] ?? '').contains('application/pdf') ||
        response.bodyBytes.length > 10000000) {
      throw const CompanyApiException(
        'PDF non disponibile. Verifica che il calendario sia pubblicato.',
      );
    }
    return response.bodyBytes;
  }

  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
  }) async {
    final uid = AuthService.instance.currentUid;
    final revision = AuthService.instance.sessionRevision;
    final tenant = SessionService.instance.tenantId;
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
    if (uid != AuthService.instance.currentUid ||
        revision != AuthService.instance.sessionRevision ||
        tenant != SessionService.instance.tenantId) {
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
