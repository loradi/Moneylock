# Mentor CRUD expansion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the mentor add a subscription, edit an existing transaction or subscription, answer "last N transactions" precisely, and answer "what am I spending the most on?" with a Dart-computed fact instead of model guesswork.

**Architecture:** Adds three more intents (`add_subscription`, `edit_transaction`, `edit_subscription`) to the existing `MentorAgent.chat()` router, reusing the exact same DAO-search → summary-DTO → structured-chat-message → confirm-button pattern already shipped for transactions/subscriptions/budget limits. Adds a `count` field to the existing `query_transactions` intent and a Dart-computed "highest spending category" line to `_generalChat()`'s context.

**Tech Stack:** Flutter/Dart, Riverpod, Drift/SQLite (same as the rest of this codebase).

## Global Constraints

- All UI copy is in English. No Spanish (or any other language) strings in any user-facing text, including LLM prompts.
- The mentor never mutates data itself. Adding a subscription, editing a transaction, and editing a subscription all require the user to tap a real, dedicated Confirm button — free-text confirmation is never sufficient.
- A mutating button (Confirm/Delete/Cancel) is never shown next to an ambiguous (2+ match) search result — only when a search narrows to exactly one candidate.
- Count/total arithmetic — and now "which category is highest" — is always computed in Dart, never delegated to the on-device model.
- `DateTime` month/year arithmetic uses direct constructor arithmetic (`DateTime(y, m±n, d)`), never `Duration`-based.

---

### Task 1: Data layer — `TransactionsDao.updateFields` + three new summary DTOs

**Files:**
- Modify: `app/lib/data/transactions_dao.dart`
- Create: `app/lib/data/new_subscription_summary.dart`
- Create: `app/lib/data/transaction_edit_summary.dart`
- Create: `app/lib/data/subscription_edit_summary.dart`
- Test: `app/test/transactions_dao_update_fields_test.dart`
- Test: `app/test/new_subscription_summary_test.dart`
- Test: `app/test/transaction_edit_summary_test.dart`
- Test: `app/test/subscription_edit_summary_test.dart`

**Interfaces:**
- Produces: `TransactionsDao.updateFields(int id, {double? amount, String? merchant})`; `NewSubscriptionSummary{name, amount, nextChargeDate}` with `.fromJson`/`.toJson`/`encodeNewSubscriptionSummary`/`decodeNewSubscriptionSummary` (single object); `TransactionEditSummary{transaction: TransactionSummary, newAmount: double?, newMerchant: String?}` with `.fromJson`/`.toJson`/`encodeTransactionEditSummary`/`decodeTransactionEditSummary`; `SubscriptionEditSummary{subscription: SubscriptionSummary, newAmount: double}` with the same shape. Tasks 2-4 consume these directly.

- [ ] **Step 1: Write the failing `updateFields` tests**

Create `app/test/transactions_dao_update_fields_test.dart`:

```dart
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneylock/data/db.dart';

AppDatabase _db() => AppDatabase.forTesting(
    driftDatabase(name: 'test_${DateTime.now().microsecondsSinceEpoch}'));

Future<int> _addTx(AppDatabase db) async {
  final outcome = await db.transactionsDao.insertWithDedup(NewTransaction(
    amount: 20.0,
    currency: 'USD',
    merchant: 'Old Store',
    category: 'Other',
    source: 'manual',
    rawText: 'Old Store 20.0',
    timestamp: DateTime.now(),
  ));
  return outcome.transaction!.id;
}

void main() {
  test('updateFields updates only amount when merchant is omitted', () async {
    final db = _db();
    final id = await _addTx(db);

    await db.transactionsDao.updateFields(id, amount: 50.0);

    final row = await (db.select(db.transactions)..where((t) => t.id.equals(id))).getSingle();
    expect(row.amount, 50.0);
    expect(row.merchant, 'Old Store');
    await db.close();
  });

  test('updateFields updates only merchant when amount is omitted', () async {
    final db = _db();
    final id = await _addTx(db);

    await db.transactionsDao.updateFields(id, merchant: 'New Store');

    final row = await (db.select(db.transactions)..where((t) => t.id.equals(id))).getSingle();
    expect(row.amount, 20.0);
    expect(row.merchant, 'New Store');
    await db.close();
  });

  test('updateFields updates both fields when both are given', () async {
    final db = _db();
    final id = await _addTx(db);

    await db.transactionsDao.updateFields(id, amount: 50.0, merchant: 'New Store');

    final row = await (db.select(db.transactions)..where((t) => t.id.equals(id))).getSingle();
    expect(row.amount, 50.0);
    expect(row.merchant, 'New Store');
    await db.close();
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd app && flutter test test/transactions_dao_update_fields_test.dart -r expanded`
Expected: FAIL — `updateFields` is not defined on `TransactionsDao`.

- [ ] **Step 3: Implement `TransactionsDao.updateFields`**

In `app/lib/data/transactions_dao.dart`, add this method to the `TransactionsDao` class (alongside `updateMostRecentCategory`):

```dart
  Future<void> updateFields(int id, {double? amount, String? merchant}) =>
      (db.update(db.transactions)..where((row) => row.id.equals(id))).write(
        TransactionsCompanion(
          amount: amount == null ? const Value.absent() : Value(amount),
          merchant: merchant == null ? const Value.absent() : Value(merchant),
        ),
      );
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd app && flutter test test/transactions_dao_update_fields_test.dart -r expanded`
Expected: 3 tests pass.

- [ ] **Step 5: Write the failing DTO tests**

Create `app/test/new_subscription_summary_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:moneylock/data/new_subscription_summary.dart';

void main() {
  test('round-trips through JSON encode/decode', () {
    final original = NewSubscriptionSummary(
      name: 'Netflix',
      amount: 30.0,
      nextChargeDate: DateTime(2026, 9, 20),
    );

    final decoded = decodeNewSubscriptionSummary(encodeNewSubscriptionSummary(original));

    expect(decoded.name, 'Netflix');
    expect(decoded.amount, 30.0);
    expect(decoded.nextChargeDate, DateTime(2026, 9, 20));
  });
}
```

Create `app/test/transaction_edit_summary_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:moneylock/data/transaction_edit_summary.dart';
import 'package:moneylock/data/transaction_summary.dart';

void main() {
  test('round-trips through JSON encode/decode, including a null newMerchant', () {
    final original = TransactionEditSummary(
      transaction: TransactionSummary(
        id: 1,
        merchant: 'Store',
        amount: 45.0,
        category: 'Other',
        timestamp: DateTime(2026, 8, 1),
      ),
      newAmount: 50.0,
      newMerchant: null,
    );

    final decoded = decodeTransactionEditSummary(encodeTransactionEditSummary(original));

    expect(decoded.transaction.merchant, 'Store');
    expect(decoded.newAmount, 50.0);
    expect(decoded.newMerchant, isNull);
  });
}
```

