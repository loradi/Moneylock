import 'dart:convert';

import 'subscription_summary.dart';

class SubscriptionEditSummary {
  final SubscriptionSummary subscription;
  final double newAmount;

  const SubscriptionEditSummary({
    required this.subscription,
    required this.newAmount,
  });

  factory SubscriptionEditSummary.fromJson(Map<String, dynamic> json) => SubscriptionEditSummary(
        subscription: SubscriptionSummary.fromJson(json['subscription'] as Map<String, dynamic>),
        newAmount: (json['newAmount'] as num).toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'subscription': subscription.toJson(),
        'newAmount': newAmount,
      };
}

String encodeSubscriptionEditSummary(SubscriptionEditSummary s) => jsonEncode(s.toJson());

SubscriptionEditSummary decodeSubscriptionEditSummary(String json) =>
    SubscriptionEditSummary.fromJson(jsonDecode(json) as Map<String, dynamic>);
