import 'dart:convert';

import 'db.dart';

class SubscriptionSummary {
  final int id;
  final String name;
  final String? brandKey;
  final double amount;
  final String currency;
  final String cycle;
  final DateTime nextChargeDate;

  const SubscriptionSummary({
    required this.id,
    required this.name,
    this.brandKey,
    required this.amount,
    required this.currency,
    required this.cycle,
    required this.nextChargeDate,
  });

  factory SubscriptionSummary.fromSubscription(Subscription s) => SubscriptionSummary(
        id: s.id,
        name: s.name,
        brandKey: s.brandKey,
        amount: s.amount,
        currency: s.currency,
        cycle: s.cycle,
        nextChargeDate: s.nextChargeDate,
      );

  factory SubscriptionSummary.fromJson(Map<String, dynamic> json) => SubscriptionSummary(
        id: json['id'] as int,
        name: json['name'] as String,
        brandKey: json['brandKey'] as String?,
        amount: (json['amount'] as num).toDouble(),
        currency: json['currency'] as String,
        cycle: json['cycle'] as String,
        nextChargeDate: DateTime.parse(json['nextChargeDate'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'brandKey': brandKey,
        'amount': amount,
        'currency': currency,
        'cycle': cycle,
        'nextChargeDate': nextChargeDate.toIso8601String(),
      };
}

String encodeSubscriptionSummaries(List<SubscriptionSummary> summaries) =>
    jsonEncode(summaries.map((s) => s.toJson()).toList());

List<SubscriptionSummary> decodeSubscriptionSummaries(String json) =>
    (jsonDecode(json) as List)
        .map((e) => SubscriptionSummary.fromJson(e as Map<String, dynamic>))
        .toList();
