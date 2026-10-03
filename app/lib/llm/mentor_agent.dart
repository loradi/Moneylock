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
import '../features/budget/plan_period.dart';
import '../features/dashboard/spendable_amount.dart';
import 'mentor_guardrails.dart';
import 'fallback_parser.dart';
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
  final String? goalName;
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
    this.goalName,
    this.degraded = false,
  });
}

bool _hasExplicitBudgetLimitLanguage(String message) => RegExp(
  r'\b(limit|cap|budget|allocation|l[ií]mite|tope|presupuesto|asignaci[oó]n)\b',
  caseSensitive: false,
).hasMatch(message);

String? _catalogCategoryIn(String message) {
  final normalized = message.toLowerCase();
  for (final category in categoryCatalog) {
    if (normalized.contains(category.toLowerCase())) return category;
  }
  const aliases = {
    'coffee': 'Coffee & Dining',
    'dining': 'Coffee & Dining',
    'food': 'Coffee & Dining',
    'grocery': 'Groceries',
    'groceries': 'Groceries',
    'mercado': 'Groceries',
    'supermercado': 'Groceries',
    'transport': 'Transport',
    'transporte': 'Transport',
    'travel': 'Travel',
    'health': 'Health',
    'entertainment': 'Entertainment',
    'entretenimiento': 'Entertainment',
  };
  for (final entry in aliases.entries) {
    if (RegExp('\\b${entry.key}\\b').hasMatch(normalized)) return entry.value;
  }
  return null;
}

double? _firstAmount(String message) {
  final match = RegExp(r'(?<![\w.])\$?([0-9]+(?:[.,][0-9]{1,2})?)')
      .firstMatch(message);
  return match == null
      ? null
      : double.tryParse(match.group(1)!.replaceAll(',', '.'));
}

int? _requestedCount(String message) {
  final match = RegExp(
    r'\b(?:last|latest|recent|ultim[oa]s?)\s+(\d+)\b',
    caseSensitive: false,
  ).firstMatch(message);
  return match == null ? null : int.tryParse(match.group(1)!);
}

