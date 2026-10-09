import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'api_service.dart';

enum ApiConnectionStatus { checking, online, offline }

/// Shows reachability of RadioTech, including a Wi-Fi network without Internet.
class ApiConnectionController extends ChangeNotifier {
  ApiConnectionController({Future<bool> Function()? probe})
    : _probe = probe ?? _health;
  final Future<bool> Function() _probe;
  ApiConnectionStatus status = ApiConnectionStatus.checking;
  Timer? _timer;
  int _generation = 0;
  bool _active = false, _checking = false;

  static Future<bool> _health() async {
    final client = http.Client();
    try {
      final request = http.Request(
        'GET',
        Uri.parse('${ApiService.baseUrl}/api/v1/health'),
      )..followRedirects = false;
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 65));
      if (response.statusCode != 200) return false;
      final body = await response.stream.bytesToString().timeout(
        const Duration(seconds: 10),
      );
      final data = jsonDecode(body);
      return data is Map &&
          data['status'] == 'UP' &&
          data['service'] == 'radiotech-backend';
    } catch (_) {
      return false;
    } finally {
      client.close();
    }
  }

  void resume() {
    if (_active) return;
    _active = true;
    status = ApiConnectionStatus.checking;
    notifyListeners();
    _timer = Timer.periodic(const Duration(seconds: 60), (_) => check());
    unawaited(check());
  }

  void pause() {
    _active = false;
    _generation++;
    _checking = false;
    _timer?.cancel();
    _timer = null;
  }

  Future<void> check() async {
    if (!_active || _checking) return;
    _checking = true;
    final generation = _generation;
    bool online;
    try {
      online = await _probe();
    } catch (_) {
      online = false;
    }
    if (!_active || generation != _generation) return;
    _checking = false;
    status = online ? ApiConnectionStatus.online : ApiConnectionStatus.offline;
    notifyListeners();
  }

  @override
  void dispose() {
    pause();
    super.dispose();
  }
}
