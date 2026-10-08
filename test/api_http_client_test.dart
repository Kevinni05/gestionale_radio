import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:gestionale_radio/services/api_http_client.dart';

void main() {
  test('refreshes expired authentication once, preserving idempotency and payload', () async {
    var calls = 0;
    final client = ApiHttpClient(refreshToken: () async => 'fresh-token', inner: MockClient((request) async {
      expect(request.followRedirects, isFalse);
      expect(request.headers['Idempotency-Key'], 'same-operation');
      expect(request.body, '{"status":"ACCEPTED"}');
      calls++;
      if (calls == 1) return http.Response('{}', 401);
      expect(request.headers['Authorization'], 'Bearer fresh-token');
      return http.Response('{}', 200);
    }));
    addTearDown(client.close);
    final response = await client.post(Uri.parse('https://api.example.org/api/v1/tasks'), headers: {'Authorization': 'Bearer expired', 'Idempotency-Key': 'same-operation'}, body: '{"status":"ACCEPTED"}');
    expect(response.statusCode, 200);
    expect(calls, 2);
  });
  test('does not retry a failed second authentication or follow redirects', () async {
    var calls = 0;
    final client = ApiHttpClient(refreshToken: () async => 'fresh', inner: MockClient((request) async {
      calls++; expect(request.followRedirects, isFalse); return http.Response('{}', 401);
    }));
    addTearDown(client.close);
    expect((await client.get(Uri.parse('https://api.example.org'), headers: {'Authorization': 'Bearer expired'})).statusCode, 401);
    expect(calls, 2);
  });
}
