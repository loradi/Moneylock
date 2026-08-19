import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneylock/data/db.dart';
import 'package:moneylock/data/transactions_dao.dart';
import 'package:moneylock/llm/llm_provider.dart';
import 'package:moneylock/llm/mentor_agent.dart';

AppDatabase _db() => AppDatabase.forTesting(
    driftDatabase(name: 'test_${DateTime.now().microsecondsSinceEpoch}'));

class _ScriptedLlm implements LlmProvider {
  final List<String> responses;
  int _calls = 0;
  int get callCount => _calls;
  _ScriptedLlm(this.responses);
  @override
  Future<String> complete(String system, String user, {double temperature = 0.2}) async {
    final r = responses[_calls];
    _calls++;
    return r;
  }
}

class _ThrowingLlm implements LlmProvider {
  @override
  Future<String> complete(String system, String user, {double temperature = 0.2}) async {
    throw Exception('model unavailable');
  }
}

class _CapturingLlm implements LlmProvider {
  final List<String> responses;
  int _calls = 0;
  String? lastUserPrompt;
  _CapturingLlm(this.responses);
  @override
  Future<String> complete(String system, String user, {double temperature = 0.2}) async {
    lastUserPrompt = user;
    final r = responses[_calls];
    _calls++;
    return r;
  }
}

