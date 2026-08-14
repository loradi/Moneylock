import 'package:moneylock/data/db.dart';

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
}