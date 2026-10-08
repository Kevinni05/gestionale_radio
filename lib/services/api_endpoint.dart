import 'package:flutter/foundation.dart';

class ApiEndpoint {
  static String normalize(String value, {bool release = kReleaseMode}) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        !{'http', 'https'}.contains(uri.scheme) ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      throw const FormatException(
        'Inserisci un URL completo del server, senza percorsi o credenziali.',
      );
    }
    if (release &&
        (uri.scheme != 'https' ||
            uri.host == 'localhost' ||
            uri.host == '127.0.0.1' ||
            uri.host == '10.0.2.2' ||
            uri.host.endsWith('.invalid'))) {
      throw const FormatException(
        'Il rilascio richiede un endpoint di produzione HTTPS.',
      );
    }
    return uri.replace(path: '').toString();
  }
}
