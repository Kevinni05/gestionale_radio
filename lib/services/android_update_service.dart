import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'api_service.dart';

class AndroidUpdateCheck {
  const AndroidUpdateCheck(
    this.message, {
    this.url,
    this.sha256,
    this.signingSha256,
    this.versionCode,
  });
  final String message;
  final Uri? url;
  final String? sha256, signingSha256;
  final int? versionCode;
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
    if (current['applicationId'] is! String ||
        !RegExp(
          r'^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$',
        ).hasMatch(current['applicationId']) ||
        latest['applicationId'] != current['applicationId'] ||
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
        '${current['displayName'] ?? 'RadioTech'} ${current['versionName']} è aggiornato.',
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
      'È disponibile ${current['displayName'] ?? 'RadioTech'} ${latest['versionName']}. Il download verrà verificato prima di aprire l’installatore Android.',
      url: uri,
      sha256: digest,
      signingSha256: certificate,
      versionCode: code,
    );
  }

  static bool isTrustedDownload(Uri uri) =>
      uri.scheme == 'https' &&
      uri.host == 'github.com' &&
      (uri.port == 443) &&
      uri.userInfo.isEmpty &&
      uri.query.isEmpty &&
      uri.fragment.isEmpty &&
      RegExp(
        r'^/Kevinni05/gestionale_radio/releases/download/v[0-9A-Za-z.\-]+/[A-Za-z0-9][0-9A-Za-z._\-]*-[0-9A-Za-z.\-]+\.apk$',
      ).hasMatch(uri.path);
  static Future<void> installVerifiedUpdate(AndroidUpdateCheck update) async {
    final uri = update.url;
    if (uri == null ||
        !isTrustedDownload(uri) ||
        update.sha256 == null ||
        update.signingSha256 == null ||
        update.versionCode == null) {
      throw const FormatException('Download non consentito.');
    }
    await _channel.invokeMethod('installVerifiedUpdate', {
      'url': uri.toString(),
      'sha256': update.sha256,
      'signingSha256': update.signingSha256,
      'versionCode': update.versionCode,
    });
  }
}
