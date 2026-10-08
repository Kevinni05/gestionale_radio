import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'auth_service.dart';

/// API requests have bounded waits, never forward credentials via redirects,
/// refresh an expired token once, and retry only replay-safe requests.
class ApiHttpClient extends http.BaseClient {
  ApiHttpClient({
    http.Client? inner,
    Future<String?> Function()? refreshToken,
    this.requestTimeout = timeout,
    List<Duration>? retryDelays,
  }) : _inner = inner ?? http.Client(),
       _refreshToken = refreshToken ?? AuthService.instance.refreshIdToken,
       _retryDelays = retryDelays ?? const [
         Duration(milliseconds: 300),
         Duration(milliseconds: 900),
       ];

  final http.Client _inner;
  final Future<String?> Function() _refreshToken;
  final List<Duration> _retryDelays;
  static const timeout = Duration(seconds: 65);
  final Duration requestTimeout;
  static final http.Client instance = ApiHttpClient();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request is! http.Request) {
      request.followRedirects = false;
      return _inner.send(request).timeout(requestTimeout);
    }

    final actor = AuthService.instance.currentUid;
    final replaySafe = _isReplaySafe(request);

    http.Request copy({String? token}) {
      final clone = http.Request(request.method, request.url)
        ..headers.addAll(request.headers)
        ..bodyBytes = request.bodyBytes
        ..followRedirects = false;
      if (token != null) {
        clone.headers['Authorization'] = 'Bearer $token';
      }
      return clone;
    }

    var response = await _sendWithRetry(
      () => copy(),
      replaySafe: replaySafe,
    );

    if (response.statusCode == 401 &&
        request.headers.containsKey('Authorization')) {
      await response.stream.drain<void>().timeout(requestTimeout);
      final token = await _refreshToken().timeout(requestTimeout);
      if (token != null && actor == AuthService.instance.currentUid) {
        response = await _sendWithRetry(
          () => copy(token: token),
          replaySafe: replaySafe,
        );
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

  Future<http.StreamedResponse> _sendWithRetry(
    http.Request Function() requestFactory, {
    required bool replaySafe,
  }) async {
    var attempt = 0;
    while (true) {
      try {
        final response = await _inner
            .send(requestFactory())
            .timeout(requestTimeout);
        if (!replaySafe ||
            !_retryableStatus(response.statusCode) ||
            attempt >= _retryDelays.length) {
          return response;
        }

        final retryAfter = _retryAfter(response);
        await response.stream.drain<void>().timeout(requestTimeout);
        await Future<void>.delayed(retryAfter ?? _retryDelays[attempt]);
        attempt++;
      } on TimeoutException {
        if (!replaySafe || attempt >= _retryDelays.length) rethrow;
        await Future<void>.delayed(_retryDelays[attempt++]);
      } on SocketException {
        if (!replaySafe || attempt >= _retryDelays.length) rethrow;
        await Future<void>.delayed(_retryDelays[attempt++]);
      } on http.ClientException {
        if (!replaySafe || attempt >= _retryDelays.length) rethrow;
        await Future<void>.delayed(_retryDelays[attempt++]);
      }
    }
  }

  bool _isReplaySafe(http.Request request) {
    final method = request.method.toUpperCase();
    if (const {'GET', 'HEAD', 'OPTIONS'}.contains(method)) {
      return true;
    }
    final key = request.headers['Idempotency-Key']?.trim();
    return key != null && key.isNotEmpty;
  }

  bool _retryableStatus(int status) =>
      const {408, 425, 429, 500, 502, 503, 504}.contains(status);

  Duration? _retryAfter(http.StreamedResponse response) {
    final raw = response.headers['retry-after'];
    final seconds = raw == null ? null : int.tryParse(raw.trim());
    if (seconds == null || seconds < 0 || seconds > 30) {
      return null;
    }
    return Duration(seconds: seconds);
  }

  @override
  void close() => _inner.close();
}
