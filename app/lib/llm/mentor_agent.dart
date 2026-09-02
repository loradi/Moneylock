import 'dart:convert';

import 'package:moneylock/data/db.dart';

import '../data/budget_change_summary.dart';
import '../data/new_subscription_summary.dart';
import '../data/plan_action_summary.dart';
import '../data/subscription_edit_summary.dart';
import '../data/subscription_projection.dart';
import '../data/subscription_summary.dart';
import '../data/transaction_edit_summary.dart';
import '../data/transaction_summary.dart';
import '../features/dashboard/spendable_amount.dart';
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
  MentorChatResult({required this.content, this.kind = 'text', this.dataJson});
}

class ChatIntent {
  final String intent;
  final String? category;
  final String? merchant;
  final int? monthsBack;
  final double? newLimit;
  final double? amount;
  final int? dayOfMonth;
  final String? newMerchant;
  final String? newCategory;
  final int? count;
  final String? planCycle;
  final String? targetCurrency;
  final double? exchangeRate;
  final bool degraded;
  ChatIntent({
    required this.intent,
    this.category,
    this.merchant,
    this.monthsBack,
    this.newLimit,
    this.amount,
    this.dayOfMonth,
    this.newMerchant,
    this.newCategory,
    this.count,
    this.planCycle,
    this.targetCurrency,
    this.exchangeRate,
    this.degraded = false,
  });
}

