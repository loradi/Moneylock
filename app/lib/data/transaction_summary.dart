import 'dart:convert';

import 'db.dart';

class TransactionSummary {
  final int id;
  final String merchant;
  final double amount;
  final String category;
  final DateTime timestamp;

  const TransactionSummary({
    required this.id,
    required this.merchant,
    required this.amount,
    required this.category,
    required this.timestamp,
  });

  factory TransactionSummary.fromTransaction(Transaction t) => TransactionSummary(
        id: t.id,
        merchant: t.merchant,
        amount: t.amount,
        category: t.category,
        timestamp: t.timestamp,
      );

  factory TransactionSummary.fromJson(Map<String, dynamic> json) => TransactionSummary(
        id: json['id'] as int,
        merchant: json['merchant'] as String,
        amount: (json['amount'] as num).toDouble(),
        category: json['category'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'merchant': merchant,
        'amount': amount,
        'category': category,
        'timestamp': timestamp.toIso8601String(),
      };
}

String encodeTransactionSummaries(List<TransactionSummary> summaries) =>
    jsonEncode(summaries.map((s) => s.toJson()).toList());

List<TransactionSummary> decodeTransactionSummaries(String json) =>
    (jsonDecode(json) as List)
        .map((e) => TransactionSummary.fromJson(e as Map<String, dynamic>))
        .toList();