/// Handles unambiguous commands locally before a model or a database history
/// is needed. The model remains the fallback for natural, ambiguous language.
ChatIntent? _fastIntent(String message) {
  final normalized = message.trim().toLowerCase();
  if (normalized.isEmpty) return null;
  final amount = _firstAmount(message);
  final category = _catalogCategoryIn(message);

  if (RegExp(
    r'\b(clear|delete|remove|borrar|eliminar|quita[rz]?)\b.*\b(savings?|ahorro|meta)',
  ).hasMatch(normalized)) {
    return ChatIntent(intent: 'clear_savings_goal');
  }
  if (RegExp(
        r'\b(add|contribute|deposit|aporta[rz]?)\b.*\b(savings?|goal|ahorro|meta)',
      ).hasMatch(normalized) &&
      amount != null &&
      !RegExp(r'\b(for|para)\b').hasMatch(normalized)) {
    return ChatIntent(intent: 'contribute_savings_goal', amount: amount);
  }
  if (RegExp(r'\b(goal|meta)\b').hasMatch(normalized) &&
      RegExp(r'\b(save|saving|ahorrar|ahorro|create|crear|set|poner)\b')
          .hasMatch(normalized) &&
      amount != null) {
    final nameMatch = RegExp(
      r'\b(?:for|para)\s+(.+?)(?:\s+(?:of|de|target|objetivo)\s+|$)',
      caseSensitive: false,
    ).firstMatch(message);
    return ChatIntent(
      intent: 'set_savings_goal',
      amount: amount,
      goalName: nameMatch?.group(1)?.trim(),
    );
  }
  if (RegExp(
    r'\b(show|list|ver|muestra|listar)\b.*\b(subscription|subscriptions|suscripci[oó]n|suscripciones)',
  ).hasMatch(normalized)) {
    return ChatIntent(intent: 'query_subscriptions');
  }
  final deleteTransaction = RegExp(
    r'\b(?:delete|remove|borrar|eliminar|quita[rz]?)\b.*?\b(?:transaction|transactions|purchase|purchases|expense|expenses|entry|entries|record|records|transacci[oó]n|transacciones|compra|compras|gasto|gastos|registro|registros)\b(?:\s+(?:for|of|at|from|de|del|para|en)\s+(.+))?\s*$',
    caseSensitive: false,
  ).firstMatch(normalized);
  if (deleteTransaction != null) {
    return ChatIntent(
      intent: 'delete_transaction',
      merchant: deleteTransaction.group(1)?.trim(),
    );
  }
  if (RegExp(
    r'\b(show|list|display|ver|muestra|mostrar|listar)\b.*\b(transaction|transactions|purchase|purchases|expense|expenses|entry|entries|record|records|transacci[oó]n|transacciones|compra|compras|gastos?|registro|registros)',
  ).hasMatch(normalized)) {
    return ChatIntent(
      intent: 'query_transactions',
      count: _requestedCount(message),
    );
  }
  if (RegExp(r'\b(income|salary|paycheck|ingreso|salario)\b')
          .hasMatch(normalized) &&
      amount != null &&
      RegExp(r'\b(set|change|update|pon|cambia|actualiza)\b')
          .hasMatch(normalized)) {
    return ChatIntent(intent: 'set_plan_income', amount: amount);
  }
  if (RegExp(r'\b(weekly|week|semanal|semana)\b').hasMatch(normalized) &&
      RegExp(r'\b(plan|budget|presupuesto)\b').hasMatch(normalized)) {
    return ChatIntent(intent: 'set_plan_cycle', planCycle: 'weekly');
  }
  if (RegExp(r'\b(fortnightly|biweekly|bi-weekly|quincenal|quincena)\b')
          .hasMatch(normalized) &&
      RegExp(r'\b(plan|budget|presupuesto)\b').hasMatch(normalized)) {
    return ChatIntent(intent: 'set_plan_cycle', planCycle: 'fortnightly');
  }
  if (RegExp(r'\b(monthly|month|mensual|mes)\b').hasMatch(normalized) &&
      RegExp(r'\b(plan|budget|presupuesto)\b').hasMatch(normalized)) {
    return ChatIntent(intent: 'set_plan_cycle', planCycle: 'monthly');
  }
  if (_hasExplicitBudgetLimitLanguage(message) &&
      amount != null &&
      category != null) {
    return ChatIntent(
      intent: 'update_budget_limit',
      category: category,
      newLimit: amount,
    );
  }
  if (amount != null && isExplicitTransactionCommand(message)) {
    return ChatIntent(
      intent: 'record_transaction',
      category: category,
      amount: amount,
    );
  }
  if (amount != null && isCompactTransactionEntry(message)) {
    return ChatIntent(
      intent: 'record_transaction',
      category: category,
      amount: amount,
    );
  }
  if (_isFinancialCheckInRequest(normalized)) {
    return ChatIntent(intent: 'financial_checkin');
  }
  return null;
}

