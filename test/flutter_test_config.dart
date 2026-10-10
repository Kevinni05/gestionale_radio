import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'support/protected_local_mock.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  installProtectedLocalMock();
  await testMain();
}
