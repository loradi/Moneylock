import 'dart:convert';

import 'package:http/http.dart' as http;

class ExchangeRateQuote {
  const ExchangeRateQuote({
    required this.base,
    required this.quote,
    required this.rate,
    required this.asOf,
  });

  final String base;
  final String quote;
  final double rate;
  final DateTime asOf;
}

/// Retrieves a suggested fiat rate from Frankfurter's public reference-rate
/// endpoint. The app still asks the user to confirm before changing money.
class ExchangeRateService {
  ExchangeRateService({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;
  final _cache = <String, ExchangeRateQuote>{};

  Future<ExchangeRateQuote> quote({
    required String base,
    required String target,
    DateTime? date,
  }) async {
    final normalizedBase = base.toUpperCase();
    final normalizedTarget = target.toUpperCase();
    if (normalizedBase == normalizedTarget) {
      return ExchangeRateQuote(
        base: normalizedBase,
        quote: normalizedTarget,
        rate: 1,
        asOf: date ?? DateTime.now(),
      );
    }
    final datePart = date == null
        ? ''
        : '?date=${date.toUtc().toIso8601String().substring(0, 10)}';
    final key = '$normalizedBase/$normalizedTarget$datePart';
    final cached = _cache[key];
    if (cached != null) return cached;
    final response = await _client
        .get(
          Uri.parse(
            'https://api.frankfurter.dev/v2/rate/$normalizedBase/$normalizedTarget$datePart',
          ),
        )
        .timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) {
      throw StateError('Rate lookup failed (${response.statusCode}).');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final rate = (body['rate'] as num?)?.toDouble();
    final asOf = DateTime.tryParse(body['date'] as String? ?? '');
    if (rate == null || !rate.isFinite || rate <= 0 || asOf == null) {
      throw const FormatException('Rate response was invalid.');
    }
    final result = ExchangeRateQuote(
      base: normalizedBase,
      quote: normalizedTarget,
      rate: rate,
      asOf: asOf,
    );
    _cache[key] = result;
    return result;
  }
}
