import 'package:flutter_test/flutter_test.dart';
import 'package:gestionale_radio/services/session_service.dart';

void main() {
  test('legacy chief and enterprise identities can enter the mobile app', () {
    for (final role in [
      'CAPO',
      'CHIEF_EXECUTIVE',
      'CUSTOMER',
      'NETWORK_MANAGER',
      'ENGINEER',
      'VIEWER',
      'OPERATOR',
    ]) {
      expect(SessionService.isAppRole(role), isTrue);
    }
    expect(SessionService.isAppRole('unknown'), isFalse);
    expect(SessionService.isAppRole(null), isFalse);
  });
}
