import 'dart:convert';

import 'package:moneylock/data/db.dart';

import '../data/transaction_summary.dart';
import 'mentor_guardrails.dart';
import 'prompts.dart';
import 'llm_provider.dart';

enum Severity { info, warning, alert }

Severity assessSpend(double spent, double? limit) {
  if (limit == null) return Severity.info;
  if (spent >= limit) return Severity.alert;
  if (spent >= limit * 0.8) return Severity.warning;
  return Severity.info;
}

String mentorPromptFor(String tone) {
  switch (tone) {
    case 'neutral_analyst':
      return neutralAnalystPrompt;
    case 'friendly_coach':
      return friendlyCoachPrompt;
    default:
      return strictRamseyPrompt;
  }
}

class MentorVerdict {
  final Severity severity;
  final String message;
  MentorVerdict(this.severity, this.message);
}

class MentorChatResult {
  final String content;
  final String kind; // 'text' | 'transaction_list' | 'delete_confirm'
  final String? dataJson;
  MentorChatResult({
    required this.content,
    this.kind = 'text',
    this.dataJson,
  });
}

class ChatIntent {
  final String intent;
  final String? category;
  final String? merchant;
  final int? monthsBack;
  ChatIntent({required this.intent, this.category, this.merchant, this.monthsBack});
}

ChatIntent _parseIntent(String raw) {
  try {
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final intent = json['intent'] as String?;
    if (intent != 'query_transactions' && intent != 'delete_transaction') {
      return ChatIntent(intent: 'chat');
    }
    return ChatIntent(
      intent: intent!,
      category: json['category'] as String?,
      merchant: json['merchant'] as String?,
      monthsBack: (json['monthsBack'] as num?)?.toInt(),
    );
  } catch (_) {
    return ChatIntent(intent: 'chat');
  }
}

DateTime? _sinceFromMonthsBack(int? monthsBack) {
  if (monthsBack == null) return null;
  final now = DateTime.now();
  return DateTime(now.year, now.month - monthsBack, now.day);
}

class MentorAgent {
  final LlmProvider provider;
  final AppDatabase db;
  MentorAgent(this.provider, this.db);

  Future<MentorVerdict> evaluate({
    required String category,
    required double amount,
    required DateTime timestamp,
  }) async {
    final period = '${timestamp.year.toString().padLeft(4, '0')}-${timestamp.month.toString().padLeft(2, '0')}';
    final limits = await db.budgetsDao.limitsForPeriod(period);
    final spent = await db.transactionsDao.categorySpentThisPeriod(category, period);
    final limit = limits[category];
    final severity = assessSpend(spent, limit);

    final tone = await db.settingsDao.mentorTone();
    final recent = await db.transactionsDao.recent(5);
    final recentText = recent.isEmpty ? 'No prior transactions.'
        : recent.map((t) => '${t.merchant.isEmpty ? t.category : t.merchant}: \$${t.amount.toStringAsFixed(2)} (${t.category})').join('\n');

    final context = 'Category: $category\n'
        'New amount: \$${amount.toStringAsFixed(2)}\n'
        'Spent this month in $category: \$${spent.toStringAsFixed(2)}\n'
        'Monthly limit for $category: ${limit == null ? 'none' : '\$${limit.toStringAsFixed(2)}'}\n'
        'Recent transactions:\n$recentText';

    String message;
    if (severity == Severity.info && limit == null) {
      message = 'Transaction recorded: \$${amount.toStringAsFixed(2)} in $category.';
    } else {
      try {
        message = await provider.complete(mentorPromptFor(tone), context);
      } catch (_) {
        message = severity == Severity.alert
            ? 'You are over budget on $category (${spent.toStringAsFixed(2)}). Tighten up.'
            : severity == Severity.warning
            ? 'You have used ${(spent / limit! * 100).toStringAsFixed(0)}% of your $category budget.'
            : 'Transaction recorded in $category.';
      }
    }
    return MentorVerdict(severity, message);
  }

  Future<String> _historyBlock() async {
    // recent() includes the just-saved current turn as its newest row --
    // every call site in chat_screen.dart persists the user's message via
    // messagesDao.add() before calling classify()/chat(). Drop the newest
    // row so it isn't duplicated against the userMessage param each caller
    // already appends explicitly. Safe even when nothing was pre-saved
    // (e.g. these unit tests calling agent.chat() directly): dropping "the
    // newest of zero-to-N rows" never removes a real prior turn that
    // wasn't already accounted for.
    final rows = await db.messagesDao.recent(7);
    final priorTurns = rows.isEmpty ? rows : rows.sublist(0, rows.length - 1);
    if (priorTurns.isEmpty) return '';
    final lines = priorTurns
        .map((m) => '${m.role == 'user' ? 'User' : 'Mentor'}: ${m.content}')
        .join('\n');
    return 'Recent conversation:\n$lines\n\n';
  }

