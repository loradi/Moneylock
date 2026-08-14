import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class SyncStats {
  final int inserted;
  final int duplicates;
  SyncStats(this.inserted, this.duplicates);
}

class SyncClient {
  final String baseUrl;
  final String apiKey;
  final http.Client _client;

  SyncClient(this.baseUrl, this.apiKey, {http.Client? client})
      : _client = client ?? http.Client();

  Future<SyncStats> push(List<Map<String, dynamic>> txs) =>
      _withRetry(() async {
        final r = await _client.post(
            Uri.parse('$baseUrl/sync/transactions'),
            headers: {'Content-Type': 'application/json', 'X-API-Key': apiKey},
            body: jsonEncode({'transactions': txs}));
        if (r.statusCode != 200) throw Exception('sync push ${r.statusCode}');
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        return SyncStats(j['inserted'] as int, j['duplicates'] as int);
      });

  Future<List<Map<String, dynamic>>> pull(DateTime since) =>
      _withRetry(() async {
        final r = await _client.get(
            Uri.parse(
                '$baseUrl/sync/transactions?since=${since.toUtc().toIso8601String()}'),
            headers: {'X-API-Key': apiKey});
        if (r.statusCode != 200) throw Exception('sync pull ${r.statusCode}');
        return (jsonDecode(r.body)['transactions'] as List)
            .cast<Map<String, dynamic>>();
      });

  Future<T> _withRetry<T>(Future<T> Function() fn) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        return await fn();
      } catch (_) {
        if (attempt == 2) rethrow;
        await Future.delayed(Duration(seconds: attempt == 0 ? 1 : 3));
      }
    }
    throw StateError('unreachable');
  }
}