import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:gestionale_radio/services/qr_login_service.dart';

void main() {
  test(
    'versioned operator badge carries a validated HTTPS server without redirecting raw tokens',
    () {
      expect(
        QrLoginService.readServerUrl(
          '{"type":"radiotech-operator","version":2,"serverUrl":"https://central.example.org/","token":"badge"}',
        ),
        'https://central.example.org',
      );
      expect(
        QrLoginService.readToken(
          '{"type":"radiotech-operator","version":2,"serverUrl":"https://central.example.org","token":"badge"}',
        ),
        'badge',
      );
      expect(QrLoginService.readServerUrl('legacy-badge'), isNull);
      for (final server in [
        'http://central.example.org',
        'https://user:password@central.example.org',
        'https://central.example.org/api',
        'https://central.example.org?token=x',
      ]) {
        expect(
          () => QrLoginService.readServerUrl(
            jsonEncode({
              'type': 'radiotech-operator',
              'version': 2,
              'serverUrl': server,
              'token': 'badge',
            }),
          ),
          throwsA(isA<QrLoginFailure>()),
        );
      }
    },
  );
  const base = 'http://192.168.1.227:8080';
  test(
    'exchanges raw, JSON and URL badges against the configured backend',
    () async {
      final client = MockClient((request) async {
        expect(request.url.toString(), '$base/api/v1/auth/qr-login');
        expect(jsonDecode(request.body), {'qrToken': 'badge-token'});
        return http.Response('{"success":true,"customToken":"session"}', 200);
      });
      final service = QrLoginService(client: client);
      for (final qr in [
        ' badge-token ',
        '{"token":"badge-token"}',
        'https://example.org/login?token=badge-token&other=value',
      ]) {
        expect(await service.exchange(qr, baseUrl: base), 'session');
      }
    },
  );
  test('accepts the wrapped API response', () async {
    final service = QrLoginService(
      client: MockClient(
        (_) async => http.Response(
          '{"success":true,"data":{"customToken":"session"}}',
          200,
        ),
      ),
    );
    expect(await service.exchange('badge', baseUrl: base), 'session');
  });
  test(
    'timeout explains backend configuration and never retries the badge',
    () async {
      var calls = 0;
      final service = QrLoginService(
        client: MockClient((_) async {
          calls++;
          throw TimeoutException('Future not completed');
        }),
      );
      await expectLater(
        service.exchange('badge', baseUrl: base),
        throwsA(
          isA<QrLoginFailure>()
              .having((e) => e.connection, 'connection', true)
              .having(
                (e) => e.message,
                'instructions',
                contains('Configura Server Backend'),
              )
              .having((e) => e.message, 'target server', contains(base)),
        ),
      );
      expect(calls, 1);
    },
  );
  test('unreachable backend is distinct from rejected credentials', () async {
    final service = QrLoginService(
      client: MockClient((_) async {
        throw http.ClientException('Connection refused');
      }),
    );
    await expectLater(
      service.exchange('badge', baseUrl: base),
      throwsA(
        isA<QrLoginFailure>().having((e) => e.connection, 'connection', true),
      ),
    );
  });
  test('expired badge preserves the message returned by the backend', () async {
    final service = QrLoginService(
      client: MockClient(
        (_) async => http.Response(
          '{"success":false,"message":"Badge scaduto. Rigenera il QR."}',
          401,
        ),
      ),
    );
    await expectLater(
      service.exchange('badge', baseUrl: base),
      throwsA(
        isA<QrLoginFailure>()
            .having((e) => e.connection, 'connection', false)
            .having(
              (e) => e.message,
              'message',
              'Badge scaduto. Rigenera il QR.',
            ),
      ),
    );
  });
  test('HTML server response explains wrong backend', () async {
    final service = QrLoginService(
      client: MockClient(
        (_) async => http.Response('<html>Hosting</html>', 200),
      ),
    );
    await expectLater(
      service.exchange('badge', baseUrl: base),
      throwsA(
        isA<QrLoginFailure>().having((e) => e.connection, 'connection', true),
      ),
    );
  });
  test('blank badges never reach the network', () async {
    var calls = 0;
    final service = QrLoginService(
      client: MockClient((_) async {
        calls++;
        return http.Response('{}', 200);
      }),
    );
    await expectLater(
      service.exchange(' ', baseUrl: base),
      throwsA(isA<QrLoginFailure>()),
    );
    expect(calls, 0);
  });
  test(
    'missing custom session token is rejected before Firebase login',
    () async {
      final service = QrLoginService(
        client: MockClient((_) async => http.Response('{"success":true}', 200)),
      );
      await expectLater(
        service.exchange('badge', baseUrl: base),
        throwsA(isA<QrLoginFailure>()),
      );
    },
  );
}
