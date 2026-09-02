import 'dart:convert';

class PlanActionSummary {
  const PlanActionSummary({
    required this.action,
    this.period,
    this.category,
    this.amount,
    this.cycle,
    this.targetCurrency,
    this.rate,
    this.goalName,
    this.savedAmount,
  });

  final String action;
  final String? period;
  final String? category;
  final double? amount;
  final String? cycle;
  final String? targetCurrency;
  final double? rate;
  final String? goalName;
  final double? savedAmount;

  Map<String, dynamic> toJson() => {
    'action': action,
    'period': period,
    'category': category,
    'amount': amount,
    'cycle': cycle,
    'targetCurrency': targetCurrency,
    'rate': rate,
    'goalName': goalName,
    'savedAmount': savedAmount,
  };

  factory PlanActionSummary.fromJson(Map<String, dynamic> json) =>
      PlanActionSummary(
        action: json['action'] as String,
        period: json['period'] as String?,
        category: json['category'] as String?,
        amount: (json['amount'] as num?)?.toDouble(),
        cycle: json['cycle'] as String?,
        targetCurrency: json['targetCurrency'] as String?,
        rate: (json['rate'] as num?)?.toDouble(),
        goalName: json['goalName'] as String?,
        savedAmount: (json['savedAmount'] as num?)?.toDouble(),
      );
}

String encodePlanActionSummary(PlanActionSummary summary) =>
    jsonEncode(summary.toJson());

PlanActionSummary decodePlanActionSummary(String raw) =>
    PlanActionSummary.fromJson(jsonDecode(raw) as Map<String, dynamic>);
