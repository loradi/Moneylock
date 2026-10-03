import 'dart:async';

import '../../data/db.dart';
import '../../data/transactions_dao.dart';
import '../../llm/categorizer_agent.dart';
import '../../llm/fallback_parser.dart';
import '../../llm/mentor_agent.dart';
import '../../core/notifications.dart';
import '../../core/notification_scheduler.dart';
import '../../core/currency_options.dart';

class AddResult {
  final bool inserted;
  final Transaction? transaction;
  final MentorVerdict? verdict;
  final String? error;

  /// Optional completion signal for non-blocking Vector follow-up work.
  /// The saved transaction is already durable when [inserted] is true.
  final Future<void>? postSave;

  AddResult({
    required this.inserted,
    this.transaction,
    this.verdict,
    this.error,
    this.postSave,
  });
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
  final NotificationScheduler scheduler;
  AddTransactionFlow({
    required this.categorizer,
    required this.mentor,
    required this.db,
    required this.notifications,
    required this.scheduler,
  });

  Future<AddResult> run({
    required String rawText,
    required String source,
    DateTime? timestamp,
    bool includeMentorFeedback = true,
  }) async {
    final ts = timestamp ?? DateTime.now();
    try {
      // A recognized amount can be committed immediately. The on-device model
      // still refines low-confidence categories after the save, but the user
      // never has to wait for model inference to protect a simple record.
      final fallback = parseFallback(rawText);
      final parsedResult =
          fallback ??
          (await categorizer.categorize(rawText, source: source)).parsed;
      final configuredCurrency = await db.settingsDao.defaultCurrency();
      final hasExplicitCurrency = RegExp(r'(?:\b[A-Z]{3}\b|\$|€|£|¥|₹)')
          .hasMatch(rawText);
      final parsed =
          !hasExplicitCurrency &&
              parsedResult.amount != null &&
              isCurrencyCode(configuredCurrency)
          ? ParsedTransaction(
              amount: parsedResult.amount,
              currency: configuredCurrency,
              merchant: parsedResult.merchant,
              category: parsedResult.category,
              confidence: parsedResult.confidence,
            )
          : parsedResult;
      final amount = parsed.amount;
      if (amount == null) {
        return AddResult(inserted: false, error: 'Could not extract amount');
      }
      final outcome = await db.transactionsDao.insertWithDedup(
        NewTransaction(
          amount: amount,
          currency: parsed.currency,
          merchant: parsed.merchant ?? '',
          category: parsed.category ?? 'Other',
          source: source,
          rawText: rawText,
          timestamp: ts,
        ),
      );
      if (!outcome.inserted) {
        return AddResult(inserted: false);
      }

      final postSave = _finishAfterSave(
        transaction: outcome.transaction!,
        timestamp: ts,
        rawText: rawText,
        source: source,
        shouldRefine: fallback == null || fallback.confidence < 0.5,
        includeMentorFeedback: includeMentorFeedback,
      );
      unawaited(postSave);
      return AddResult(
        inserted: true,
        transaction: outcome.transaction,
        postSave: postSave,
      );
    } catch (e) {
      return AddResult(inserted: false, error: e.toString());
    }
  }

  Future<void> _finishAfterSave({
    required Transaction transaction,
    required DateTime timestamp,
    required String rawText,
    required String source,
    required bool shouldRefine,
    required bool includeMentorFeedback,
  }) async {
    var saved = transaction;
    try {
      // Scheduling is useful, but it is cold-path work. The transaction is
      // already durable, so do not make Vector wait on it before confirming
      // a simple add command.
      await scheduler.refresh();
    } catch (_) {
      // It is retried on the next launch/resume/transaction.
    }
    if (shouldRefine) {
      try {
        final refined = await categorizer.categorize(rawText, source: source);
        final parsed = refined.parsed;
        if (parsed.amount != null) {
          await db.transactionsDao.updateFields(
            saved.id,
            merchant: parsed.merchant ?? saved.merchant,
            category: parsed.category ?? saved.category,
          );
          saved = saved.copyWith(
            merchant: parsed.merchant ?? saved.merchant,
            category: parsed.category ?? saved.category,
          );
        }
      } catch (_) {
        // Keeping the immediately recorded fallback is safer than delaying
        // or rolling back a user's expense when the model is unavailable.
      }
    }
    if (!includeMentorFeedback) return;
    try {
      final verdict = await mentor.evaluate(
        category: saved.category,
        amount: saved.amount,
        timestamp: timestamp,
      );
      await db.messagesDao.add(
        'mentor',
        verdict.message,
        severity: verdict.severity.name,
      );
      final title = switch (verdict.severity) {
        Severity.alert => 'Over budget',
        Severity.warning => 'Budget warning',
        Severity.info => 'Transaction recorded',
      };
      await notifications.show(title, verdict.message, verdict.severity);
    } catch (_) {
      // The transaction is already committed, so any mentor, message, or
      // notification failure must not turn a successful save into an error.
    }
  }
}
