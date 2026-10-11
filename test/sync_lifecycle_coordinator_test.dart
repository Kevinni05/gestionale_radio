import 'dart:async';
import 'package:fake_async/fake_async.dart';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestionale_radio/services/sync_lifecycle_coordinator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('start, resume and network recovery coalesce without overlapping', () {
    fakeAsync((clock) {
      final network = StreamController<bool>();
      final first = Completer<void>();
      final attempts = <bool>[];
      final coordinator = SyncLifecycleCoordinator(
        networkChanges: network.stream,
        retry: (force) async {
          attempts.add(force);
          if (attempts.length == 1) await first.future;
        },
      );
      coordinator.start();
      coordinator.start();
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 1));
      clock.flushMicrotasks();
      expect(attempts, [false]);
      network.add(false);
      network.add(true);
      network.add(true);
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 1));
      clock.flushMicrotasks();
      expect(attempts, [false]);
      first.complete();
      clock.flushMicrotasks();
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 1));
      clock.flushMicrotasks();
      expect(attempts, [false, true]);
      coordinator.didChangeAppLifecycleState(AppLifecycleState.paused);
      network.add(false);
      network.add(true);
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 1));
      clock.flushMicrotasks();
      expect(attempts.length, 2);
      coordinator.didChangeAppLifecycleState(AppLifecycleState.resumed);
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 1));
      clock.flushMicrotasks();
      expect(attempts, [false, true, true]);
      unawaited(coordinator.dispose());
      clock.flushMicrotasks();
      network.add(false);
      network.add(true);
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 1));
      clock.flushMicrotasks();
      expect(attempts.length, 3);
      unawaited(network.close());
      clock.flushMicrotasks();
    });
  });

  test('dependency errors are reported and a subsequent resume retries', () {
    fakeAsync((clock) {
      final errors = <Object>[];
      var attempts = 0;
      final coordinator = SyncLifecycleCoordinator(
        networkChanges: const Stream.empty(),
        retry: (_) async {
          if (++attempts == 1) throw StateError('storage unavailable');
        },
        onError: errors.add,
      );
      coordinator.start();
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 1));
      clock.flushMicrotasks();
      expect(errors, hasLength(1));
      coordinator.didChangeAppLifecycleState(AppLifecycleState.resumed);
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 1));
      clock.flushMicrotasks();
      expect(attempts, 2);
      unawaited(coordinator.dispose());
      clock.flushMicrotasks();
    });
  });
}
