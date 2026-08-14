import 'dart:convert';
import 'fallback_parser.dart';
import 'llm_provider.dart';
import 'prompts.dart';

class CategorizeResult {
  final ParsedTransaction parsed;
  final double confidence;
  CategorizeResult(this.parsed, this.confidence);
}

class CategorizerAgent {
  final LlmProvider provider;
  CategorizerAgent(this.provider);

  Future<CategorizeResult> categorize(String rawText, {String source = 'manual'}) async {
    ParsedTransaction? parsed;
    try {
      final raw = await provider.complete(categorizerSystemPrompt, rawText);
      parsed = _parseJson(raw);
    } catch (_) {
      parsed = null; // LLM no disponible: fallback determinista garantiza el registro
    }
    final result = parsed ?? parseFallback(rawText);
    final confidence = (result?.confidence ?? 0.0).clamp(0.0, 1.0).toDouble();
    return CategorizeResult(result ?? ParsedTransaction(confidence: 0.0), confidence);
  }

  ParsedTransaction? _parseJson(String raw) {
    final match = RegExp(r'\{[^{}]*\}', dotAll: true).firstMatch(raw);
    if (match == null) return null;
    try {
      final map = jsonDecode(match.group(0)!) as Map<String, dynamic>;
      final amount = (map['amount'] as num?)?.toDouble();
      final currency = (map['currency'] as String?)?.toUpperCase();
      final merchant = (map['merchant'] as String?) ?? '';
      final category = (map['category'] as String?) ?? '';
      final confidence = (map['confidence'] as num?)?.toDouble() ?? 0.5;
      if (amount == null || amount <= 0) return null;
      if (currency != null && currency != 'USD' && currency != 'CAD') return null;
      if (!categoryCatalog.contains(category)) return null;
      return ParsedTransaction(
        amount: amount,
        currency: currency ?? 'USD',
        merchant: merchant,
        category: category,
        confidence: confidence.clamp(0.0, 1.0).toDouble(),
      );
    } catch (_) {
      return null;
    }
  }
}