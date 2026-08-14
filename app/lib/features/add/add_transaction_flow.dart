import '../../data/db.dart';
import '../../data/transactions_dao.dart';
import '../../llm/categorizer_agent.dart';
import '../../llm/mentor_agent.dart';
import '../../core/notifications.dart';

class AddResult {
  final bool inserted;
  final MentorVerdict? verdict;
  final String? error;
  AddResult({required this.inserted, this.verdict, this.error});
}

String parseShortcutUrl(Uri uri) {
  final amount = uri.queryParameters['amount'];
  final merchant = uri.queryParameters['merchant'];
  if (amount == null || double.tryParse(amount) == null) {
    throw FormatException('Missing or invalid amount: $amount');
  }
  return '$merchant $amount USD';
}

class AddTransactionFlow {
  final CategorizerAgent categorizer;
  final MentorAgent mentor;
  final AppDatabase db;
  final LocalNotifications notifications;
  AddTransactionFlow({required this.categorizer, required this.mentor,
      required this.db, required this.notifications});

  Future<AddResult> run({required String rawText, required String source, DateTime? timestamp}) async {
    final ts = timestamp ?? DateTime.now();
    try {
      final result = await categorizer.categorize(rawText, source: source);
      final parsed = result.parsed;
      final amount = parsed.amount;
      if (amount == null) {
        return AddResult(inserted: false, error: 'Could not extract amount');
      }
      final outcome = await db.transactionsDao.insertWithDedup(NewTransaction(
        amount: amount, currency: parsed.currency,
        merchant: parsed.merchant ?? '', category: parsed.category ?? 'Other',
        source: source, rawText: rawText, timestamp: ts));
      if (!outcome.inserted) {
        return AddResult(inserted: false);
      }
      final verdict = await mentor.evaluate(
          category: outcome.transaction!.category,
          amount: outcome.transaction!.amount,
          timestamp: ts);
      await db.messagesDao.add('mentor', verdict.message);
      final title = switch (verdict.severity) {
        Severity.alert => 'Over budget',
        Severity.warning => 'Budget warning',
        Severity.info => 'Transaction recorded',
      };
      await notifications.show(title, verdict.message, verdict.severity);
      return AddResult(inserted: true, verdict: verdict);
    } catch (e) {
      return AddResult(inserted: false, error: e.toString());
    }
  }
}