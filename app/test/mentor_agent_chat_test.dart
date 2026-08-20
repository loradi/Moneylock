import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneylock/data/budget_change_summary.dart';
import 'package:moneylock/data/db.dart';
import 'package:moneylock/data/new_subscription_summary.dart';
import 'package:moneylock/data/subscription_summary.dart';
import 'package:moneylock/data/transaction_summary.dart';
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
    expect(result.dataJson, isNull);
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
    expect(decodeTransactionSummaries(result.dataJson!), hasLength(2));
    expect(result.content, contains('90.00'));
    await db.close();
  });

  test('query_transactions with no matches returns a text-only result', () async {
    final db = _db();
    final llm = _ScriptedLlm(['{"intent": "query_transactions", "merchant": "nothing"}']);
    final agent = MentorAgent(llm, db);

    final result = await agent.chat('find nothing');

    expect(result.kind, 'text');
    expect(result.dataJson, isNull);
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
    expect(decodeTransactionSummaries(result.dataJson!), hasLength(1));
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
    expect(decodeTransactionSummaries(result.dataJson!), hasLength(2));
    await db.close();
  });

  test('delete_transaction with no matches returns text-only', () async {
    final db = _db();
    final llm = _ScriptedLlm(['{"intent": "delete_transaction", "merchant": "nothing"}']);
    final agent = MentorAgent(llm, db);

    final result = await agent.chat('delete nothing');

    expect(result.kind, 'text');
    expect(result.dataJson, isNull);
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
    expect(decodeTransactionSummaries(result.dataJson!), hasLength(20));
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

  test('query_subscriptions reports a monthly-equivalent total across mixed cycles', () async {
    final db = _db();
    await db.subscriptionsDao.add(SubscriptionsCompanion.insert(
      name: 'Netflix',
      amount: 15.0,
      cycle: 'monthly',
      nextChargeDate: DateTime(2026, 9, 1),
      createdAt: DateTime.now(),
    ));
    await db.subscriptionsDao.add(SubscriptionsCompanion.insert(
      name: 'Amazon Prime',
      amount: 120.0,
      cycle: 'yearly',
      nextChargeDate: DateTime(2027, 1, 1),
      createdAt: DateTime.now(),
    ));
    final llm = _ScriptedLlm(['{"intent": "query_subscriptions"}']);
    final agent = MentorAgent(llm, db);

    final result = await agent.chat('how much do I pay in subscriptions?');

    expect(result.kind, 'subscription_list');
    expect(decodeSubscriptionSummaries(result.dataJson!), hasLength(2));
    // 15.00 monthly + (120.00 / 12) = 25.00/month, computed in Dart.
    expect(result.content, contains('25.00'));
    await db.close();
  });

  test('query_subscriptions with no matches returns text-only', () async {
    final db = _db();
    final llm = _ScriptedLlm(['{"intent": "query_subscriptions", "merchant": "nothing"}']);
    final agent = MentorAgent(llm, db);

    final result = await agent.chat('find nothing');

    expect(result.kind, 'text');
    expect(result.dataJson, isNull);
    await db.close();
  });

  test('cancel_subscription with exactly one match returns cancel_confirm', () async {
    final db = _db();
    await db.subscriptionsDao.add(SubscriptionsCompanion.insert(
      name: 'Netflix',
      amount: 15.0,
      cycle: 'monthly',
      nextChargeDate: DateTime(2026, 9, 1),
      createdAt: DateTime.now(),
    ));
    final llm = _ScriptedLlm(['{"intent": "cancel_subscription", "merchant": "Netflix"}']);
    final agent = MentorAgent(llm, db);

    final result = await agent.chat('cancel Netflix');

    expect(result.kind, 'cancel_confirm');
    expect(decodeSubscriptionSummaries(result.dataJson!), hasLength(1));
    await db.close();
  });

  test('cancel_subscription with multiple matches returns an informational list, not cancel_confirm', () async {
    final db = _db();
    await db.subscriptionsDao.add(SubscriptionsCompanion.insert(
      name: 'Disney Plus',
      amount: 10.0,
      cycle: 'monthly',
      nextChargeDate: DateTime(2026, 9, 1),
      createdAt: DateTime.now(),
    ));
    await db.subscriptionsDao.add(SubscriptionsCompanion.insert(
      name: 'Disney Bundle',
      amount: 13.0,
      cycle: 'monthly',
      nextChargeDate: DateTime(2026, 9, 5),
      createdAt: DateTime.now(),
    ));
    final llm = _ScriptedLlm(['{"intent": "cancel_subscription", "merchant": "Disney"}']);
    final agent = MentorAgent(llm, db);

    final result = await agent.chat('cancel the Disney one');

    expect(result.kind, 'subscription_list');
    expect(decodeSubscriptionSummaries(result.dataJson!), hasLength(2));
    await db.close();
  });

  test('cancel_subscription with no matches returns text-only', () async {
    final db = _db();
    final llm = _ScriptedLlm(['{"intent": "cancel_subscription", "merchant": "nothing"}']);
    final agent = MentorAgent(llm, db);

    final result = await agent.chat('cancel nothing');

    expect(result.kind, 'text');
    expect(result.dataJson, isNull);
    await db.close();
  });

  test('update_budget_limit with a resolvable category and limit returns budget_confirm', () async {
    final db = _db();
    await db.budgetsDao.upsert('Groceries', 300.0, '2026-08');
    final llm = _ScriptedLlm(
        ['{"intent": "update_budget_limit", "category": "Groceries", "newLimit": 400}']);
    final agent = MentorAgent(llm, db);

    final result = await agent.chat('raise my groceries limit to \$400');

    expect(result.kind, 'budget_confirm');
    final change = decodeBudgetChangeSummary(result.dataJson!);
    expect(change.category, 'Groceries');
    expect(change.currentLimit, 300.0);
    expect(change.proposedLimit, 400.0);
    await db.close();
  });

  test('update_budget_limit with no existing limit for the category treats current as 0', () async {
    final db = _db();
    final llm = _ScriptedLlm(
        ['{"intent": "update_budget_limit", "category": "Travel", "newLimit": 200}']);
    final agent = MentorAgent(llm, db);

    final result = await agent.chat('set my travel limit to \$200');

    expect(result.kind, 'budget_confirm');
    final change = decodeBudgetChangeSummary(result.dataJson!);
    expect(change.currentLimit, 0.0);
    expect(change.proposedLimit, 200.0);
    await db.close();
  });

  test('update_budget_limit with a missing category falls back to chat', () async {
    final db = _db();
    final llm = _ScriptedLlm(['{"intent": "update_budget_limit", "newLimit": 400}', 'General advice.']);
    final agent = MentorAgent(llm, db);

    final result = await agent.chat('raise my limit to \$400');

    expect(result.kind, 'text');
    expect(result.content, 'General advice.');
    await db.close();
  });

  test('update_budget_limit with a missing newLimit falls back to chat', () async {
    final db = _db();
    final llm = _ScriptedLlm(['{"intent": "update_budget_limit", "category": "Groceries"}', 'General advice.']);
    final agent = MentorAgent(llm, db);

    final result = await agent.chat('change my groceries limit');

    expect(result.kind, 'text');
    expect(result.content, 'General advice.');
    await db.close();
  });

  test('update_budget_limit with a mis-cased category resolves to the canonical catalog casing', () async {
    final db = _db();
    await db.budgetsDao.upsert('Groceries', 300.0, '2026-08');
    final llm = _ScriptedLlm(
        ['{"intent": "update_budget_limit", "category": "groceries", "newLimit": 400}']);
    final agent = MentorAgent(llm, db);

    final result = await agent.chat('change my groceries limit to \$400');

    expect(result.kind, 'budget_confirm');
    final change = decodeBudgetChangeSummary(result.dataJson!);
    expect(change.category, 'Groceries');
    await db.close();
  });

  test('update_budget_limit with an off-catalog category falls back to chat', () async {
    final db = _db();
    final llm = _ScriptedLlm(
        ['{"intent": "update_budget_limit", "category": "Foobar", "newLimit": 400}', 'General advice.']);
    final agent = MentorAgent(llm, db);

    final result = await agent.chat('change my foobar limit to \$400');

    expect(result.kind, 'text');
    expect(result.content, 'General advice.');
    await db.close();
  });

  test('classify() recognizes record_transaction and extracts its params', () async {
    final db = _db();
    final llm = _ScriptedLlm(
        ['{"intent": "record_transaction", "category": "Coffee & Dining", "merchant": null}']);
    final agent = MentorAgent(llm, db);

    final intent = await agent.classify('add a new expense for 35 on coffee');

    expect(intent.intent, 'record_transaction');
    expect(intent.category, 'Coffee & Dining');
    await db.close();
  });

  test('chat() with a preclassified record_transaction intent falls through to general chat rather than throwing', () async {
    final db = _db();
    final llm = _ScriptedLlm(['General advice.']);
    final agent = MentorAgent(llm, db);

    final result = await agent.chat(
      'add a new expense for 35 on coffee',
      preclassified: ChatIntent(intent: 'record_transaction', category: 'Coffee & Dining'),
    );

    expect(result.kind, 'text');
    expect(result.content, 'General advice.');
    await db.close();
  });

  test('add_subscription with a day not yet reached this month computes the next charge this month', () async {
    final db = _db();
    final now = DateTime.now();
    final futureDay = (now.day % 27) + 1 > now.day ? (now.day % 27) + 1 : now.day;
    final llm = _ScriptedLlm(
        ['{"intent": "add_subscription", "merchant": "Netflix", "amount": 30, "dayOfMonth": $futureDay}']);
    final agent = MentorAgent(llm, db);

    final result = await agent.chat('add Netflix for \$30 recurring on the ${futureDay}th');

    expect(result.kind, 'add_subscription_confirm');
    final summary = decodeNewSubscriptionSummary(result.dataJson!);
    expect(summary.name, 'Netflix');
    expect(summary.amount, 30.0);
    expect(summary.nextChargeDate.day, futureDay);
    expect(summary.nextChargeDate.month, now.month);
    expect(summary.nextChargeDate.year, now.year);
    await db.close();
  });

  test('add_subscription with a day already passed this month rolls to next month', () async {
    final db = _db();
    final now = DateTime.now();
    final pastDay = now.day > 1 ? now.day - 1 : now.day;
    if (pastDay >= now.day) {
      // Guard: on the 1st of the month there's no "already passed" day to
      // pick, so this scenario doesn't apply today; nothing to assert.
      await db.close();
      return;
    }
    final llm = _ScriptedLlm(
        ['{"intent": "add_subscription", "merchant": "Netflix", "amount": 30, "dayOfMonth": $pastDay}']);
    final agent = MentorAgent(llm, db);

    final result = await agent.chat('add Netflix for \$30 recurring on the ${pastDay}th');

    final summary = decodeNewSubscriptionSummary(result.dataJson!);
    final expectedMonth = now.month == 12 ? 1 : now.month + 1;
    final expectedYear = now.month == 12 ? now.year + 1 : now.year;
    expect(summary.nextChargeDate.month, expectedMonth);
    expect(summary.nextChargeDate.year, expectedYear);
    expect(summary.nextChargeDate.day, pastDay);
    await db.close();
  });

  test('add_subscription with a missing amount falls back to chat', () async {
    final db = _db();
    final llm = _ScriptedLlm(
        ['{"intent": "add_subscription", "merchant": "Netflix", "dayOfMonth": 20}', 'General advice.']);
    final agent = MentorAgent(llm, db);

    final result = await agent.chat('add Netflix recurring on the 20th');

    expect(result.kind, 'text');
    expect(result.content, 'General advice.');
    await db.close();
  });

  test('add_subscription with a missing dayOfMonth falls back to chat', () async {
    final db = _db();
    final llm = _ScriptedLlm(
        ['{"intent": "add_subscription", "merchant": "Netflix", "amount": 30}', 'General advice.']);
    final agent = MentorAgent(llm, db);

    final result = await agent.chat('add Netflix for \$30');

    expect(result.kind, 'text');
    expect(result.content, 'General advice.');
    await db.close();
  });

  test('add_subscription with a missing name falls back to chat', () async {
    final db = _db();
    final llm = _ScriptedLlm(
        ['{"intent": "add_subscription", "amount": 30, "dayOfMonth": 20}', 'General advice.']);
    final agent = MentorAgent(llm, db);

    final result = await agent.chat('add a subscription for \$30 on the 20th');

    expect(result.kind, 'text');
    expect(result.content, 'General advice.');
    await db.close();
  });
}
