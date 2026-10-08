import 'dart:async';
import 'package:http/http.dart' as http;
import 'auth_service.dart';

/// API requests have bounded waits and never forward credentials via redirects.
class ApiHttpClient extends http.BaseClient {
  ApiHttpClient({
    http.Client? inner,
    Future<String?> Function()? refreshToken,
    this.requestTimeout = timeout,
  }) : _inner = inner ?? http.Client(),
       _refreshToken = refreshToken ?? AuthService.instance.refreshIdToken;

  final http.Client _inner;
  final Future<String?> Function() _refreshToken;
  static const timeout = Duration(seconds: 65);
  final Duration requestTimeout;
  static final http.Client instance = ApiHttpClient();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    // BaseClient's get/post helpers use Request. Streamed uploads are not replayed.
    if (request is! http.Request) {
      request.followRedirects = false;
      return _inner.send(request).timeout(requestTimeout);
    }
    final actor = AuthService.instance.currentUid;
    http.Request copy({String? token}) {
      final clone = http.Request(request.method, request.url)
        ..headers.addAll(request.headers)
        ..bodyBytes = request.bodyBytes
        ..followRedirects = false;
      if (token != null) clone.headers['Authorization'] = 'Bearer $token';
      return clone;
    }

    var response = await _inner.send(copy()).timeout(requestTimeout);
    if (response.statusCode == 401 &&
        request.headers.containsKey('Authorization')) {
      await response.stream.drain<void>().timeout(requestTimeout);
      final token = await _refreshToken().timeout(requestTimeout);
      if (token != null && actor == AuthService.instance.currentUid) {
        response = await _inner
            .send(copy(token: token))
            .timeout(requestTimeout);
      } else {
        throw StateError('Sessione scaduta. Accedi nuovamente.');
      }
    }
    return http.StreamedResponse(
      response.stream.timeout(requestTimeout),
      response.statusCode,
      contentLength: response.contentLength,
      request: response.request,
      headers: response.headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
    );
  }

  @override
  void close() => _inner.close();
}
