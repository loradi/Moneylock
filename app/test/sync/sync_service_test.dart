import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:moneylock/data/transactions_dao.dart';
import 'package:moneylock/sync/api_client.dart';
import 'package:moneylock/sync/sync_service.dart';

import '../helpers/test_database.dart';

void main() {
  test(
    'sync uploads local rows and imports remote rows by stable hash',
    () async {
      final db = createTestDatabase();
      await db.transactionsDao.insertWithDedup(
        NewTransaction(
          amount: 12.5,
          currency: 'CAD',
          merchant: 'Local cafe',
          category: 'Coffee & Dining',
          source: 'manual',
          rawText: 'Local cafe 12.50 CAD',
          timestamp: DateTime.utc(2026, 9, 1),
        ),
      );
      await db.settingsDao.setSyncConfiguration(
        baseUrl: 'https://sync.example.test/',
        apiKey: 'secret',
      );

      final httpClient = MockClient((request) async {
        if (request.method == 'POST') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final sent = body['transactions'] as List<dynamic>;
          expect(request.headers['X-API-Key'], 'secret');
          expect(sent, hasLength(1));
          expect((sent.single as Map<String, dynamic>)['currency'], 'CAD');
          return http.Response('{"inserted": 1, "duplicates": 0}', 200);
        }
        expect(request.url.queryParameters['since'], startsWith('1970-01-01'));
        return http.Response(
          jsonEncode({
            'transactions': [
              {
                'amount': 19.99,
                'currency': 'EUR',
                'merchant': 'Remote shop',
                'category': 'Shopping & E-commerce',
                'source': 'receipt',
                'raw_text': 'Remote shop 19.99 EUR',
                'timestamp': '2026-09-02T10:30:00.000Z',
                'dedup_hash': 'remote-sync-hash-0001',
              },
            ],
          }),
          200,
        );
      });
      final service = SyncService(
        db,
        clientFactory: (url, key) => SyncClient(url, key, client: httpClient),
      );

      final outcome = await service.sync();

      expect(outcome.uploaded, 1);
      expect(outcome.downloaded, 1);
      final rows = await db.transactionsDao.all();
      expect(rows, hasLength(2));
      expect(rows.map((row) => row.currency), contains('EUR'));
      await db.close();
    },
  );

  test('sync rejects a missing configuration before network work', () async {
    final db = createTestDatabase();
    final service = SyncService(db);

    await expectLater(service.sync(), throwsA(isA<StateError>()));
    await db.close();
  });
}
