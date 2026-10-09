import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'api_service.dart';

class AndroidUpdateCheck {
  const AndroidUpdateCheck(this.message, {this.url});
  final String message;
  final Uri? url;
}

class AndroidUpdateService {
  AndroidUpdateService({
    Future<Map> Function()? installedApp,
    Future<Map> Function()? manifest,
  }) : _installedApp = installedApp ?? _installed,
       _manifest = manifest ?? _latest;
  static const _channel = MethodChannel('radiotech/updates');
  final Future<Map> Function() _installedApp, _manifest;
  static Future<Map> _installed() async =>
      (await _channel.invokeMapMethod<String, dynamic>('installedApp'))!;
  static Future<Map> _latest() async {
    final client = http.Client();
    try {
      final request = http.Request(
        'GET',
        Uri.parse('${ApiService.baseUrl}/api/v1/mobile/releases/latest'),
      )..followRedirects = false;
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 65));
      if (response.statusCode != 200) {
        throw StateError('Canale aggiornamenti non disponibile.');
      }
      final bytes = <int>[];
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 10),
      )) {
        if (bytes.length + chunk.length > 16384) {
          throw const FormatException('Manifest troppo grande.');
        }
        bytes.addAll(chunk);
      }
      final result = jsonDecode(utf8.decode(bytes));
      if (result is! Map) {
        throw const FormatException('Manifest aggiornamenti non valido.');
      }
      return result;
    } finally {
      client.close();
    }
  }

  Future<AndroidUpdateCheck> check() async {
    final current = await _installedApp();
    final latest = await _manifest();
    if (latest['available'] != true) {
      return const AndroidUpdateCheck(
        'Nessun aggiornamento pubblicato nel canale di produzione.',
      );
    }
    final code = latest['versionCode'];
    final certificate = latest['signingSha256']?.toString().toLowerCase();
    final digest = latest['sha256']?.toString().toLowerCase();
    if (latest['applicationId'] != 'com.example.gestionale_radio' ||
        code is! int ||
        code < 1 ||
        certificate == null ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(certificate) ||
        digest == null ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(digest)) {
      throw const FormatException('Aggiornamento non valido.');
    }
    if ((current['versionCode'] as num).toInt() >= code) {
      return AndroidUpdateCheck(
        'RadioTech ${current['versionName']} è aggiornato.',
      );
    }
    final uri = Uri.tryParse(latest['downloadUrl']?.toString() ?? '');
    if (uri == null || !isTrustedDownload(uri)) {
      throw const FormatException('Indirizzo aggiornamento non consentito.');
    }
    final signatures = (current['signingSha256'] as List).map(
      (value) => value.toString().toLowerCase(),
    );
    if (!signatures.contains(certificate)) {
      return const AndroidUpdateCheck(
        'La versione installata usa una firma diversa. Il passaggio alla produzione richiede una nuova installazione e la conservazione preventiva dei dati locali.',
      );
    }
    return AndroidUpdateCheck(
      'È disponibile RadioTech ${latest['versionName']}. Apri il download per aggiornare l’app.',
      url: uri,
    );
  }

  static bool isTrustedDownload(Uri uri) =>
      uri.scheme == 'https' &&
      uri.host == 'github.com' &&
      uri.userInfo.isEmpty &&
      uri.query.isEmpty &&
      uri.fragment.isEmpty &&
      RegExp(
        r'^/Kevinni05/gestionale_radio/releases/download/v[0-9A-Za-z.\-]+/RadioTech-[0-9A-Za-z.\-]+\.apk$',
      ).hasMatch(uri.path);
  static Future<void> openDownload(Uri uri) async {
    if (!isTrustedDownload(uri)) {
      throw const FormatException('Download non consentito.');
    }
    await _channel.invokeMethod('openDownload', {'url': uri.toString()});
  }
}