Create `app/test/subscription_edit_summary_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:moneylock/data/subscription_edit_summary.dart';
import 'package:moneylock/data/subscription_summary.dart';

void main() {
  test('round-trips through JSON encode/decode', () {
    final original = SubscriptionEditSummary(
      subscription: SubscriptionSummary(
        id: 1,
        name: 'Netflix',
        brandKey: 'netflix',
        amount: 15.99,
        currency: 'USD',
        cycle: 'monthly',
        nextChargeDate: DateTime(2026, 9, 1),
      ),
      newAmount: 18.99,
    );

    final decoded = decodeSubscriptionEditSummary(encodeSubscriptionEditSummary(original));

    expect(decoded.subscription.name, 'Netflix');
    expect(decoded.newAmount, 18.99);
  });
}
```

- [ ] **Step 6: Run the tests to verify they fail**

Run: `cd app && flutter test test/new_subscription_summary_test.dart test/transaction_edit_summary_test.dart test/subscription_edit_summary_test.dart -r expanded`
Expected: FAIL — none of the three files exist yet.

- [ ] **Step 7: Create the three DTOs**

Create `app/lib/data/new_subscription_summary.dart`:

```dart
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
```

Create `app/lib/data/transaction_edit_summary.dart`:

```dart
import 'dart:convert';

import 'transaction_summary.dart';

class TransactionEditSummary {
  final TransactionSummary transaction;
  final double? newAmount;
  final String? newMerchant;

  const TransactionEditSummary({
    required this.transaction,
    this.newAmount,
    this.newMerchant,
  });

  factory TransactionEditSummary.fromJson(Map<String, dynamic> json) => TransactionEditSummary(
        transaction: TransactionSummary.fromJson(json['transaction'] as Map<String, dynamic>),
        newAmount: (json['newAmount'] as num?)?.toDouble(),
        newMerchant: json['newMerchant'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'transaction': transaction.toJson(),
        'newAmount': newAmount,
        'newMerchant': newMerchant,
      };
}

String encodeTransactionEditSummary(TransactionEditSummary s) => jsonEncode(s.toJson());

TransactionEditSummary decodeTransactionEditSummary(String json) =>
    TransactionEditSummary.fromJson(jsonDecode(json) as Map<String, dynamic>);
```

Create `app/lib/data/subscription_edit_summary.dart`:

```dart
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
```

- [ ] **Step 8: Run the tests to verify they pass**

Run: `cd app && flutter test test/transactions_dao_update_fields_test.dart test/new_subscription_summary_test.dart test/transaction_edit_summary_test.dart test/subscription_edit_summary_test.dart -r expanded`
Expected: 6 tests pass (3 + 1 + 1 + 1).

- [ ] **Step 9: Run `flutter analyze`**

Run: `cd app && flutter analyze`
Expected: only the same 11 pre-existing info-level issues, nothing new.

- [ ] **Step 10: Commit**

```bash
cd app
git add lib/data/transactions_dao.dart lib/data/new_subscription_summary.dart lib/data/transaction_edit_summary.dart lib/data/subscription_edit_summary.dart test/transactions_dao_update_fields_test.dart test/new_subscription_summary_test.dart test/transaction_edit_summary_test.dart test/subscription_edit_summary_test.dart
git commit -m "feat: add TransactionsDao.updateFields and three new summary DTOs for the mentor CRUD expansion"
```

---

### Task 2: `add_subscription` intent

**Files:**
- Modify: `app/lib/llm/prompts.dart`
- Modify: `app/lib/llm/mentor_agent.dart`
- Test: `app/test/mentor_agent_chat_test.dart`

**Interfaces:**
- Consumes: `NewSubscriptionSummary`/`encodeNewSubscriptionSummary` (Task 1), `SubscriptionsDao.add` (already existing).
- Produces: `ChatIntent` gains `double? amount` and `int? dayOfMonth` fields (both also reused by Tasks 3-4). `MentorChatResult` with `kind: 'add_subscription_confirm'`.

- [ ] **Step 1: Write the failing tests**

Append to `app/test/mentor_agent_chat_test.dart` (add `import 'package:moneylock/data/new_subscription_summary.dart';`):

```dart
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd app && flutter test test/mentor_agent_chat_test.dart -r expanded`
Expected: the 5 new tests FAIL — `add_subscription` isn't recognized yet.

- [ ] **Step 3: Extend `mentorIntentPrompt`**

In `app/lib/llm/prompts.dart`, change the JSON shape line from:

```dart
{"intent": "chat"|"query_transactions"|"delete_transaction"|"query_subscriptions"|"cancel_subscription"|"update_budget_limit"|"record_transaction",
 "category": "<one of: ${categoryCatalog.join(', ')}>"|null,
 "merchant": "<short keyword or null>", "monthsBack": <integer or null>,
 "newLimit": <number or null>}
```

to:

```dart
{"intent": "chat"|"query_transactions"|"delete_transaction"|"query_subscriptions"|"cancel_subscription"|"update_budget_limit"|"record_transaction"|"add_subscription",
 "category": "<one of: ${categoryCatalog.join(', ')}>"|null,
 "merchant": "<short keyword or null>", "monthsBack": <integer or null>,
 "newLimit": <number or null>, "amount": <number or null>, "dayOfMonth": <integer 1-31 or null>}
```

Add a new rule after the existing `record_transaction` rule:

```
- "add_subscription" is for requests to add a new recurring monthly
  subscription (e.g. "add Netflix for $30 recurring on the 20th", "add a
  new subscription: Spotify, $12, charges on the 5th"). Requires "merchant"
  (the subscription's name), "amount" (the monthly charge as a plain
  number), and "dayOfMonth" (the day of the month it recurs on, 1-31) --
  if any of the three can't be confidently determined, use "chat" instead
  of guessing. Only monthly subscriptions can be added this way; if the
  user asks for a yearly one, use "chat".
- "amount" is the requested monetary amount as a plain number, used by
  "add_subscription" (the subscription's charge), else null.
- "dayOfMonth" is the day of the month (1-31) a new subscription recurs
  on, used only by "add_subscription", else null.
```

Add one more example at the end:

```
"add Netflix for \$30 recurring on the 20th" -> {"intent": "add_subscription", "category": null, "merchant": "Netflix", "monthsBack": null, "newLimit": null, "amount": 30, "dayOfMonth": 20}
```

- [ ] **Step 4: Extend `ChatIntent` and `_parseIntent`**