ChatIntent _parseIntent(String raw) {
  try {
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final intent = json['intent'] as String?;
    const recognized = {
      'query_transactions',
      'delete_transaction',
      'query_subscriptions',
      'cancel_subscription',
      'update_budget_limit',
      'record_transaction',
      'add_subscription',
      'edit_transaction',
      'edit_subscription',
      'set_plan_income',
      'set_plan_cycle',
      'set_plan_currency',
      'add_category',
      'remove_category',
    };
    if (intent == null || !recognized.contains(intent)) {
      return ChatIntent(intent: 'chat');
    }
    var category = json['category'] as String?;
    if (intent == 'update_budget_limit') {
      if (category == null || json['newLimit'] == null) {
        return ChatIntent(intent: 'chat', degraded: true);
      }
      final resolvedCategory = categoryCatalog.firstWhere(
        (c) => c.toLowerCase() == category!.toLowerCase(),
        orElse: () => '',
      );
      if (resolvedCategory.isEmpty) {
        return ChatIntent(intent: 'chat', degraded: true);
      }
      category = resolvedCategory;
    }
    if (intent == 'add_subscription' &&
        (json['merchant'] == null ||
            json['amount'] == null ||
            json['dayOfMonth'] == null)) {
      return ChatIntent(intent: 'chat', degraded: true);
    }
    final newCategory = json['newCategory'] as String?;
    if (intent == 'edit_transaction' &&
        newCategory != null &&
        !categoryCatalog.contains(newCategory)) {
      return ChatIntent(intent: 'chat', degraded: true);
    }
    if (intent == 'edit_transaction' &&
        json['amount'] == null &&
        json['newMerchant'] == null &&
        newCategory == null) {
      return ChatIntent(intent: 'chat', degraded: true);
    }
    if (intent == 'edit_subscription' && json['amount'] == null) {
      return ChatIntent(intent: 'chat', degraded: true);
    }
    if (intent == 'set_plan_income' &&
        ((json['amount'] as num?)?.toDouble() ?? 0) <= 0) {
      return ChatIntent(intent: 'chat', degraded: true);
    }
    const cycles = {'weekly', 'fortnightly', 'monthly'};
    final planCycle = json['planCycle'] as String?;
    if (intent == 'set_plan_cycle' && !cycles.contains(planCycle)) {
      return ChatIntent(intent: 'chat', degraded: true);
    }
    const currencies = {'USD', 'CAD', 'EUR', 'GBP'};
    final targetCurrency = json['targetCurrency'] as String?;
    final exchangeRate = (json['exchangeRate'] as num?)?.toDouble();
    if (intent == 'set_plan_currency' &&
        (!currencies.contains(targetCurrency) ||
            exchangeRate == null ||
            !exchangeRate.isFinite ||
            exchangeRate <= 0)) {
      return ChatIntent(intent: 'chat', degraded: true);
    }
    if ((intent == 'add_category' || intent == 'remove_category') &&
        (category == null || category.trim().isEmpty || category.length > 50)) {
      return ChatIntent(intent: 'chat', degraded: true);
    }
    return ChatIntent(
      intent: intent,
      category: category,
      merchant: json['merchant'] as String?,
      monthsBack: (json['monthsBack'] as num?)?.toInt(),
      newLimit: (json['newLimit'] as num?)?.toDouble(),
      amount: (json['amount'] as num?)?.toDouble(),
      dayOfMonth: (json['dayOfMonth'] as num?)?.toInt(),
      newMerchant: json['newMerchant'] as String?,
      newCategory: newCategory,
      count: (json['count'] as num?)?.toInt(),
      planCycle: planCycle,
      targetCurrency: targetCurrency,
      exchangeRate: exchangeRate,
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
    final period =
        '${timestamp.year.toString().padLeft(4, '0')}-${timestamp.month.toString().padLeft(2, '0')}';
    final limits = await db.budgetsDao.limitsForPeriod(period);
    final spent = await db.transactionsDao.categorySpentThisPeriod(
      category,
      period,
    );
    final limit = limits[category];
    final severity = assessSpend(spent, limit);

    final tone = await db.settingsDao.mentorTone();
    final recent = await db.transactionsDao.recent(5);
    final recentText = recent.isEmpty
        ? 'No prior transactions.'
        : recent
              .map(
                (t) =>
                    '${t.merchant.isEmpty ? t.category : t.merchant}: \$${t.amount.toStringAsFixed(2)} (${t.category})',
              )
              .join('\n');

    final context =
        'Category: $category\n'
        'New amount: \$${amount.toStringAsFixed(2)}\n'
        'Spent this month in $category: \$${spent.toStringAsFixed(2)}\n'
        'Monthly limit for $category: ${limit == null ? 'none' : '\$${limit.toStringAsFixed(2)}'}\n'
        'Recent transactions:\n$recentText';

    String message;
    if (severity == Severity.info && limit == null) {
      message =
          'Transaction recorded: \$${amount.toStringAsFixed(2)} in $category.';
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

  Future<MentorChatResult> chat(
    String userMessage, {
    ChatIntent? preclassified,
  }) async {
    final parsed = preclassified ?? await classify(userMessage);
    switch (parsed.intent) {
      case 'query_transactions':
        return _queryTransactions(parsed);
      case 'delete_transaction':
        return _deleteTransactionCandidate(parsed);
      case 'query_subscriptions':
        return _querySubscriptions(parsed);
      case 'cancel_subscription':
        return _cancelSubscriptionCandidate(parsed);
      case 'update_budget_limit':
        return _updateBudgetLimit(parsed);
      case 'add_subscription':
        return _addSubscription(parsed);
      case 'edit_transaction':
        return _editTransactionCandidate(parsed);
      case 'edit_subscription':
        return _editSubscriptionCandidate(parsed);
      case 'set_plan_income':
        return _setPlanIncome(parsed);
      case 'set_plan_cycle':
        return _setPlanCycle(parsed);
      case 'set_plan_currency':
        return _setPlanCurrency(parsed);
      case 'add_category':
        return _addCategory(parsed);
      case 'remove_category':
        return _removeCategory(parsed);
      // 'record_transaction' has no case here: chat_screen.dart's _send()
      // intercepts that intent before ever calling chat(), routing it to
      // the add-transaction flow instead. If it ever does reach here
      // (e.g. a future caller that doesn't intercept it), falling through
      // to general chat is a safe, non-broken degradation.
      default:
        return _generalChat(userMessage);
    }
  }

  Future<MentorChatResult> _generalChat(String userMessage) async {
    final tone = await db.settingsDao.mentorTone();
    final now = DateTime.now();
    final period =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}';
    final (planRows, storedCurrency, defaultCurrency, transactions) = await (
      db.budgetsDao.forPeriod(period),
      db.settingsDao.planCurrency(period),
      db.settingsDao.defaultCurrency(),
      db.transactionsDao.search(limit: 500),
    ).wait;
    final currency =
        storedCurrency ??
        (planRows.isEmpty ? defaultCurrency : planRows.first.currency);
    final limits = {for (final row in planRows) row.category: row.monthlyLimit};
    final start = DateTime(now.year, now.month);
    final end = DateTime(now.year, now.month + 1);
    final spentByCategory = <String, double>{};
    final unconvertedTotals = <String, double>{};
    for (final transaction in transactions.where(
      (row) => !row.timestamp.isBefore(start) && row.timestamp.isBefore(end),
    )) {
      if (transaction.currency != currency) {
        unconvertedTotals[transaction.currency] =
            (unconvertedTotals[transaction.currency] ?? 0) + transaction.amount;
        continue;
      }
      spentByCategory[transaction.category] =
          (spentByCategory[transaction.category] ?? 0) + transaction.amount;
    }
    final totalSpent = spentByCategory.values.fold<double>(0, (a, b) => a + b);
    final totalLimit = limits.values.fold<double>(0, (a, b) => a + b);
    final subs = await db.subscriptionsDao.allForScheduling();
    final upcomingSubscriptions = projectSubscriptionCharges(
      subscriptions: subs,
      month: now,
      currency: currency,
      now: now,
    );
    final startOfToday = DateTime(now.year, now.month, now.day);
    final daysRemaining = DateTime(
      now.year,
      now.month + 1,
    ).difference(startOfToday).inDays;
    final spendable = calculateSpendableAmount(
      totalLimit: totalLimit,
      totalSpent: totalSpent,
      recurringCommitments: upcomingSubscriptions.total,
      daysLeft: daysRemaining,
    );

    final categoryLines = limits.entries
        .map(
          (e) =>
              '- ${e.key}: \$${(spentByCategory[e.key] ?? 0).toStringAsFixed(2)} / \$${e.value.toStringAsFixed(2)}',
        )
        .join('\n');
    final subsLines = subs.isEmpty
        ? 'No subscriptions tracked.'
        : subs
              .map(
                (s) =>
                    '- ${s.name}: \$${s.amount.toStringAsFixed(2)}/${s.cycle}, renews ${s.nextChargeDate.month}/${s.nextChargeDate.day}',
              )
              .join('\n');
    final topCategoryLine = spentByCategory.isEmpty
        ? ''
        : (() {
            final top = spentByCategory.entries.reduce(
              (a, b) => a.value > b.value ? a : b,
            );
            return 'Highest spending category this month: ${top.key} (\$${top.value.toStringAsFixed(2)}).\n';
          })();
    final unconvertedLine = unconvertedTotals.isEmpty
        ? ''
        : 'Other currencies excluded from these totals: ${unconvertedTotals.entries.map((entry) => '${entry.key} ${entry.value.toStringAsFixed(2)}').join(', ')}.\n';

    final history = await _historyBlock();
    final context =
        '${history}This month ($period) so far:\n'
        'Currency: $currency\n'
        'Total spent: $currency ${totalSpent.toStringAsFixed(2)} of $currency ${totalLimit.toStringAsFixed(2)} budgeted\n'
        'By category:\n${categoryLines.isEmpty ? '(no budgets set)' : categoryLines}\n'
        '$topCategoryLine'
        '$unconvertedLine'
        'Financial runway:\n'
        '- Upcoming tracked recurring charges this month: $currency ${upcomingSubscriptions.total.toStringAsFixed(2)}\n'
        '- Flexible money after spending and those charges: $currency ${spendable.availableAfterCommitments.toStringAsFixed(2)}\n'
        '- Safe daily amount for the remaining $daysRemaining day${daysRemaining == 1 ? '' : 's'}: $currency ${spendable.dailyAmount.toStringAsFixed(2)}\n'
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
    final effectiveLimit = parsed.count != null
        ? parsed.count!.clamp(1, 50)
        : 500;
    final rows = await db.transactionsDao.search(
      category: parsed.category,
      merchantKeyword: parsed.merchant,
      since: _sinceFromMonthsBack(parsed.monthsBack),
      limit: effectiveLimit,
    );
    final summaries = rows.map(TransactionSummary.fromTransaction).toList();
    if (summaries.isEmpty) {
      return MentorChatResult(
        content: "I couldn't find any matching transactions.",
      );
    }
    final total = summaries.fold<double>(0, (a, t) => a + t.amount);
    if (parsed.count != null) {
      return MentorChatResult(
        content:
            'Here are your last ${summaries.length} transactions, totaling \$${total.toStringAsFixed(2)}.',
        kind: 'transaction_list',
        dataJson: encodeTransactionSummaries(summaries),
      );
    }
    final label = parsed.merchant ?? parsed.category ?? 'transactions';
    return MentorChatResult(
      content:
          'Found ${summaries.length} matching "$label", totaling \$${total.toStringAsFixed(2)}.',
      kind: 'transaction_list',
      dataJson: encodeTransactionSummaries(summaries.take(20).toList()),
    );
  }

  Future<MentorChatResult> _deleteTransactionCandidate(
    ChatIntent parsed,
  ) async {
    final rows = await db.transactionsDao.search(
      category: parsed.category,
      merchantKeyword: parsed.merchant,
      since: _sinceFromMonthsBack(parsed.monthsBack),
      limit: 5,
    );
    final summaries = rows.map(TransactionSummary.fromTransaction).toList();
    if (summaries.isEmpty) {
      return MentorChatResult(
        content: "I couldn't find a transaction matching that.",
      );
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

  Future<MentorChatResult> _querySubscriptions(ChatIntent parsed) async {
    final rows = await db.subscriptionsDao.search(
      nameKeyword: parsed.merchant,
      limit: 100,
    );
    final summaries = rows.map(SubscriptionSummary.fromSubscription).toList();
    if (summaries.isEmpty) {
      return MentorChatResult(
        content: "I couldn't find any matching subscriptions.",
      );
    }
    final monthlyTotal = summaries.fold<double>(
      0,
      (a, s) => a + (s.cycle == 'yearly' ? s.amount / 12 : s.amount),
    );
    return MentorChatResult(
      content:
          'Found ${summaries.length} subscription${summaries.length == 1 ? '' : 's'}, '
          '~\$${monthlyTotal.toStringAsFixed(2)}/month.',
      kind: 'subscription_list',
      dataJson: encodeSubscriptionSummaries(summaries),
    );
  }

  Future<MentorChatResult> _cancelSubscriptionCandidate(
    ChatIntent parsed,
  ) async {
    final rows = await db.subscriptionsDao.search(
      nameKeyword: parsed.merchant,
      limit: 5,
    );
    final summaries = rows.map(SubscriptionSummary.fromSubscription).toList();
    if (summaries.isEmpty) {
      return MentorChatResult(
        content: "I couldn't find a subscription matching that.",
      );
    }
    if (summaries.length > 1) {
      return MentorChatResult(
        content:
            'Found ${summaries.length} subscriptions matching that -- can you be more specific?',
        kind: 'subscription_list',
        dataJson: encodeSubscriptionSummaries(summaries),
      );
    }
    return MentorChatResult(
      content: 'Found this subscription -- want me to cancel it?',
      kind: 'cancel_confirm',
      dataJson: encodeSubscriptionSummaries(summaries),
    );
  }

  Future<MentorChatResult> _updateBudgetLimit(ChatIntent parsed) async {
    final category = parsed.category!;
    final newLimit = parsed.newLimit!;
    final now = DateTime.now();
    final period =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}';
    final limits = await db.budgetsDao.limitsForPeriod(period);
    final currentLimit = limits[category] ?? 0.0;
    final change = BudgetChangeSummary(
      category: category,
      currentLimit: currentLimit,
      proposedLimit: newLimit,
      period: period,
    );
    return MentorChatResult(
      content:
          'Change your $category limit from \$${currentLimit.toStringAsFixed(2)} '
          'to \$${newLimit.toStringAsFixed(2)}?',
      kind: 'budget_confirm',
      dataJson: encodeBudgetChangeSummary(change),
    );
  }

  Future<MentorChatResult> _setPlanIncome(ChatIntent parsed) async {
    final now = DateTime.now();
    final period =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}';
    final currency =
        await db.settingsDao.planCurrency(period) ??
        await db.settingsDao.defaultCurrency();
    final amount = parsed.amount!;
    return MentorChatResult(
      content:
          'Set your $period take-home income to $currency ${amount.toStringAsFixed(2)}?',
      kind: 'plan_action_confirm',
      dataJson: encodePlanActionSummary(
        PlanActionSummary(action: 'set_income', period: period, amount: amount),
      ),
    );
  }

  Future<MentorChatResult> _setPlanCycle(ChatIntent parsed) async {
    final cycle = parsed.planCycle!;
    return MentorChatResult(
      content:
          'Use ${cycle == 'fortnightly' ? 'a two-week' : 'a $cycle'} planning cycle going forward?',
      kind: 'plan_action_confirm',
      dataJson: encodePlanActionSummary(
        PlanActionSummary(action: 'set_cycle', cycle: cycle),
      ),
    );
  }

  Future<MentorChatResult> _setPlanCurrency(ChatIntent parsed) async {
    final now = DateTime.now();
    final period =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}';
    final rows = await db.budgetsDao.forPeriod(period);
    final currentCurrency =
        await db.settingsDao.planCurrency(period) ??
        (rows.isEmpty
            ? await db.settingsDao.defaultCurrency()
            : rows.first.currency);
    final target = parsed.targetCurrency!;
    if (target == currentCurrency) {
      return MentorChatResult(content: 'This plan is already in $target.');
    }
    return MentorChatResult(
      content:
          'Convert your $period plan from $currentCurrency to $target at ${parsed.exchangeRate!.toStringAsFixed(4)} $target per $currentCurrency?',
      kind: 'plan_action_confirm',
      dataJson: encodePlanActionSummary(
        PlanActionSummary(
          action: 'convert_currency',
          period: period,
          targetCurrency: target,
          rate: parsed.exchangeRate,
        ),
      ),
    );
  }

  Future<MentorChatResult> _addCategory(ChatIntent parsed) async {
    final category = parsed.category!.trim();
    return MentorChatResult(
      content: 'Add "$category" to your plan categories?',
      kind: 'plan_action_confirm',
      dataJson: encodePlanActionSummary(
        PlanActionSummary(action: 'add_category', category: category),
      ),
    );
  }

  Future<MentorChatResult> _removeCategory(ChatIntent parsed) async {
    final category = parsed.category!.trim();
    return MentorChatResult(
      content:
          'Remove "$category" from your plan categories? Existing transactions will remain unchanged.',
      kind: 'plan_action_confirm',
      dataJson: encodePlanActionSummary(
        PlanActionSummary(action: 'remove_category', category: category),
      ),
    );
  }

  Future<MentorChatResult> _addSubscription(ChatIntent parsed) async {
    final name = parsed.merchant!;
    final amount = parsed.amount!;
    final dayOfMonth = parsed.dayOfMonth!;
    final now = DateTime.now();
    final nextChargeDate = now.day <= dayOfMonth
        ? DateTime(now.year, now.month, dayOfMonth)
        : DateTime(now.year, now.month + 1, dayOfMonth);
    final summary = NewSubscriptionSummary(
      name: name,
      amount: amount,
      nextChargeDate: nextChargeDate,
    );
    final monthName = const [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ][nextChargeDate.month - 1];
    return MentorChatResult(
      content:
          'Add $name at \$${amount.toStringAsFixed(2)}/month, '
          'starting $monthName ${nextChargeDate.day}?',
      kind: 'add_subscription_confirm',
      dataJson: encodeNewSubscriptionSummary(summary),
    );
  }

  Future<MentorChatResult> _editTransactionCandidate(ChatIntent parsed) async {
    final rows = await db.transactionsDao.search(
      category: parsed.category,
      merchantKeyword: parsed.merchant,
      since: _sinceFromMonthsBack(parsed.monthsBack),
      limit: 5,
    );
    final summaries = rows.map(TransactionSummary.fromTransaction).toList();
    if (summaries.isEmpty) {
      return MentorChatResult(
        content: "I couldn't find a transaction matching that.",
      );
    }
    if (summaries.length > 1) {
      return MentorChatResult(
        content:
            'Found ${summaries.length} transactions matching that -- can you be more specific (date, amount, or exact merchant)?',
        kind: 'transaction_list',
        dataJson: encodeTransactionSummaries(summaries),
      );
    }
    final target = summaries.first;
    final label = target.merchant.isEmpty ? target.category : target.merchant;
    final parts = <String>[];
    if (parsed.amount != null) {
      parts.add(
        'amount from \$${target.amount.toStringAsFixed(2)} to \$${parsed.amount!.toStringAsFixed(2)}',
      );
    }
    if (parsed.newMerchant != null) {
      parts.add(
        "merchant from '${target.merchant}' to '${parsed.newMerchant}'",
      );
    }
    if (parsed.newCategory != null) {
      parts.add('category from ${target.category} to ${parsed.newCategory}');
    }
    final edit = TransactionEditSummary(
      transaction: target,
      newAmount: parsed.amount,
      newMerchant: parsed.newMerchant,
      newCategory: parsed.newCategory,
    );
    return MentorChatResult(
      content:
          'Change $label (${target.timestamp.month}/${target.timestamp.day})\'s ${parts.join(' and ')}?',
      kind: 'edit_transaction_confirm',
      dataJson: encodeTransactionEditSummary(edit),
    );
  }

  Future<MentorChatResult> _editSubscriptionCandidate(ChatIntent parsed) async {
    final rows = await db.subscriptionsDao.search(
      nameKeyword: parsed.merchant,
      limit: 5,
    );
    final summaries = rows.map(SubscriptionSummary.fromSubscription).toList();
    if (summaries.isEmpty) {
      return MentorChatResult(
        content: "I couldn't find a subscription matching that.",
      );
    }
    if (summaries.length > 1) {
      return MentorChatResult(
        content:
            'Found ${summaries.length} subscriptions matching that -- can you be more specific?',
        kind: 'subscription_list',
        dataJson: encodeSubscriptionSummaries(summaries),
      );
    }
    final target = summaries.first;
    final newAmount = parsed.amount!;
    final edit = SubscriptionEditSummary(
      subscription: target,
      newAmount: newAmount,
    );
    return MentorChatResult(
      content:
          'Change ${target.name} from \$${target.amount.toStringAsFixed(2)} '
          'to \$${newAmount.toStringAsFixed(2)}?',
      kind: 'edit_subscription_confirm',
      dataJson: encodeSubscriptionEditSummary(edit),
    );
  }
}
