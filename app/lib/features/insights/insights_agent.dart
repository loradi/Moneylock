const disclaimer = 'Educational information only, not financial advice.';

class BudgetSummary {
  final double totalSpent;
  final double totalLimit;
  final Map<String, double> byCategory;

  /// Límites mensuales por categoría (~v1: solo pide [byCategory], pero las
  /// barras del Dashboard necesitan el límite de cada categoría).
  final Map<String, double> byCategoryLimits;
  BudgetSummary({
    required this.totalSpent,
    required this.totalLimit,
    required this.byCategory,
    this.byCategoryLimits = const {},
  });
}

class InsightCapsule {
  final String title;
  final String body;
  InsightCapsule(this.title, this.body);
}

List<InsightCapsule> generateInsights(BudgetSummary s) {
  if (s.totalSpent <= 0) {
    return [InsightCapsule('Start tracking',
        'Add your first transaction to unlock spending insights. $disclaimer')];
  }
  final top = s.byCategory.entries
      .map((e) => (cat: e.key, pct: e.value / s.totalSpent))
      .toList()
    ..sort((a, b) => b.pct.compareTo(a.pct));
  final dominant = top.first;
  final pct = (dominant.pct * 100).toStringAsFixed(0);
  return [
    InsightCapsule('${dominant.cat} dominates',
        '$pct% of your spending went to ${dominant.cat} this month. '
        'Households in this pattern typically respond to category limits. '
        'Consider a monthly cap to retake control. $disclaimer'),
    InsightCapsule('Budget health',
        s.totalLimit > 0
            ? 'You have used ${(s.totalSpent / s.totalLimit * 100).toStringAsFixed(0)}% '
                'of your total monthly budget. $disclaimer'
            : 'Set category budgets in Settings to track limit health. $disclaimer'),
  ];
}