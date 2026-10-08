import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:gestionale_radio/services/api_http_client.dart';

void main() {
  test(
    'refreshes expired authentication once, preserving idempotency and payload',
    () async {
      var calls = 0;
      final client = ApiHttpClient(
        refreshToken: () async => 'fresh-token',
        retryDelays: const [],
        inner: MockClient((request) async {
          expect(request.followRedirects, isFalse);
          expect(request.headers['Idempotency-Key'], 'same-operation');
          expect(request.body, '{"status":"ACCEPTED"}');
          calls++;
          if (calls == 1) return http.Response('{}', 401);
          expect(request.headers['Authorization'], 'Bearer fresh-token');
          return http.Response('{}', 200);
        }),
      );
      addTearDown(client.close);
      final response = await client.post(
        Uri.parse('https://api.example.org/api/v1/tasks'),
        headers: {
          'Authorization': 'Bearer expired',
          'Idempotency-Key': 'same-operation',
        },
        body: '{"status":"ACCEPTED"}',
      );
      expect(response.statusCode, 200);
      expect(calls, 2);
    },
  );

  test('does not retry a failed second authentication or follow redirects', () async {
    var calls = 0;
    final client = ApiHttpClient(
      refreshToken: () async => 'fresh',
      retryDelays: const [],
      inner: MockClient((request) async {
        calls++;
        expect(request.followRedirects, isFalse);
        return http.Response('{}', 401);
      }),
    );
    addTearDown(client.close);
    expect(
      (await client.get(
        Uri.parse('https://api.example.org'),
        headers: {'Authorization': 'Bearer expired'},
      )).statusCode,
      401,
    );
    expect(calls, 2);
  });

  test('retries transient GET failures and preserves response semantics', () async {
    var calls = 0;
    final client = ApiHttpClient(
      retryDelays: const [Duration.zero, Duration.zero],
      inner: MockClient((request) async {
        calls++;
        if (calls < 3) return http.Response('busy', 503);
        return http.Response('ok', 200);
      }),
    );
    addTearDown(client.close);

    final response = await client.get(Uri.parse('https://api.example.org/health'));

    expect(response.statusCode, 200);
    expect(response.body, 'ok');
    expect(calls, 3);
  });

  test('retries keyed POST but never replays an unsafe POST', () async {
    var keyedCalls = 0;
    final keyed = ApiHttpClient(
      retryDelays: const [Duration.zero],
      inner: MockClient((request) async {
        keyedCalls++;
        return http.Response('{}', keyedCalls == 1 ? 504 : 200);
      }),
    );
    addTearDown(keyed.close);
    expect(
      (
        await keyed.post(
          Uri.parse('https://api.example.org/report'),
          headers: {'Idempotency-Key': 'report-1'},
          body: '{}',
        )
      ).statusCode,
      200,
    );
    expect(keyedCalls, 2);

    var unsafeCalls = 0;
    final unsafe = ApiHttpClient(
      retryDelays: const [Duration.zero],
      inner: MockClient((request) async {
        unsafeCalls++;
        return http.Response('{}', 503);
      }),
    );
    addTearDown(unsafe.close);
    expect(
      (await unsafe.post(Uri.parse('https://api.example.org/create'))).statusCode,
      503,
    );
    expect(unsafeCalls, 1);
  });

  test('retries a replay-safe timeout and succeeds', () async {
    var calls = 0;
    final client = ApiHttpClient(
      requestTimeout: const Duration(milliseconds: 10),
      retryDelays: const [Duration.zero],
      inner: MockClient((request) async {
        calls++;
        if (calls == 1) {
          await Future<void>.delayed(const Duration(milliseconds: 30));
        }
        return http.Response('{}', 200);
      }),
    );
    addTearDown(client.close);

    expect(
      (await client.get(Uri.parse('https://api.example.org/data'))).statusCode,
      200,
    );
    expect(calls, 2);
  });
}
