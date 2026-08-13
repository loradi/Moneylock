import 'package:flutter_test/flutter_test.dart';
import 'package:moneylock/llm/categorizer_agent.dart';
import 'package:moneylock/llm/llm_provider.dart';

class _FakeLlm implements LlmProvider {
  final String response;
  _FakeLlm(this.response);
  @override
  Future<String> complete(String system, String user, {double temperature = 0.2}) async => response;
}

void main() {
  group('CategorizerAgent', () {
    test('parsea JSON valido del LLM', () async {
      final agent = CategorizerAgent(_FakeLlm(
        '{"amount": 45.5, "currency": "USD", "merchant": "Starbucks", "category": "Coffee & Dining", "confidence": 0.9}'));
      final r = await agent.categorize(r'Starbucks $45.50');
      expect(r.parsed.amount, closeTo(45.5, 0.001));
      expect(r.parsed.merchant, 'Starbucks');
      expect(r.parsed.category, 'Coffee & Dining');
      expect(r.confidence, closeTo(0.9, 0.001));
    });

    test('JSON invalido -> fallback determinista', () async {
      final agent = CategorizerAgent(_FakeLlm('I cannot parse that.'));
      final r = await agent.categorize(r'Starbucks $12.50');
      expect(r.parsed.amount, closeTo(12.5, 0.001));
      expect(r.parsed.category, 'Coffee & Dining');
      expect(r.parsed.merchant, 'Starbucks');
    });

    test('categoria fuera del catalogo -> fallback', () async {
      final agent = CategorizerAgent(_FakeLlm(
        '{"amount": 5, "currency": "USD", "merchant": "X", "category": "Nonsense", "confidence": 0.8}'));
      final r = await agent.categorize('X 5 USD');
      expect(r.parsed.category, isNot('Nonsense'));
    });
  });
}