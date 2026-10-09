import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'app_branding.dart';

class QrLoginFailure implements Exception {
  const QrLoginFailure(this.message, {this.connection = false});
  final String message;
  final bool connection;
  @override
  String toString() => message;
}

class QrLoginService {
  QrLoginService({
    required this.client,
    this.timeout = const Duration(seconds: 20),
  });
  final http.Client client;
  final Duration timeout;

  static String? readServerUrl(String raw) {
    dynamic value;
    try {
      value = jsonDecode(raw.trim());
    } on FormatException {
      return null;
    }
    if (value is! Map ||
        value['type'] != 'radiotech-operator' ||
        value['version'] != 2) {
      return null;
    }
    final uri = Uri.tryParse(value['serverUrl']?.toString() ?? '');
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const QrLoginFailure(
        'Indirizzo HTTPS della centrale nel QR non valido.',
      );
    }
    return uri.toString().replaceAll(RegExp(r'/+$'), '');
  }

  static String readToken(String raw) {
    var token = raw.trim();
    try {
      final value = jsonDecode(token);
      if (value is Map && value['token'] is String) {
        token = value['token'] as String;
      }
    } on FormatException {
      final uri = Uri.tryParse(token);
      token = uri?.queryParameters['token'] ?? token;
    }
    if (token.trim().isEmpty) {
      throw const QrLoginFailure('Codice QR operatore non valido.');
    }
    return token.trim();
  }

  Future<String> exchange(String raw, {required String baseUrl}) async {
    final token = readToken(raw);
    http.Response response;
    try {
      response = await client
          .post(
            Uri.parse('$baseUrl/api/v1/auth/qr-login'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'qrToken': token}),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw QrLoginFailure(
        'La centrale $baseUrl non risponde. Torna al login e apri '
        'Configura Server Backend: usa l’indirizzo HTTPS pubblico della centrale '
        'per accedere anche da rete mobile. Gli indirizzi locali funzionano solo nella stessa Wi-Fi. '
        'Premi Prova connessione e salva prima di riprovare.',
        connection: true,
      );
    } on SocketException {
      throw QrLoginFailure(
        'Impossibile raggiungere $baseUrl. Controlla la '
        'Wi-Fi e Configura Server Backend nella schermata di accesso.',
        connection: true,
      );
    } on http.ClientException {
      throw QrLoginFailure(
        'Connessione a $baseUrl non riuscita. Controlla '
        'l’indirizzo in Configura Server Backend e prova la connessione.',
        connection: true,
      );
    }
    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw QrLoginFailure(
        'Il server non restituisce una risposta '
        '${AppBranding.name} valida. Controlla l’indirizzo del backend.',
        connection: true,
      );
    }
    if (response.statusCode != 200 ||
        decoded is! Map ||
        decoded['success'] != true) {
      throw QrLoginFailure(
        decoded is Map && decoded['message'] is String
            ? decoded['message'] as String
            : 'Accesso QR non riuscito (HTTP ${response.statusCode}).',
      );
    }
    final payload = decoded['data'] is Map ? decoded['data'] as Map : decoded;
    final customToken = payload['customToken'];
    if (customToken is! String || customToken.isEmpty) {
      throw const QrLoginFailure('Token di sessione non valido dal server.');
    }
    return customToken;
  }
}
