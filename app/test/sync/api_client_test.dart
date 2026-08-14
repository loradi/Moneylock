import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:moneylock/sync/api_client.dart';

void main() {
  test('push manda X-API-Key y parsea SyncStats', () async {
    late http.Request captured;
    final client = MockClient((req) async {
      captured = req;
      return http.Response('{"inserted": 2, "duplicates": 1}', 200);
    });
    final sync = SyncClient('http://localhost:8000', 'k', client: client);
    final stats = await sync.push([
      {'amount': 12.5}
    ]);
    expect(stats.inserted, 2);
    expect(stats.duplicates, 1);
    expect(captured.headers['X-API-Key'], 'k');
    expect(jsonDecode(captured.body)['transactions'], hasLength(1));
  });

  test('pull manda since UTC y devuelve lista', () async {
    final client = MockClient((req) async {
      expect(req.url.path, '/sync/transactions');
      expect(req.url.queryParameters['since'], startsWith('2026-01-01'));
      return http.Response(
          '{"transactions": [{"amount": 1.0}]}',
          200,
          headers: {'content-type': 'application/json'});
    });
    final sync = SyncClient('http://localhost:8000', 'k', client: client);
    final txs = await sync.pull(DateTime.utc(2026, 1, 1));
    expect(txs, hasLength(1));
  });

  test('reintenta tras un 500 y lanza al tercer intento', () async {
    var calls = 0;
    final client = MockClient((req) async {
      calls++;
      if (calls < 3) return http.Response('boom', 500);
      return http.Response('{"inserted": 0, "duplicates": 0}', 200);
    });
    final sync = SyncClient('http://localhost:8000', 'k', client: client);
    final stats = await sync.push([]);
    expect(stats.inserted, 0);
    expect(calls, 3);
  });

  test('pull falla con error tras reintentos', () async {
    final client = MockClient((_) async => http.Response('boom', 500));
    final sync = SyncClient('http://localhost:8000', 'k', client: client);
    expect(() => sync.pull(DateTime.utc(2026)), throwsA(isA<Exception>()));
  });
}