In `app/lib/llm/mentor_agent.dart`, change `ChatIntent` from:

```dart
class ChatIntent {
  final String intent;
  final String? category;
  final String? merchant;
  final int? monthsBack;
  final double? newLimit;
  ChatIntent({
    required this.intent,
    this.category,
    this.merchant,
    this.monthsBack,
    this.newLimit,
  });
}
```

to:

```dart
class ChatIntent {
  final String intent;
  final String? category;
  final String? merchant;
  final int? monthsBack;
  final double? newLimit;
  final double? amount;
  final int? dayOfMonth;
  ChatIntent({
    required this.intent,
    this.category,
    this.merchant,
    this.monthsBack,
    this.newLimit,
    this.amount,
    this.dayOfMonth,
  });
}
```

Change `_parseIntent`'s `recognized` set to add `'add_subscription'`:

```dart
    const recognized = {
      'query_transactions',
      'delete_transaction',
      'query_subscriptions',
      'cancel_subscription',
      'update_budget_limit',
      'record_transaction',
      'add_subscription',
    };
```

Add a presence check for `add_subscription` right after the existing `update_budget_limit` check (both live inside the same `try` block, after the `recognized.contains` guard and before the final `return ChatIntent(...)`):

```dart
    if (intent == 'add_subscription' &&
        (json['merchant'] == null || json['amount'] == null || json['dayOfMonth'] == null)) {
      return ChatIntent(intent: 'chat');
    }
```

Add `amount`/`dayOfMonth` to the final `return ChatIntent(...)` call at the bottom of `_parseIntent`:

```dart
    return ChatIntent(
      intent: intent,
      category: category,
      merchant: json['merchant'] as String?,
      monthsBack: (json['monthsBack'] as num?)?.toInt(),
      newLimit: (json['newLimit'] as num?)?.toDouble(),
      amount: (json['amount'] as num?)?.toDouble(),
      dayOfMonth: (json['dayOfMonth'] as num?)?.toInt(),
    );
```

- [ ] **Step 5: Add `_addSubscription` and wire the switch**

Add `import '../data/new_subscription_summary.dart';` to the top of `app/lib/llm/mentor_agent.dart`.

Change `chat()`'s switch to add one more case (alongside the others, before `default`):

```dart
      case 'add_subscription':
        return _addSubscription(parsed);
```

Add this method after `_updateBudgetLimit`:

```dart
  Future<MentorChatResult> _addSubscription(ChatIntent parsed) async {
    final name = parsed.merchant!;
    final amount = parsed.amount!;
    final dayOfMonth = parsed.dayOfMonth!;
    final now = DateTime.now();
    final nextChargeDate = now.day <= dayOfMonth
        ? DateTime(now.year, now.month, dayOfMonth)
        : DateTime(now.year, now.month + 1, dayOfMonth);
    final summary = NewSubscriptionSummary(
      name: name,
      amount: amount,
      nextChargeDate: nextChargeDate,
    );
    final monthName = const [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ][nextChargeDate.month - 1];
    return MentorChatResult(
      content: 'Add $name at \$${amount.toStringAsFixed(2)}/month, '
          'starting $monthName ${nextChargeDate.day}?',
      kind: 'add_subscription_confirm',
      dataJson: encodeNewSubscriptionSummary(summary),
    );
  }
```

