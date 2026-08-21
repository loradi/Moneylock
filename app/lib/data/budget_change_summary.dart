import 'dart:convert';

class BudgetChangeSummary {
  final String category;
  final double currentLimit;
  final double proposedLimit;
  final String period;

  const BudgetChangeSummary({
    required this.category,
    required this.currentLimit,
    required this.proposedLimit,
    required this.period,
  });

  factory BudgetChangeSummary.fromJson(Map<String, dynamic> json) => BudgetChangeSummary(
        category: json['category'] as String,
        currentLimit: (json['currentLimit'] as num).toDouble(),
        proposedLimit: (json['proposedLimit'] as num).toDouble(),
        period: json['period'] as String,
      );

  Map<String, dynamic> toJson() => {
        'category': category,
        'currentLimit': currentLimit,
        'proposedLimit': proposedLimit,
        'period': period,
      };
}

String encodeBudgetChangeSummary(BudgetChangeSummary s) => jsonEncode(s.toJson());

BudgetChangeSummary decodeBudgetChangeSummary(String json) =>
    BudgetChangeSummary.fromJson(jsonDecode(json) as Map<String, dynamic>);
