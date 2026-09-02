import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:moneylock/data/exchange_rate_service.dart';

void main() {
  test('gets and caches a historical pair quote', () async {
    var calls = 0;
    final service = ExchangeRateService(
      client: MockClient((request) async {
        calls++;
        expect(request.url.path, '/v2/rate/USD/CAD');
        expect(request.url.queryParameters['date'], '2026-09-01');
        return http.Response(
          '{"date":"2026-09-01","base":"USD","quote":"CAD","rate":1.36}',
          200,
        );
      }),
    );

    final first = await service.quote(
      base: 'usd',
      target: 'cad',
      date: DateTime.utc(2026, 9, 1),
    );
    final second = await service.quote(
      base: 'USD',
      target: 'CAD',
      date: DateTime.utc(2026, 9, 1),
    );

    expect(first.rate, 1.36);
    expect(first.asOf, DateTime(2026, 9, 1));
    expect(second.rate, 1.36);
    expect(calls, 1);
  });

  test('uses a rate of one for the same currency without a request', () async {
    final service = ExchangeRateService(
      client: MockClient((_) async => throw StateError('not called')),
    );
    final quote = await service.quote(base: 'CAD', target: 'CAD');
    expect(quote.rate, 1);
  });
}
