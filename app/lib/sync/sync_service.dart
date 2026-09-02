import '../data/db.dart';
import 'api_client.dart';
import 'sync_credential_store.dart';
import 'sync_profile.dart';

class SyncOutcome {
  const SyncOutcome({
    required this.uploaded,
    required this.duplicates,
    required this.downloaded,
    required this.profileConflicts,
  });

  final int uploaded;
  final int duplicates;
  final int downloaded;
  final int profileConflicts;
}

typedef SyncClientFactory = SyncClient Function(String baseUrl, String apiKey);

/// Synchronizes transactions and the user's financial setup. Mentor chats and
/// on-device model data intentionally remain local to the device.
class SyncService {
  SyncService(
    this._db, {
    required this.credentialStore,
    SyncClientFactory? clientFactory,
  }) : _clientFactory = clientFactory ?? ((url, key) => SyncClient(url, key));

  final AppDatabase _db;
  final SyncCredentialStore credentialStore;
  final SyncClientFactory _clientFactory;

  Future<SyncOutcome> sync() async {
    final config = await _db.settingsDao.syncConfiguration();
    final baseUrl = config.baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    await _db.settingsDao.migrateLegacySyncApiKey(credentialStore.writeApiKey);
    final apiKey = (await credentialStore.readApiKey()).trim();
    if (baseUrl.isEmpty || apiKey.isEmpty) {
      throw StateError('Add your sync server URL and API key first.');
    }
    final server = Uri.tryParse(baseUrl);
    if (server == null || !server.hasScheme || server.host.isEmpty) {
      throw StateError('Enter a valid server URL, including https://.');
    }

    final client = _clientFactory(baseUrl, apiKey);
    final local = await _db.transactionsDao.all();
    final pushed = await client.push([
      for (final transaction in local)
        {
          'amount': transaction.amount,
          'currency': transaction.currency,
          'merchant': transaction.merchant,
          'category': transaction.category,
          'source': transaction.source,
          'raw_text': transaction.rawText,
          'timestamp': transaction.timestamp.toUtc().toIso8601String(),
          'dedup_hash': transaction.dedupHash,
        },
    ]);

    // The server is deduplicated by hash, so a full pull is safe and avoids
    // losing a record whose device clock was previously wrong.
    final remote = await client.pull(DateTime.utc(1970));
    var downloaded = 0;
    for (final transaction in remote) {
      final inserted = await _db.transactionsDao.insertFromSync(
        amount: (transaction['amount'] as num).toDouble(),
        currency: transaction['currency'] as String? ?? 'USD',
        merchant: transaction['merchant'] as String? ?? '',
        category: transaction['category'] as String? ?? 'Other',
        source: transaction['source'] as String? ?? 'manual',
        rawText: transaction['raw_text'] as String? ?? '',
        timestamp: DateTime.parse(transaction['timestamp'] as String),
        dedupHash: transaction['dedup_hash'] as String,
      );
      if (inserted) downloaded++;
    }
    final localProfile = await SyncProfile.fromDatabase(_db);
    final remoteProfile = await client.pullProfile();
    final mergedProfile = localProfile.mergeServer(
      remoteProfile == null ? null : SyncProfile.fromJson(remoteProfile),
    );
    await mergedProfile.profile.applyTo(_db);
    await client.pushProfile(mergedProfile.profile.toJson());
    return SyncOutcome(
      uploaded: pushed.inserted,
      duplicates: pushed.duplicates,
      downloaded: downloaded,
      profileConflicts: mergedProfile.conflicts,
    );
  }
}
