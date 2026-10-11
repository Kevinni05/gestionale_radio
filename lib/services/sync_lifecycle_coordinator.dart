import 'dart:async';

import 'package:flutter/widgets.dart';

/// Foreground triggers are hints to retry, never proof of server receipt.
/// The queue executor retains responsibility for identity and idempotency.
class SyncLifecycleCoordinator with WidgetsBindingObserver {
  SyncLifecycleCoordinator({
    required this.networkChanges,
    required this.retry,
    this.onError,
    this.debounce = const Duration(milliseconds: 500),
  });

  final Stream<bool> networkChanges;
  final Future<void> Function(bool force) retry;
  final void Function(Object error)? onError;
  final Duration debounce;
  StreamSubscription<bool>? _subscription;
  Timer? _timer;
  bool _started = false;
  bool _foreground = true;
  bool _running = false;
  bool _requested = false;
  bool _force = false;

  void start() {
    if (_started) return;
    _started = true;
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    _subscription = networkChanges.distinct().listen((available) {
      if (available) request(force: true);
    }, onError: (Object error) => onError?.call(error));
    request();
  }

  void request({bool force = false}) {
    if (!_started || !_foreground) return;
    _requested = true;
    _force = _force || force;
    if (_running || _timer != null) return;
    _timer = Timer(debounce, () {
      _timer = null;
      unawaited(_drain());
    });
  }

  Future<void> _drain() async {
    if (!_started || !_foreground || !_requested || _running) return;
    _running = true;
    final force = _force;
    _force = false;
    _requested = false;
    try {
      await retry(force);
    } catch (error) {
      onError?.call(error);
    } finally {
      _running = false;
      if (_requested) request();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      request(force: true);
    } else {
      _timer?.cancel();
      _timer = null;
      _requested = false;
      _force = false;
    }
  }

  Future<void> dispose() async {
    _started = false;
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _timer = null;
    await _subscription?.cancel();
    _subscription = null;
  }
}