  Future<ChatIntent> classify(String userMessage) async {
    try {
      final history = await _historyBlock();
      final raw = await provider.complete(
        mentorIntentPrompt,
        '${history}User: $userMessage',
        temperature: 0.0,
      );
      return _parseIntent(raw);
    } catch (_) {
      return ChatIntent(intent: 'chat');
    }
  }

  Future<MentorChatResult> chat(String userMessage, {ChatIntent? preclassified}) async {
    final parsed = preclassified ?? await classify(userMessage);
    switch (parsed.intent) {
      case 'query_transactions':
        return _queryTransactions(parsed);
      case 'delete_transaction':
        return _deleteTransactionCandidate(parsed);
      default:
        return _generalChat(userMessage);
    }
  }

  Future<MentorChatResult> _generalChat(String userMessage) async {
    final tone = await db.settingsDao.mentorTone();
    final now = DateTime.now();
    final period = '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}';
    final spentByCategory = await db.transactionsDao.spentByCategoryThisPeriod(period);
    final limits = await db.budgetsDao.limitsForPeriod(period);
    final totalSpent = spentByCategory.values.fold<double>(0, (a, b) => a + b);
    final totalLimit = limits.values.fold<double>(0, (a, b) => a + b);
    final subs = await db.subscriptionsDao.allForScheduling();

    final categoryLines = limits.entries
        .map((e) =>
            '- ${e.key}: \$${(spentByCategory[e.key] ?? 0).toStringAsFixed(2)} / \$${e.value.toStringAsFixed(2)}')
        .join('\n');
    final subsLines = subs.isEmpty
        ? 'No subscriptions tracked.'
        : subs
            .map((s) =>
                '- ${s.name}: \$${s.amount.toStringAsFixed(2)}/${s.cycle}, renews ${s.nextChargeDate.month}/${s.nextChargeDate.day}')
            .join('\n');

    final history = await _historyBlock();
    final context = '${history}This month ($period) so far:\n'
        'Total spent: \$${totalSpent.toStringAsFixed(2)} of \$${totalLimit.toStringAsFixed(2)} budgeted\n'
        'By category:\n${categoryLines.isEmpty ? '(no budgets set)' : categoryLines}\n'
        'Active subscriptions:\n$subsLines\n\n'
        'User: $userMessage';

    try {
      final reply = await provider.complete(mentorPromptFor(tone), context);
      return MentorChatResult(content: guardMentorResponse(reply));
    } catch (_) {
      return MentorChatResult(content: 'I could not reach my model right now.');
    }
  }

  Future<MentorChatResult> _queryTransactions(ChatIntent parsed) async {
    final rows = await db.transactionsDao.search(
      category: parsed.category,
      merchantKeyword: parsed.merchant,
      since: _sinceFromMonthsBack(parsed.monthsBack),
      limit: 500,
    );
    final summaries = rows.map(TransactionSummary.fromTransaction).toList();
    if (summaries.isEmpty) {
      return MentorChatResult(content: "I couldn't find any matching transactions.");
    }
    final total = summaries.fold<double>(0, (a, t) => a + t.amount);
    final label = parsed.merchant ?? parsed.category ?? 'transactions';
    return MentorChatResult(
      content: 'Found ${summaries.length} matching "$label", totaling \$${total.toStringAsFixed(2)}.',
      kind: 'transaction_list',
      dataJson: encodeTransactionSummaries(summaries.take(20).toList()),
    );
  }

  Future<MentorChatResult> _deleteTransactionCandidate(ChatIntent parsed) async {
    final rows = await db.transactionsDao.search(
      category: parsed.category,
      merchantKeyword: parsed.merchant,
      since: _sinceFromMonthsBack(parsed.monthsBack),
      limit: 5,
    );
    final summaries = rows.map(TransactionSummary.fromTransaction).toList();
    if (summaries.isEmpty) {
      return MentorChatResult(content: "I couldn't find a transaction matching that.");
    }
    if (summaries.length > 1) {
      return MentorChatResult(
        content:
            'Found ${summaries.length} transactions matching that -- can you be more specific (date, amount, or exact merchant)?',
        kind: 'transaction_list',
        dataJson: encodeTransactionSummaries(summaries),
      );
    }
    return MentorChatResult(
      content: 'Found this transaction -- want me to delete it?',
      kind: 'delete_confirm',
      dataJson: encodeTransactionSummaries(summaries),
    );
  }
}