(`parsed.merchant!`/`parsed.amount!`/`parsed.dayOfMonth!` are safe: `_parseIntent`'s guard in Step 4 only ever produces `intent: 'add_subscription'` when all three are non-null.)

- [ ] **Step 6: Run the tests to verify they pass**

Run: `cd app && flutter test test/mentor_agent_chat_test.dart -r expanded`
Expected: all pass (35 total: 30 existing + 5 new).

- [ ] **Step 7: Run `flutter analyze`**

Run: `cd app && flutter analyze`
Expected: only the same 11 pre-existing info-level issues, nothing new.

- [ ] **Step 8: Commit**

```bash
cd app
git add lib/llm/prompts.dart lib/llm/mentor_agent.dart test/mentor_agent_chat_test.dart
git commit -m "feat: add add_subscription intent to mentor chat"
```

---

### Task 3: `edit_transaction` intent

**Files:**
- Modify: `app/lib/llm/prompts.dart`
- Modify: `app/lib/llm/mentor_agent.dart`
- Test: `app/test/mentor_agent_chat_test.dart`

**Interfaces:**
- Consumes: `TransactionEditSummary`/`encodeTransactionEditSummary` (Task 1), `TransactionsDao.search`/`.updateFields` (Task 1 / already existing), `ChatIntent.amount` (Task 2, reused here as "the new amount").
- Produces: `ChatIntent` gains `String? newMerchant`. `MentorChatResult` with `kind: 'edit_transaction_confirm'`.

- [ ] **Step 1: Write the failing tests**

Append to `app/test/mentor_agent_chat_test.dart` (add `import 'package:moneylock/data/transaction_edit_summary.dart';`):

```dart
  test('edit_transaction with exactly one match and a new amount returns edit_transaction_confirm', () async {
    final db = _db();
    await db.transactionsDao.insertWithDedup(NewTransaction(
      amount: 45.0,
      currency: 'USD',
      merchant: 'Nike Store',
      category: 'Shopping & E-commerce',
      source: 'manual',
      rawText: 'Nike Store 45.0',
      timestamp: DateTime.now(),
    ));
    final llm = _ScriptedLlm(['{"intent": "edit_transaction", "merchant": "Nike", "amount": 50}']);
    final agent = MentorAgent(llm, db);

    final result = await agent.chat('change my Nike purchase to \$50');

    expect(result.kind, 'edit_transaction_confirm');
    final edit = decodeTransactionEditSummary(result.dataJson!);
    expect(edit.transaction.merchant, 'Nike Store');
    expect(edit.newAmount, 50.0);
    expect(edit.newMerchant, isNull);
    await db.close();
  });

  test('edit_transaction with multiple matches returns an informational list, not a confirm card', () async {
    final db = _db();
    await db.transactionsDao.insertWithDedup(NewTransaction(
      amount: 45.0,
      currency: 'USD',
      merchant: 'Nike Store',
      category: 'Shopping & E-commerce',
      source: 'manual',
      rawText: 'Nike Store 45.0',
      timestamp: DateTime.now(),
    ));
    await db.transactionsDao.insertWithDedup(NewTransaction(
      amount: 30.0,
      currency: 'USD',
      merchant: 'Nike Outlet',
      category: 'Shopping & E-commerce',
      source: 'manual',
      rawText: 'Nike Outlet 30.0',
      timestamp: DateTime.now(),
    ));
    final llm = _ScriptedLlm(['{"intent": "edit_transaction", "merchant": "Nike", "amount": 50}']);
    final agent = MentorAgent(llm, db);

    final result = await agent.chat('change the Nike one to \$50');

    expect(result.kind, 'transaction_list');
    await db.close();
  });

  test('edit_transaction with no matches returns text-only', () async {
    final db = _db();
    final llm = _ScriptedLlm(['{"intent": "edit_transaction", "merchant": "nothing", "amount": 50}']);
    final agent = MentorAgent(llm, db);

    final result = await agent.chat('change the nothing purchase to \$50');

    expect(result.kind, 'text');
    await db.close();
  });

  test('edit_transaction with neither amount nor newMerchant falls back to chat', () async {
    final db = _db();
    final llm = _ScriptedLlm(['{"intent": "edit_transaction", "merchant": "Nike"}', 'General advice.']);
    final agent = MentorAgent(llm, db);

    final result = await agent.chat('change my Nike purchase');

    expect(result.kind, 'text');
    expect(result.content, 'General advice.');
    await db.close();
  });

  test('edit_transaction can change the merchant instead of the amount', () async {
    final db = _db();
    await db.transactionsDao.insertWithDedup(NewTransaction(
      amount: 45.0,
      currency: 'USD',
      merchant: 'Store',
      category: 'Shopping & E-commerce',
      source: 'manual',
      rawText: 'Store 45.0',
      timestamp: DateTime.now(),
    ));
    final llm = _ScriptedLlm(
        ['{"intent": "edit_transaction", "merchant": "Store", "newMerchant": "Starbucks"}']);
    final agent = MentorAgent(llm, db);

    final result = await agent.chat('rename my store purchase to Starbucks');

    expect(result.kind, 'edit_transaction_confirm');
    final edit = decodeTransactionEditSummary(result.dataJson!);
    expect(edit.newAmount, isNull);
    expect(edit.newMerchant, 'Starbucks');
    await db.close();
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd app && flutter test test/mentor_agent_chat_test.dart -r expanded`
Expected: the 5 new tests FAIL — `edit_transaction` isn't recognized yet.

- [ ] **Step 3: Extend `mentorIntentPrompt`**

In `app/lib/llm/prompts.dart`, change the JSON shape line (from Task 2's version) to add `edit_transaction` to the enum and a `newMerchant` field:

```dart
{"intent": "chat"|"query_transactions"|"delete_transaction"|"query_subscriptions"|"cancel_subscription"|"update_budget_limit"|"record_transaction"|"add_subscription"|"edit_transaction",
 "category": "<one of: ${categoryCatalog.join(', ')}>"|null,
 "merchant": "<short keyword or null>", "monthsBack": <integer or null>,
 "newLimit": <number or null>, "amount": <number or null>, "dayOfMonth": <integer 1-31 or null>,
 "newMerchant": "<string or null>"}
```

Add a new rule after `add_subscription`'s rule:

```
- "edit_transaction" is for requests to correct a specific past
  transaction's amount and/or merchant name (e.g. "change my Nike purchase
  to $50", "the Starbucks charge should say Peet's Coffee instead"). Same
  search fields as "delete_transaction" ("category"/"merchant"/
  "monthsBack" identify WHICH transaction), plus "amount" (the corrected
  amount) and/or "newMerchant" (the corrected merchant name) for WHAT to
  change -- at least one of "amount"/"newMerchant" is required, else use
  "chat".
- "newMerchant" is the corrected merchant name if the intent is
  "edit_transaction", else null.
```

Add one more example:

```
"change my Nike purchase to \$50" -> {"intent": "edit_transaction", "category": null, "merchant": "Nike", "monthsBack": null, "newLimit": null, "amount": 50, "dayOfMonth": null, "newMerchant": null}
```

- [ ] **Step 4: Extend `ChatIntent` and `_parseIntent`**

In `app/lib/llm/mentor_agent.dart`, add `final String? newMerchant;` and the matching constructor parameter to `ChatIntent` (alongside `amount`/`dayOfMonth`).

Add `'edit_transaction'` to `_parseIntent`'s `recognized` set.

Add a presence check after the `add_subscription` check from Task 2:

```dart
    if (intent == 'edit_transaction' && json['amount'] == null && json['newMerchant'] == null) {
      return ChatIntent(intent: 'chat');
    }
```

Add `newMerchant` to the final `return ChatIntent(...)`:

```dart
      newMerchant: json['newMerchant'] as String?,
```

- [ ] **Step 5: Add `_editTransactionCandidate` and wire the switch**

Add `import '../data/transaction_edit_summary.dart';` to the top of `app/lib/llm/mentor_agent.dart`.

Add one more case to `chat()`'s switch:

```dart
      case 'edit_transaction':
        return _editTransactionCandidate(parsed);
```

Add this method after `_addSubscription`:

```dart
  Future<MentorChatResult> _editTransactionCandidate(ChatIntent parsed) async {
    final rows = await db.transactionsDao.search(
      category: parsed.category,
      merchantKeyword: parsed.merchant,
      since: _sinceFromMonthsBack(parsed.monthsBack),
      limit: 5,
    );
    final summaries = rows.map(TransactionSummary.fromTransaction).toList();
    if (summaries.isEmpty) {
      return MentorChatResult(content: "I couldn't find a transaction matching that.");
    }
    if (summaries.length > 1) {
      return MentorChatResult(
        content:
            'Found ${summaries.length} transactions matching that -- can you be more specific (date, amount, or exact merchant)?',
        kind: 'transaction_list',
        dataJson: encodeTransactionSummaries(summaries),
      );
    }
    final target = summaries.first;
    final parts = <String>[];
    if (parsed.amount != null) {
      parts.add('amount from \$${target.amount.toStringAsFixed(2)} to \$${parsed.amount!.toStringAsFixed(2)}');
    }
    if (parsed.newMerchant != null) {
      parts.add("merchant from '${target.merchant}' to '${parsed.newMerchant}'");
    }
    final edit = TransactionEditSummary(
      transaction: target,
      newAmount: parsed.amount,
      newMerchant: parsed.newMerchant,
    );
    return MentorChatResult(
      content: 'Change this transaction\'s ${parts.join(' and ')}?',
      kind: 'edit_transaction_confirm',
      dataJson: encodeTransactionEditSummary(edit),
    );
  }
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `cd app && flutter test test/mentor_agent_chat_test.dart -r expanded`
Expected: all pass (40 total: 35 + 5).

- [ ] **Step 7: Run `flutter analyze`**

Run: `cd app && flutter analyze`
Expected: only the same 11 pre-existing info-level issues, nothing new.

- [ ] **Step 8: Commit**

```bash
cd app
git add lib/llm/prompts.dart lib/llm/mentor_agent.dart test/mentor_agent_chat_test.dart
git commit -m "feat: add edit_transaction intent to mentor chat"
```

---

### Task 4: `edit_subscription` intent

**Files:**
- Modify: `app/lib/llm/prompts.dart`
- Modify: `app/lib/llm/mentor_agent.dart`
- Test: `app/test/mentor_agent_chat_test.dart`

**Interfaces:**
- Consumes: `SubscriptionEditSummary`/`encodeSubscriptionEditSummary` (Task 1), `SubscriptionsDao.search`/`.update` (already existing), `ChatIntent.amount` (Task 2, reused here too — no new `ChatIntent` fields needed for this task).
- Produces: `MentorChatResult` with `kind: 'edit_subscription_confirm'`.

- [ ] **Step 1: Write the failing tests**

Append to `app/test/mentor_agent_chat_test.dart` (add `import 'package:moneylock/data/subscription_edit_summary.dart';`):

```dart
  test('edit_subscription with exactly one match returns edit_subscription_confirm', () async {
    final db = _db();
    await db.subscriptionsDao.add(SubscriptionsCompanion.insert(
      name: 'Netflix',
      amount: 15.99,
      cycle: 'monthly',
      nextChargeDate: DateTime(2026, 9, 1),
      createdAt: DateTime.now(),
    ));
    final llm = _ScriptedLlm(['{"intent": "edit_subscription", "merchant": "Netflix", "amount": 18.99}']);
    final agent = MentorAgent(llm, db);

    final result = await agent.chat('change Netflix to \$18.99');

    expect(result.kind, 'edit_subscription_confirm');
    final edit = decodeSubscriptionEditSummary(result.dataJson!);
    expect(edit.subscription.name, 'Netflix');
    expect(edit.newAmount, 18.99);
    await db.close();
  });

  test('edit_subscription with multiple matches returns an informational list, not a confirm card', () async {
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
    final llm = _ScriptedLlm(['{"intent": "edit_subscription", "merchant": "Disney", "amount": 15}']);
    final agent = MentorAgent(llm, db);

    final result = await agent.chat('change the Disney one to \$15');

    expect(result.kind, 'subscription_list');
    await db.close();
  });

  test('edit_subscription with no matches returns text-only', () async {
    final db = _db();
    final llm = _ScriptedLlm(['{"intent": "edit_subscription", "merchant": "nothing", "amount": 15}']);
    final agent = MentorAgent(llm, db);

    final result = await agent.chat('change nothing to \$15');

    expect(result.kind, 'text');
    await db.close();
  });

  test('edit_subscription with a missing amount falls back to chat', () async {
    final db = _db();
    final llm = _ScriptedLlm(['{"intent": "edit_subscription", "merchant": "Netflix"}', 'General advice.']);
    final agent = MentorAgent(llm, db);

    final result = await agent.chat('change Netflix');

    expect(result.kind, 'text');
    expect(result.content, 'General advice.');
    await db.close();
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd app && flutter test test/mentor_agent_chat_test.dart -r expanded`
Expected: the 4 new tests FAIL — `edit_subscription` isn't recognized yet.

- [ ] **Step 3: Extend `mentorIntentPrompt`**

In `app/lib/llm/prompts.dart`, add `edit_subscription` to the intent enum (no new fields needed — it reuses `merchant` as the search keyword and `amount` as the new value, both already added):

```dart
{"intent": "chat"|"query_transactions"|"delete_transaction"|"query_subscriptions"|"cancel_subscription"|"update_budget_limit"|"record_transaction"|"add_subscription"|"edit_transaction"|"edit_subscription",
```

Add a new rule after `edit_transaction`'s rule:

```
- "edit_subscription" is for requests to change an existing subscription's
  monthly amount (e.g. "change Netflix to \$18.99", "Spotify is now \$13").
  "merchant" identifies WHICH subscription (same as "cancel_subscription"),
  "amount" is the corrected monthly charge -- required, else use "chat".
```

Add one more example:

```
"change Netflix to \$18.99" -> {"intent": "edit_subscription", "category": null, "merchant": "Netflix", "monthsBack": null, "newLimit": null, "amount": 18.99, "dayOfMonth": null, "newMerchant": null}
```

- [ ] **Step 4: Extend `_parseIntent`'s recognized set and guard**

In `app/lib/llm/mentor_agent.dart`, add `'edit_subscription'` to `_parseIntent`'s `recognized` set.

Add a presence check after the `edit_transaction` check from Task 3:

```dart
    if (intent == 'edit_subscription' && json['amount'] == null) {
      return ChatIntent(intent: 'chat');
    }
```

No `ChatIntent` field changes needed — `merchant`/`amount` already exist.

- [ ] **Step 5: Add `_editSubscriptionCandidate` and wire the switch**

Add `import '../data/subscription_edit_summary.dart';` to the top of `app/lib/llm/mentor_agent.dart`.

Add one more case to `chat()`'s switch:

```dart
      case 'edit_subscription':
        return _editSubscriptionCandidate(parsed);
```

Add this method after `_editTransactionCandidate`:

```dart
  Future<MentorChatResult> _editSubscriptionCandidate(ChatIntent parsed) async {
    final rows = await db.subscriptionsDao.search(nameKeyword: parsed.merchant, limit: 5);
    final summaries = rows.map(SubscriptionSummary.fromSubscription).toList();
    if (summaries.isEmpty) {
      return MentorChatResult(content: "I couldn't find a subscription matching that.");
    }
    if (summaries.length > 1) {
      return MentorChatResult(
        content: 'Found ${summaries.length} subscriptions matching that -- can you be more specific?',
        kind: 'subscription_list',
        dataJson: encodeSubscriptionSummaries(summaries),
      );
    }
    final target = summaries.first;
    final newAmount = parsed.amount!;
    final edit = SubscriptionEditSummary(subscription: target, newAmount: newAmount);
    return MentorChatResult(
      content: 'Change ${target.name} from \$${target.amount.toStringAsFixed(2)} '
          'to \$${newAmount.toStringAsFixed(2)}?',
      kind: 'edit_subscription_confirm',
      dataJson: encodeSubscriptionEditSummary(edit),
    );
  }
```

(`parsed.amount!` is safe: `_parseIntent`'s guard in Step 4 only ever produces `intent: 'edit_subscription'` when `amount` is non-null.)

- [ ] **Step 6: Run the tests to verify they pass**

Run: `cd app && flutter test test/mentor_agent_chat_test.dart -r expanded`
Expected: all pass (44 total: 40 + 4).

- [ ] **Step 7: Run `flutter analyze`**

Run: `cd app && flutter analyze`
Expected: only the same 11 pre-existing info-level issues, nothing new.

- [ ] **Step 8: Commit**

```bash
cd app
git add lib/llm/prompts.dart lib/llm/mentor_agent.dart test/mentor_agent_chat_test.dart
git commit -m "feat: add edit_subscription intent to mentor chat"
```

---

### Task 5: Scoped "last N transactions" search + spending-insight context

**Files:**
- Modify: `app/lib/llm/prompts.dart`
- Modify: `app/lib/llm/mentor_agent.dart`
- Test: `app/test/mentor_agent_chat_test.dart`

**Interfaces:**
- Produces: `ChatIntent` gains `int? count` (meaningful only for `query_transactions`). `_generalChat`'s context gains a Dart-computed highest-spending-category line.

- [ ] **Step 1: Write the failing tests**

Append to `app/test/mentor_agent_chat_test.dart`:

```dart
  test('query_transactions with a count set returns exactly that many, total scoped to them', () async {
    final db = _db();
    for (var i = 0; i < 10; i++) {
      await db.transactionsDao.insertWithDedup(NewTransaction(
        amount: 10.0,
        currency: 'USD',
        merchant: 'Store',
        category: 'Other',
        source: 'manual',
        rawText: 'Store 10.0 #$i',
        timestamp: DateTime.now(),
      ));
    }
    final llm = _ScriptedLlm(['{"intent": "query_transactions", "count": 5}']);
    final agent = MentorAgent(llm, db);

    final result = await agent.chat('give me my last 5 transactions');

    expect(result.kind, 'transaction_list');
    final summaries = decodeTransactionSummaries(result.dataJson!);
    expect(summaries, hasLength(5));
    expect(result.content, contains('last 5'));
    expect(result.content, contains('50.00'));
    await db.close();
  });

  test('query_transactions without a count keeps the existing "Found N matching" wording', () async {
    final db = _db();
    await db.transactionsDao.insertWithDedup(NewTransaction(
      amount: 10.0,
      currency: 'USD',
      merchant: 'Store',
      category: 'Other',
      source: 'manual',
      rawText: 'Store 10.0',
      timestamp: DateTime.now(),
    ));
    final llm = _ScriptedLlm(['{"intent": "query_transactions", "merchant": "Store"}']);
    final agent = MentorAgent(llm, db);

    final result = await agent.chat('show me my Store purchases');

    expect(result.content, contains('Found 1 matching'));
    await db.close();
  });

  test('_generalChat context includes the highest-spending category, computed in Dart', () async {
    final db = _db();
    await db.budgetsDao.upsert('Groceries', 400.0, '2026-08');
    await db.budgetsDao.upsert('Travel', 400.0, '2026-08');
    await db.transactionsDao.insertWithDedup(NewTransaction(
      amount: 300.0,
      currency: 'USD',
      merchant: 'Store',
      category: 'Groceries',
      source: 'manual',
      rawText: 'Store 300.0',
      timestamp: DateTime.now(),
    ));
    await db.transactionsDao.insertWithDedup(NewTransaction(
      amount: 50.0,
      currency: 'USD',
      merchant: 'Airline',
      category: 'Travel',
      source: 'manual',
      rawText: 'Airline 50.0',
      timestamp: DateTime.now(),
    ));
    final llm = _CapturingLlm(['{"intent": "chat"}', 'Reply.']);
    final agent = MentorAgent(llm, db);

    await agent.chat('what am I spending the most on?');

    expect(llm.lastUserPrompt, contains('Highest spending category this month: Groceries'));
    await db.close();
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd app && flutter test test/mentor_agent_chat_test.dart -r expanded`
Expected: the 3 new tests FAIL — `count` isn't recognized yet, and the highest-spending-category line doesn't exist.

- [ ] **Step 3: Extend `mentorIntentPrompt`**

In `app/lib/llm/prompts.dart`, add `count` to the JSON shape line:

```dart
{"intent": "chat"|"query_transactions"|"delete_transaction"|"query_subscriptions"|"cancel_subscription"|"update_budget_limit"|"record_transaction"|"add_subscription"|"edit_transaction"|"edit_subscription",
 "category": "<one of: ${categoryCatalog.join(', ')}>"|null,
 "merchant": "<short keyword or null>", "monthsBack": <integer or null>,
 "newLimit": <number or null>, "amount": <number or null>, "dayOfMonth": <integer 1-31 or null>,
 "newMerchant": "<string or null>", "count": <integer or null>}
```

Add a new rule after the `newMerchant` field rule:

```
- "count" is how many results the user explicitly asked for (e.g. "my
  last 5 transactions" -> 5, "the last three purchases" -> 3), used only
  by "query_transactions", else null. Do not guess a count if the user
  didn't give one.
```

Add one more example:

```
"give me my last 5 transactions" -> {"intent": "query_transactions", "category": null, "merchant": null, "monthsBack": null, "count": 5}
```

- [ ] **Step 4: Add `count` to `ChatIntent`/`_parseIntent`**

In `app/lib/llm/mentor_agent.dart`, add `final int? count;` and the matching constructor parameter to `ChatIntent`.

Add `count` to `_parseIntent`'s final `return ChatIntent(...)`:

```dart
      count: (json['count'] as num?)?.toInt(),
```

(No presence-check guard needed — `count` is optional for `query_transactions`, absence just means "no explicit limit," the existing default-500 behavior.)

- [ ] **Step 5: Use `count` in `_queryTransactions`**

Change `_queryTransactions` from:

```dart
  Future<MentorChatResult> _queryTransactions(ChatIntent parsed) async {
    final rows = await db.transactionsDao.search(
      category: parsed.category,
      merchantKeyword: parsed.merchant,
      since: _sinceFromMonthsBack(parsed.monthsBack),
      limit: 500,
    );
    final summaries = rows.map(TransactionSummary.fromTransaction).toList();
    if (summaries.isEmpty) {
      return MentorChatResult(content: "I couldn't find any matching transactions.");
    }
    final total = summaries.fold<double>(0, (a, t) => a + t.amount);
    final label = parsed.merchant ?? parsed.category ?? 'transactions';
    return MentorChatResult(
      content: 'Found ${summaries.length} matching "$label", totaling \$${total.toStringAsFixed(2)}.',
      kind: 'transaction_list',
      dataJson: encodeTransactionSummaries(summaries.take(20).toList()),
    );
  }
```

to:

```dart
  Future<MentorChatResult> _queryTransactions(ChatIntent parsed) async {
    final effectiveLimit = parsed.count != null ? parsed.count!.clamp(1, 50) : 500;
    final rows = await db.transactionsDao.search(
      category: parsed.category,
      merchantKeyword: parsed.merchant,
      since: _sinceFromMonthsBack(parsed.monthsBack),
      limit: effectiveLimit,
    );
    final summaries = rows.map(TransactionSummary.fromTransaction).toList();
    if (summaries.isEmpty) {
      return MentorChatResult(content: "I couldn't find any matching transactions.");
    }
    final total = summaries.fold<double>(0, (a, t) => a + t.amount);
    if (parsed.count != null) {
      return MentorChatResult(
        content: 'Here are your last ${summaries.length} transactions, totaling \$${total.toStringAsFixed(2)}.',
        kind: 'transaction_list',
        dataJson: encodeTransactionSummaries(summaries),
      );
    }
    final label = parsed.merchant ?? parsed.category ?? 'transactions';
    return MentorChatResult(
      content: 'Found ${summaries.length} matching "$label", totaling \$${total.toStringAsFixed(2)}.',
      kind: 'transaction_list',
      dataJson: encodeTransactionSummaries(summaries.take(20).toList()),
    );
  }
```

- [ ] **Step 6: Add the highest-spending-category line to `_generalChat`**

In `_generalChat`, change:

```dart
    final categoryLines = limits.entries
        .map((e) =>
            '- ${e.key}: \$${(spentByCategory[e.key] ?? 0).toStringAsFixed(2)} / \$${e.value.toStringAsFixed(2)}')
        .join('\n');
    final subsLines = subs.isEmpty
        ? 'No subscriptions tracked.'
        : subs
            .map((s) =>
                '- ${s.name}: \$${s.amount.toStringAsFixed(2)}/${s.cycle}, renews ${s.nextChargeDate.month}/${s.nextChargeDate.day}')
            .join('\n');

    final history = await _historyBlock();
    final context = '${history}This month ($period) so far:\n'
        'Total spent: \$${totalSpent.toStringAsFixed(2)} of \$${totalLimit.toStringAsFixed(2)} budgeted\n'
        'By category:\n${categoryLines.isEmpty ? '(no budgets set)' : categoryLines}\n'
        'Active subscriptions:\n$subsLines\n\n'
        'User: $userMessage';
```

to:

```dart
    final categoryLines = limits.entries
        .map((e) =>
            '- ${e.key}: \$${(spentByCategory[e.key] ?? 0).toStringAsFixed(2)} / \$${e.value.toStringAsFixed(2)}')
        .join('\n');
    final subsLines = subs.isEmpty
        ? 'No subscriptions tracked.'
        : subs
            .map((s) =>
                '- ${s.name}: \$${s.amount.toStringAsFixed(2)}/${s.cycle}, renews ${s.nextChargeDate.month}/${s.nextChargeDate.day}')
            .join('\n');
    final topCategoryLine = spentByCategory.isEmpty
        ? ''
        : (() {
            final top = spentByCategory.entries.reduce((a, b) => a.value > b.value ? a : b);
            return 'Highest spending category this month: ${top.key} (\$${top.value.toStringAsFixed(2)}).\n';
          })();

    final history = await _historyBlock();
    final context = '${history}This month ($period) so far:\n'
        'Total spent: \$${totalSpent.toStringAsFixed(2)} of \$${totalLimit.toStringAsFixed(2)} budgeted\n'
        'By category:\n${categoryLines.isEmpty ? '(no budgets set)' : categoryLines}\n'
        '$topCategoryLine'
        'Active subscriptions:\n$subsLines\n\n'
        'User: $userMessage';
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `cd app && flutter test test/mentor_agent_chat_test.dart -r expanded`
Expected: all pass (47 total: 44 + 3).

- [ ] **Step 8: Run `flutter analyze`**

Run: `cd app && flutter analyze`
Expected: only the same 11 pre-existing info-level issues, nothing new.

- [ ] **Step 9: Commit**

```bash
cd app
git add lib/llm/prompts.dart lib/llm/mentor_agent.dart test/mentor_agent_chat_test.dart
git commit -m "feat: add scoped last-N transaction search and highest-spending-category context"
```

---

### Task 6: UI — three new confirm-card kinds in the chat

**Files:**
- Modify: `app/lib/features/chat/chat_screen.dart`
- Test: `app/test/chat_screen_test.dart`

**Interfaces:**
- Consumes: `NewSubscriptionSummary`, `TransactionEditSummary`, `SubscriptionEditSummary` (Task 1), and the three new `MentorChatResult.kind` values (`add_subscription_confirm`, `edit_transaction_confirm`, `edit_subscription_confirm`) produced by Tasks 2-4.

- [ ] **Step 1: Add the three getters and confirm methods to `_BubbleState`**

In `app/lib/features/chat/chat_screen.dart`, add these five imports. `SubscriptionsCompanion`/`Value` are referenced by name in Step 1's new code below but this file currently imports neither `db.dart` nor `drift/drift.dart` directly (it only reaches Drift types transitively through the summary DTOs) — both are required, not optional:

```dart
import 'package:drift/drift.dart';

import '../../data/db.dart';
import '../../data/new_subscription_summary.dart';
import '../../data/subscription_edit_summary.dart';
import '../../data/transaction_edit_summary.dart';
```

In `_BubbleState`, add these getters and methods (alongside the existing `_budgetChange`/`_confirmBudgetChange`):

```dart
  NewSubscriptionSummary? get _newSubscription =>
      widget.kind == 'add_subscription_confirm' && widget.dataJson != null
          ? decodeNewSubscriptionSummary(widget.dataJson!)
          : null;

  Future<void> _confirmAddSubscription(NewSubscriptionSummary s) async {
    await ref.read(appDatabaseProvider).subscriptionsDao.add(
          SubscriptionsCompanion.insert(
            name: s.name,
            amount: s.amount,
            cycle: const Value('monthly'),
            nextChargeDate: s.nextChargeDate,
            createdAt: DateTime.now(),
          ),
        );
    if (mounted) setState(() => _actionTaken = true);
  }

  TransactionEditSummary? get _transactionEdit =>
      widget.kind == 'edit_transaction_confirm' && widget.dataJson != null
          ? decodeTransactionEditSummary(widget.dataJson!)
          : null;

  Future<void> _confirmTransactionEdit(TransactionEditSummary edit) async {
    await ref.read(appDatabaseProvider).transactionsDao.updateFields(
          edit.transaction.id,
          amount: edit.newAmount,
          merchant: edit.newMerchant,
        );
    if (mounted) setState(() => _actionTaken = true);
  }

  SubscriptionEditSummary? get _subscriptionEdit =>
      widget.kind == 'edit_subscription_confirm' && widget.dataJson != null
          ? decodeSubscriptionEditSummary(widget.dataJson!)
          : null;

  Future<void> _confirmSubscriptionEdit(SubscriptionEditSummary edit) async {
    await ref.read(appDatabaseProvider).subscriptionsDao.update(
          edit.subscription.id,
          SubscriptionsCompanion(amount: Value(edit.newAmount)),
        );
    if (mounted) setState(() => _actionTaken = true);
  }
```

- [ ] **Step 2: Add the three rendering blocks**

In `_BubbleState.build()`'s `Column`, after the existing `_budgetChange`-driven block, add three more blocks following the exact same shape (no data-card row for any of these three — `add_subscription_confirm` could arguably show a `SubscriptionRow` preview, but the confirmation text itself already states name/amount/date, so keep this consistent with `budget_confirm`'s text-only-plus-buttons shape for all three, avoiding a partially-built preview row that duplicates the `SubscriptionSummary` shape without a real `id` yet):

```dart
                  if (_newSubscription != null) ...[
                    const SizedBox(height: 8),
                    if (!_actionTaken)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextButton(
                              onPressed: () => setState(() => _actionTaken = true),
                              style: TextButton.styleFrom(foregroundColor: AppColors.darkPrimary),
                              child: const Text('Cancel'),
                            ),
                            const SizedBox(width: 4),
                            FilledButton(
                              onPressed: () => _confirmAddSubscription(_newSubscription!),
                              child: const Text('Confirm'),
                            ),
                          ],
                        ),
                      ),
                    if (_actionTaken)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Done.',
                          style: TextStyle(color: AppColors.darkOnSurfaceVariant, fontSize: 12),
                        ),
                      ),
                  ],
                  if (_transactionEdit != null) ...[
                    const SizedBox(height: 8),
                    if (!_actionTaken)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextButton(
                              onPressed: () => setState(() => _actionTaken = true),
                              style: TextButton.styleFrom(foregroundColor: AppColors.darkPrimary),
                              child: const Text('Cancel'),
                            ),
                            const SizedBox(width: 4),
                            FilledButton(
                              onPressed: () => _confirmTransactionEdit(_transactionEdit!),
                              child: const Text('Confirm'),
                            ),
                          ],
                        ),
                      ),
                    if (_actionTaken)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Done.',
                          style: TextStyle(color: AppColors.darkOnSurfaceVariant, fontSize: 12),
                        ),
                      ),
                  ],
                  if (_subscriptionEdit != null) ...[
                    const SizedBox(height: 8),
                    if (!_actionTaken)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextButton(
                              onPressed: () => setState(() => _actionTaken = true),
                              style: TextButton.styleFrom(foregroundColor: AppColors.darkPrimary),
                              child: const Text('Cancel'),
                            ),
                            const SizedBox(width: 4),
                            FilledButton(
                              onPressed: () => _confirmSubscriptionEdit(_subscriptionEdit!),
                              child: const Text('Confirm'),
                            ),
                          ],
                        ),
                      ),
                    if (_actionTaken)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Done.',
                          style: TextStyle(color: AppColors.darkOnSurfaceVariant, fontSize: 12),
                        ),
                      ),
                  ],
```

- [ ] **Step 3: Write the failing chat screen tests**

Append to `app/test/chat_screen_test.dart` (add `import 'package:moneylock/data/new_subscription_summary.dart';`, `import 'package:moneylock/data/subscription_edit_summary.dart';`, `import 'package:moneylock/data/transaction_edit_summary.dart';`):

```dart
  testWidgets('renders an add_subscription_confirm bubble with Confirm and Cancel buttons',
      (tester) async {
    final db = _db();
    final message = _msg(
      id: 1,
      kind: 'add_subscription_confirm',
      content: 'Add Netflix at \$30.00/month, starting Sep 20?',
      dataJson: encodeNewSubscriptionSummary(NewSubscriptionSummary(
        name: 'Netflix',
        amount: 30.0,
        nextChargeDate: DateTime(2026, 9, 20),
      )),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          messagesStreamProvider.overrideWith((ref) => Stream.value([message])),
        ],
        child: const MaterialApp(home: ChatScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Confirm'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.runAsync(() => db.close());
  });

  testWidgets('renders an edit_transaction_confirm bubble with Confirm and Cancel buttons',
      (tester) async {
    final db = _db();
    final message = _msg(
      id: 1,
      kind: 'edit_transaction_confirm',
      content: "Change this transaction's amount from \$45.00 to \$50.00?",
      dataJson: encodeTransactionEditSummary(TransactionEditSummary(
        transaction: TransactionSummary(
          id: 1,
          merchant: 'Nike Store',
          amount: 45.0,
          category: 'Shopping & E-commerce',
          timestamp: DateTime(2026, 8, 1),
        ),
        newAmount: 50.0,
      )),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          messagesStreamProvider.overrideWith((ref) => Stream.value([message])),
        ],
        child: const MaterialApp(home: ChatScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Confirm'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.runAsync(() => db.close());
  });

  testWidgets('renders an edit_subscription_confirm bubble with Confirm and Cancel buttons',
      (tester) async {
    final db = _db();
    final message = _msg(
      id: 1,
      kind: 'edit_subscription_confirm',
      content: 'Change Netflix from \$15.99 to \$18.99?',
      dataJson: encodeSubscriptionEditSummary(SubscriptionEditSummary(
        subscription: SubscriptionSummary(
          id: 1,
          name: 'Netflix',
          brandKey: 'netflix',
          amount: 15.99,
          currency: 'USD',
          cycle: 'monthly',
          nextChargeDate: DateTime(2026, 9, 1),
        ),
        newAmount: 18.99,
      )),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          messagesStreamProvider.overrideWith((ref) => Stream.value([message])),
        ],
        child: const MaterialApp(home: ChatScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Confirm'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.runAsync(() => db.close());
  });
```

Do not run this file — it is a known, pre-existing, unrelated `driftDatabase()`-under-`pumpAndSettle()` hang, extensively documented in this codebase's test history. Confirm correctness via `flutter analyze` and careful reading instead.

- [ ] **Step 4: Run `flutter analyze`**

Run: `cd app && flutter analyze`
Expected: only the same 11 pre-existing info-level issues, nothing new.

- [ ] **Step 5: Run the non-hanging tests touched by this task**

Run: `cd app && flutter test test/mentor_agent_chat_test.dart -r expanded`
Expected: 47/47 pass (unaffected by this task, sanity check only).

- [ ] **Step 6: Commit**

```bash
cd app
git add lib/features/chat/chat_screen.dart test/chat_screen_test.dart
git commit -m "feat: render add-subscription and edit confirm cards in mentor chat"
```