void main() {
  test('chat intent builds a monthly summary context and returns a text result', () async {
    final db = _db();
    await db.budgetsDao.upsert('Groceries', 200.0, '2026-08');
    await db.transactionsDao.insertWithDedup(NewTransaction(
      amount: 15.0,
      currency: 'USD',
      merchant: 'Store',
      category: 'Groceries',
      source: 'manual',
      rawText: 'Store 15.0',
      timestamp: DateTime.now(),
    ));
    final llm = _ScriptedLlm(['{"intent": "chat"}', 'Cut back on takeout this month.']);
    final agent = MentorAgent(llm, db);

    final result = await agent.chat('what can I cut?');

    expect(result.kind, 'text');
    expect(result.content, 'Cut back on takeout this month.');
    expect(result.transactions, isEmpty);
    await db.close();
  });

  test('malformed intent JSON falls back to chat', () async {
    final db = _db();
    final llm = _ScriptedLlm(['not json', 'General advice.']);
    final agent = MentorAgent(llm, db);

    final result = await agent.chat('random question');

    expect(result.kind, 'text');
    expect(result.content, 'General advice.');
    await db.close();
  });

  test('an unrecognized intent string falls back to chat', () async {
    final db = _db();
    final llm = _ScriptedLlm(['{"intent": "do_something_else"}', 'Fallback reply.']);
    final agent = MentorAgent(llm, db);

    final result = await agent.chat('??');

    expect(result.kind, 'text');
    expect(result.content, 'Fallback reply.');
    await db.close();
  });

  test('query_transactions finds matches and computes total in Dart', () async {
    final db = _db();
    await db.transactionsDao.insertWithDedup(NewTransaction(
      amount: 50.0,
      currency: 'USD',
      merchant: 'Nike Store',
      category: 'Shopping & E-commerce',
      source: 'manual',
      rawText: 'Nike Store 50.0',
      timestamp: DateTime.now(),
    ));
    await db.transactionsDao.insertWithDedup(NewTransaction(
      amount: 40.0,
      currency: 'USD',
      merchant: 'Nike Outlet',
      category: 'Shopping & E-commerce',
      source: 'manual',
      rawText: 'Nike Outlet 40.0',
      timestamp: DateTime.now(),
    ));
    final llm = _ScriptedLlm(['{"intent": "query_transactions", "merchant": "Nike"}']);
    final agent = MentorAgent(llm, db);

    final result = await agent.chat('how much on Nike?');

    expect(result.kind, 'transaction_list');
    expect(result.transactions, hasLength(2));
    expect(result.content, contains('90.00'));
    await db.close();
  });

  test('query_transactions with no matches returns a text-only result', () async {
    final db = _db();
    final llm = _ScriptedLlm(['{"intent": "query_transactions", "merchant": "nothing"}']);
    final agent = MentorAgent(llm, db);

    final result = await agent.chat('find nothing');

    expect(result.kind, 'text');
    expect(result.transactions, isEmpty);
    await db.close();
  });

  test('delete_transaction with exactly one match returns delete_confirm', () async {
    final db = _db();
    await db.transactionsDao.insertWithDedup(NewTransaction(
      amount: 89.99,
      currency: 'USD',
      merchant: 'Nike Store',
      category: 'Shopping & E-commerce',
      source: 'manual',
      rawText: 'Nike Store 89.99',
      timestamp: DateTime.now(),
    ));
    final llm = _ScriptedLlm(['{"intent": "delete_transaction", "merchant": "Nike"}']);
    final agent = MentorAgent(llm, db);

    final result = await agent.chat('delete that Nike purchase');

    expect(result.kind, 'delete_confirm');
    expect(result.transactions, hasLength(1));
    await db.close();
  });

  test('delete_transaction with multiple matches returns an informational list, not delete_confirm', () async {
    final db = _db();
    await db.transactionsDao.insertWithDedup(NewTransaction(
      amount: 50.0,
      currency: 'USD',
      merchant: 'Nike Store',
      category: 'Shopping & E-commerce',
      source: 'manual',
      rawText: 'Nike Store 50.0',
      timestamp: DateTime.now(),
    ));
    await db.transactionsDao.insertWithDedup(NewTransaction(
      amount: 40.0,
      currency: 'USD',
      merchant: 'Nike Outlet',
      category: 'Shopping & E-commerce',
      source: 'manual',
      rawText: 'Nike Outlet 40.0',
      timestamp: DateTime.now(),
    ));
    final llm = _ScriptedLlm(['{"intent": "delete_transaction", "merchant": "Nike"}']);
    final agent = MentorAgent(llm, db);

    final result = await agent.chat('delete the Nike one');

    expect(result.kind, 'transaction_list');
    expect(result.transactions, hasLength(2));
    await db.close();
  });

  test('delete_transaction with no matches returns text-only', () async {
    final db = _db();
    final llm = _ScriptedLlm(['{"intent": "delete_transaction", "merchant": "nothing"}']);
    final agent = MentorAgent(llm, db);

    final result = await agent.chat('delete nothing');

    expect(result.kind, 'text');
    expect(result.transactions, isEmpty);
    await db.close();
  });

  test('a model failure on the general-chat path falls back to a canned message, never throws', () async {
    final db = _db();
    final agent = MentorAgent(_ThrowingLlm(), db);

    final result = await agent.chat('anything');

    expect(result.kind, 'text');
    expect(result.content, isNotEmpty);
    await db.close();
  });

  test('query_transactions with more than 20 matches reports the true count/total but caps rendered cards at 20', () async {
    final db = _db();
    for (var i = 0; i < 25; i++) {
      await db.transactionsDao.insertWithDedup(NewTransaction(
        amount: 10.0,
        currency: 'USD',
        merchant: 'Nike Store',
        category: 'Shopping & E-commerce',
        source: 'manual',
        rawText: 'Nike Store 10.0 #$i',
        timestamp: DateTime.now(),
      ));
    }
    final llm = _ScriptedLlm(['{"intent": "query_transactions", "merchant": "Nike"}']);
    final agent = MentorAgent(llm, db);

    final result = await agent.chat('how much on Nike?');

    expect(result.kind, 'transaction_list');
    expect(result.content, contains('Found 25'));
    expect(result.content, contains('250.00'));
    expect(result.transactions, hasLength(20));
    await db.close();
  });

  test('classify() returns the parsed ChatIntent for a scripted response', () async {
    final db = _db();
    final llm = _ScriptedLlm(['{"intent": "query_transactions", "merchant": "Nike"}']);
    final agent = MentorAgent(llm, db);

    final intent = await agent.classify('how much on Nike?');

    expect(intent.intent, 'query_transactions');
    expect(intent.merchant, 'Nike');
    expect(llm.callCount, 1);
    await db.close();
  });

  test('chat() with a preclassified intent skips the classification LLM call', () async {
    final db = _db();
    final llm = _ScriptedLlm(['General advice.']);
    final agent = MentorAgent(llm, db);

    final result = await agent.chat('what can I cut?', preclassified: ChatIntent(intent: 'chat'));

    expect(result.kind, 'text');
    expect(result.content, 'General advice.');
    expect(llm.callCount, 1);
    await db.close();
  });

  test('classify() includes recent conversation history in the prompt sent to the model', () async {
    final db = _db();
    await db.messagesDao.add('user', 'search Nike transactions');
    await db.messagesDao.add('mentor', 'Found 2 matching "Nike", totaling \$90.00.');
    await db.messagesDao.add('user', 'cancel it');
    final llm = _CapturingLlm(['{"intent": "chat"}']);
    final agent = MentorAgent(llm, db);

    await agent.classify('cancel it');

    expect(llm.lastUserPrompt, contains('search Nike transactions'));
    expect(llm.lastUserPrompt, contains('Found 2 matching "Nike"'));
    expect(llm.lastUserPrompt, contains('User: cancel it'));
    await db.close();
  });

  test('_generalChat includes recent conversation history ahead of the financial summary', () async {
    final db = _db();
    await db.messagesDao.add('user', 'what is my biggest expense?');
    await db.messagesDao.add('mentor', 'Groceries, at \$300 this month.');
    await db.messagesDao.add('user', 'how can I cut it?');
    final llm = _CapturingLlm(['{"intent": "chat"}', 'Buy less at the store.']);
    final agent = MentorAgent(llm, db);

    await agent.chat('how can I cut it?');

    expect(llm.lastUserPrompt, contains('what is my biggest expense?'));
    expect(llm.lastUserPrompt, contains('Groceries, at \$300 this month.'));
    await db.close();
  });

  test('classify() with no prior messages sends just the current message, no empty history header', () async {
    final db = _db();
    final llm = _CapturingLlm(['{"intent": "chat"}']);
    final agent = MentorAgent(llm, db);

    await agent.classify('hello');

    expect(llm.lastUserPrompt, 'User: hello');
    await db.close();
  });
}