bool _isFinancialCheckInRequest(String normalized) => RegExp(
  r'\b(check[ -]?in|safe(?:ly)? spend|how am i doing|what can i cut|reduce spending|money advice|financial advice|resumen|consejo|cu[aá]nto puedo gastar|gastar hoy|reducir gastos)\b',
  caseSensitive: false,
).hasMatch(normalized);

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
      'set_savings_goal',
      'contribute_savings_goal',
      'clear_savings_goal',
      'financial_checkin',
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
      if (resolvedCategory.isNotEmpty) {
        category = resolvedCategory;
      } else if (category.trim().isEmpty || category.length > 50) {
        return ChatIntent(intent: 'chat', degraded: true);
      }
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
    final targetCurrency = json['targetCurrency'] as String?;
    final exchangeRate = (json['exchangeRate'] as num?)?.toDouble();
    if (intent == 'set_plan_currency' &&
        (targetCurrency == null ||
            !RegExp(r'^[A-Z]{3}$').hasMatch(targetCurrency) ||
            exchangeRate == null ||
            !exchangeRate.isFinite ||
            exchangeRate <= 0)) {
      return ChatIntent(intent: 'chat', degraded: true);
    }
    if ((intent == 'add_category' || intent == 'remove_category') &&
        (category == null || category.trim().isEmpty || category.length > 50)) {
      return ChatIntent(intent: 'chat', degraded: true);
    }
    if ((intent == 'set_savings_goal' || intent == 'contribute_savings_goal') &&
        ((json['amount'] as num?)?.toDouble() ?? 0) <= 0) {
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
      goalName: json['goalName'] as String?,
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

    // Saving a transaction must feel immediate. The status is fully known
    // locally, so reserve the model for requests that actually need language
    // generation (advice and summaries), rather than for a notification.
    final message = switch (severity) {
      Severity.alert =>
        '$category is over its budget: ${spent.toStringAsFixed(2)} of ${limit!.toStringAsFixed(2)} used.',
      Severity.warning =>
        '$category is at ${(spent / limit! * 100).toStringAsFixed(0)}% of its budget.',
      Severity.info =>
        'Transaction recorded: \$${amount.toStringAsFixed(2)} in $category.',
    };
    return MentorVerdict(severity, message);
  }

  Future<String> _historyBlock({
    int limit = 3,
    int maxCharsPerTurn = 280,
  }) async {
    // recent() includes the just-saved current turn as its newest row --
    // every call site in chat_screen.dart persists the user's message via
    // messagesDao.add() before calling classify()/chat(). Drop the newest
    // row so it isn't duplicated against the userMessage param each caller
    // already appends explicitly. Safe even when nothing was pre-saved
    // (e.g. these unit tests calling agent.chat() directly): dropping "the
    // newest of zero-to-N rows" never removes a real prior turn that
    // wasn't already accounted for.
    final rows = await db.messagesDao.recent(limit + 1);
    final priorTurns = rows.isEmpty ? rows : rows.sublist(0, rows.length - 1);
    if (priorTurns.isEmpty) return '';
    final lines = priorTurns
        .map(
          (m) =>
              '${m.role == 'user' ? 'User' : 'Mentor'}: ${m.content.length > maxCharsPerTurn ? '${m.content.substring(0, maxCharsPerTurn)}…' : m.content}',
        )
        .join('\n');
    return 'Recent conversation:\n$lines\n\n';
  }

  Future<ChatIntent> classify(String userMessage) async {
    final local = _fastIntent(userMessage);
    if (local != null) return local;
    try {
      final raw = await provider.completeFast(
        mentorIntentPrompt,
        'User: $userMessage',
        temperature: 0.0,
      );
      final parsed = _parseIntent(raw);
      // A number added to a category is an expense unless the user explicitly
      // asks to change an ongoing budget cap. This protects the durable
      // transaction path from an over-eager classifier.
      if (parsed.intent == 'update_budget_limit' &&
          !_hasExplicitBudgetLimitLanguage(userMessage)) {
        return ChatIntent(
          intent: 'record_transaction',
          category: parsed.category,
          amount: parsed.newLimit,
        );
      }
      return parsed;
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
      case 'set_savings_goal':
        return _setSavingsGoal(parsed);
      case 'contribute_savings_goal':
        return _contributeSavingsGoal(parsed);
      case 'clear_savings_goal':
        return _clearSavingsGoal();
      case 'financial_checkin':
        return _financialCheckIn();
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
    final (planRows, storedCurrency, globalCurrency, transactions) = await (
      db.budgetsDao.forPeriod(period),
      db.settingsDao.planCurrency(period),
      db.settingsDao.storedDefaultCurrency(),
      db.transactionsDao.search(limit: 500),
    ).wait;
    final currency =
        globalCurrency ??
        storedCurrency ??
        (planRows.isEmpty ? 'USD' : planRows.first.currency);
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

  /// A data-only answer for the most common money questions. It avoids local
  /// model startup and inference, which makes Vector feel immediate while
  /// keeping the advice tied to records the user can inspect.
  Future<MentorChatResult> _financialCheckIn() async {
    final now = DateTime.now();
    final cycle = PlanCycle.fromStorage(await db.settingsDao.planCycle());
    final period = cycle.keyFor(now);
    final start = cycle.startFor(now);
    final end = cycle.endFor(now);
    final (
      budgets,
      storedCurrency,
      globalCurrency,
      transactions,
      subscriptions,
      goal,
    ) = await (
      db.budgetsDao.forPeriod(period),
      db.settingsDao.planCurrency(period),
      db.settingsDao.storedDefaultCurrency(),
      db.transactionsDao.search(limit: 500),
      db.subscriptionsDao.allForScheduling(),
      db.settingsDao.savingsGoal(),
    ).wait;
    final currency =
        globalCurrency ??
        storedCurrency ??
        (budgets.isEmpty ? 'USD' : budgets.first.currency);
    final limits = {
      for (final budget in budgets) budget.category: budget.monthlyLimit,
    };
    final spentByCategory = <String, double>{};
    var ignoredCurrencies = 0;
    for (final transaction in transactions) {
      if (transaction.timestamp.isBefore(start) ||
          !transaction.timestamp.isBefore(end)) {
        continue;
      }
      if (transaction.currency != currency) {
        ignoredCurrencies++;
        continue;
      }
      spentByCategory[transaction.category] =
          (spentByCategory[transaction.category] ?? 0) + transaction.amount;
    }
    final totalSpent = spentByCategory.values.fold<double>(0, (a, b) => a + b);
    final totalLimit = limits.values.fold<double>(0, (a, b) => a + b);
    final recurring = projectSubscriptionChargesInRange(
      subscriptions: subscriptions,
      start: start,
      end: end,
      currency: currency,
      now: now,
    ).total;
    final today = DateTime(now.year, now.month, now.day);
    final daysLeft = end.difference(today).inDays.clamp(1, 366);
    final spendable = calculateSpendableAmount(
      totalLimit: totalLimit,
      totalSpent: totalSpent,
      recurringCommitments: recurring,
      daysLeft: daysLeft,
    );
    final highest = spentByCategory.entries.isEmpty
        ? null
        : spentByCategory.entries.reduce((a, b) => a.value > b.value ? a : b);
    final nearLimit =
        limits.entries
            .where(
              (entry) =>
                  entry.value > 0 &&
                  (spentByCategory[entry.key] ?? 0) / entry.value >= .8,
            )
            .toList()
          ..sort(
            (a, b) => ((spentByCategory[b.key] ?? 0) / b.value).compareTo(
              (spentByCategory[a.key] ?? 0) / a.value,
            ),
          );

    final headline = totalLimit <= 0
        ? 'You have no caps set for this ${cycle.label.toLowerCase()} plan yet.'
        : 'You have spent $currency ${totalSpent.toStringAsFixed(2)} of $currency ${totalLimit.toStringAsFixed(2)}.';
    final nextStep = switch ((
      totalLimit <= 0,
      spendable.availableAfterCommitments <= 0,
      nearLimit.isNotEmpty,
    )) {
      (true, _, _) =>
        'Set category caps to give Vector a usable spending boundary.',
      (_, true, _) => 'Pause discretionary spending until the next plan period and review upcoming charges.',
      (_, _, true) =>
        'Keep ${nearLimit.first.key} to essentials; it is already at ${(((spentByCategory[nearLimit.first.key] ?? 0) / nearLimit.first.value) * 100).toStringAsFixed(0)}% of its cap.',
      _ =>
        'A practical ceiling is $currency ${spendable.dailyAmount.toStringAsFixed(2)} per day for the remaining $daysLeft day${daysLeft == 1 ? '' : 's'}.',
    };
    final topLine = highest == null
        ? ''
        : ' Your largest category is ${highest.key} at $currency ${highest.value.toStringAsFixed(2)}.';
    final goalLine = goal == null
        ? ''
        : ' Your ${goal.name} goal is $currency ${goal.savedAmount.toStringAsFixed(2)} of $currency ${goal.targetAmount.toStringAsFixed(2)}.';
    final currencyLine = ignoredCurrencies == 0
        ? ''
        : ' $ignoredCurrencies transaction${ignoredCurrencies == 1 ? '' : 's'} in another currency ${ignoredCurrencies == 1 ? 'is' : 'are'} excluded.';
    return MentorChatResult(
      content:
          '$headline$topLine$goalLine $nextStep$currencyLine Educational information only, not financial advice.',
    );
  }

  Future<MentorChatResult> _setSavingsGoal(ChatIntent parsed) async {
    final now = DateTime.now();
    final period = await _currentPlanPeriod(now);
    final (current, currency) = await (
      db.settingsDao.savingsGoal(),
      db.settingsDao.planCurrency(period),
    ).wait;
    final target = parsed.amount!;
    final name = parsed.goalName?.trim();
    return MentorChatResult(
      content:
          'Set ${name?.isNotEmpty == true ? name : current?.name ?? 'Savings goal'} to ${(currency ?? current?.currency ?? 'USD')} ${target.toStringAsFixed(2)}?',
      kind: 'plan_action_confirm',
      dataJson: encodePlanActionSummary(
        PlanActionSummary(
          action: 'set_savings_goal',
          goalName: name?.isNotEmpty == true
              ? name
              : current?.name ?? 'Savings goal',
          amount: target,
          savedAmount: current?.savedAmount ?? 0,
          targetCurrency: currency ?? current?.currency ?? 'USD',
        ),
      ),
    );
  }

  Future<MentorChatResult> _contributeSavingsGoal(ChatIntent parsed) async {
    final goal = await db.settingsDao.savingsGoal();
    if (goal == null) {
      return MentorChatResult(
        content: 'Create a savings goal first, then I can track contributions to it.',
      );
    }
    final updated = (goal.savedAmount + parsed.amount!)
        .clamp(0, goal.targetAmount)
        .toDouble();
    return MentorChatResult(
      content:
          'Add ${goal.currency} ${parsed.amount!.toStringAsFixed(2)} to ${goal.name}? Your tracked progress would become ${goal.currency} ${updated.toStringAsFixed(2)}.',
      kind: 'plan_action_confirm',
      dataJson: encodePlanActionSummary(
        PlanActionSummary(
          action: 'set_savings_goal',
          goalName: goal.name,
          amount: goal.targetAmount,
          savedAmount: updated,
          targetCurrency: goal.currency,
        ),
      ),
    );
  }

  Future<MentorChatResult> _clearSavingsGoal() async {
    final goal = await db.settingsDao.savingsGoal();
    if (goal == null) {
      return MentorChatResult(
        content: 'You do not have a savings goal to remove.',
      );
    }
    return MentorChatResult(
      content:
          'Remove your ${goal.name} savings goal? This does not delete any transactions.',
      kind: 'plan_action_confirm',
      dataJson: encodePlanActionSummary(
        const PlanActionSummary(action: 'clear_savings_goal'),
      ),
    );
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
    final requestedCategory = parsed.category!;
    final categories = await db.categoriesDao.all();
    final category = categories
        .where(
          (candidate) =>
              candidate.name.toLowerCase() == requestedCategory.toLowerCase(),
        )
        .map((candidate) => candidate.name)
        .firstOrNull;
    if (category == null) {
      return MentorChatResult(
        content:
            'I could not find "$requestedCategory" in your active categories. Add it first, then I can set its cap.',
      );
    }
    final newLimit = parsed.newLimit!;
    final now = DateTime.now();
    final period = await _currentPlanPeriod(now);
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
    final period = await _currentPlanPeriod(now);
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
    final period = await _currentPlanPeriod(now);
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

  Future<String> _currentPlanPeriod(DateTime now) async {
    final cycle = PlanCycle.fromStorage(await db.settingsDao.planCycle());
    return cycle.keyFor(now);
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
