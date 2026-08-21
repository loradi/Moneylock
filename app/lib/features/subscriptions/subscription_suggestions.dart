import '../../data/db.dart';

class SuggestedSubscription {
  final String merchant;
  final double averageAmount;
  final int occurrenceCount;
  final DateTime mostRecentDate;
  SuggestedSubscription({
    required this.merchant,
    required this.averageAmount,
    required this.occurrenceCount,
    required this.mostRecentDate,
  });
}

List<SuggestedSubscription> detectSuggestions({
  required List<Transaction> transactions,
  required List<Subscription> existingSubscriptions,
  required Set<String> dismissedMerchants,
}) {
  final existingNames = existingSubscriptions.map((s) => s.name.toLowerCase()).toSet();
  final byMerchant = <String, List<Transaction>>{};
  for (final t in transactions) {
    final key = t.merchant.trim().toLowerCase();
    if (key.isEmpty) continue;
    byMerchant.putIfAbsent(key, () => []).add(t);
  }

  final suggestions = <SuggestedSubscription>[];
  for (final entry in byMerchant.entries) {
    final key = entry.key;
    final group = entry.value;
    if (group.length < 2) continue;
    if (existingNames.contains(key)) continue;
    if (dismissedMerchants.contains(key)) continue;

    final average = group.fold<double>(0, (a, t) => a + t.amount) / group.length;
    final withinBand = group.every((t) => (t.amount - average).abs() <= average * 0.10);
    if (!withinBand) continue;

    group.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    suggestions.add(SuggestedSubscription(
      merchant: group.first.merchant,
      averageAmount: average,
      occurrenceCount: group.length,
      mostRecentDate: group.first.timestamp,
    ));
  }
  return suggestions;
}
