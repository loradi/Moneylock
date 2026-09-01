import 'dart:convert';

import 'transaction_summary.dart';

class TransactionEditSummary {
  final TransactionSummary transaction;
  final double? newAmount;
  final String? newMerchant;
  final String? newCategory;

  const TransactionEditSummary({
    required this.transaction,
    this.newAmount,
    this.newMerchant,
    this.newCategory,
  });

  factory TransactionEditSummary.fromJson(Map<String, dynamic> json) =>
      TransactionEditSummary(
        transaction: TransactionSummary.fromJson(
          json['transaction'] as Map<String, dynamic>,
        ),
        newAmount: (json['newAmount'] as num?)?.toDouble(),
        newMerchant: json['newMerchant'] as String?,
        newCategory: json['newCategory'] as String?,
      );

  Map<String, dynamic> toJson() => {
    'transaction': transaction.toJson(),
    'newAmount': newAmount,
    'newMerchant': newMerchant,
    'newCategory': newCategory,
  };
}

String encodeTransactionEditSummary(TransactionEditSummary s) =>
    jsonEncode(s.toJson());

TransactionEditSummary decodeTransactionEditSummary(String json) =>
    TransactionEditSummary.fromJson(jsonDecode(json) as Map<String, dynamic>);
