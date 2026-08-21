import 'dart:convert';

class NewSubscriptionSummary {
  final String name;
  final double amount;
  final DateTime nextChargeDate;

  const NewSubscriptionSummary({
    required this.name,
    required this.amount,
    required this.nextChargeDate,
  });

  factory NewSubscriptionSummary.fromJson(Map<String, dynamic> json) => NewSubscriptionSummary(
        name: json['name'] as String,
        amount: (json['amount'] as num).toDouble(),
        nextChargeDate: DateTime.parse(json['nextChargeDate'] as String),
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'amount': amount,
        'nextChargeDate': nextChargeDate.toIso8601String(),
      };
}

String encodeNewSubscriptionSummary(NewSubscriptionSummary s) => jsonEncode(s.toJson());

NewSubscriptionSummary decodeNewSubscriptionSummary(String json) =>
    NewSubscriptionSummary.fromJson(jsonDecode(json) as Map<String, dynamic>);
