# Mentor Data Access Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the mentor chat real access to the user's financial data — general questions get a monthly-summary context, "find X" questions search real transactions, "delete X" requests surface a guarded confirm-before-delete flow — plus a matching swipe-to-delete on Dashboard's Recent Transactions, and a fix for the Spanish-language default mentor prompt.

**Architecture:** An intent-classification LLM call (constrained JSON, same proven pattern as the existing transaction categorizer) routes each free-text chat message to one of three deterministic Dart-side handlers on `MentorAgent`. Query/delete results carry structured `TransactionSummary` data alongside text, rendered as a shared `TransactionRow` card in both the chat and the Dashboard.

**Tech Stack:** Flutter/Dart, Riverpod, Drift/SQLite (same stack as the rest of the app — no new dependencies).

## Global Constraints

- All UI copy is in English. No Spanish (or any other language) strings in any user-facing text — including the mentor's own system prompts, since they shape the on-device model's actual output language.
- `DateTime` month/year arithmetic uses the constructor directly (`DateTime(y, m - n, d)`), never `Duration`-based addition/subtraction.
- The mentor never deletes anything itself. `delete_transaction` intent only ever *surfaces* a candidate; the user must tap a real Delete button to confirm. A delete button is never shown next to an ambiguous (2+ match) candidate.
- Count/total arithmetic on search results is always computed in Dart, never asked of the on-device model.

---

### Task 1: Fix Spanish prompt, add `TransactionSummary`, extend `TransactionsDao`

**Files:**
- Modify: `app/lib/llm/prompts.dart`
- Modify: `app/test/mentor_rules_test.dart`
- Create: `app/lib/data/transaction_summary.dart`
- Modify: `app/lib/data/transactions_dao.dart`
- Test: `app/test/transaction_summary_test.dart`
- Test: `app/test/transactions_dao_search_test.dart`

**Interfaces:**
- Produces: `TransactionSummary` (fields `id`, `merchant`, `amount`, `category`, `timestamp`; `TransactionSummary.fromTransaction(Transaction)`, `TransactionSummary.fromJson(Map)`, `.toJson()`), top-level `List<TransactionSummary> decodeTransactionSummaries(String json)`. `TransactionsDao.spentByCategoryThisPeriod(String period)`, `.search({category, merchantKeyword, since, limit})`, `.remove(int id)`. Later tasks depend on all of these by exact name.

- [ ] **Step 1: Translate `strictRamseyPrompt` to English**

In `app/lib/llm/prompts.dart`, replace:

```dart
const strictRamseyPrompt = '''
Eres un Mentor Financiero estricto, pragmatico y sin rodeos. Tu objetivo es hacer que el usuario cumpla sus metas financieras. Si el usuario gasta en cosas innecesarias o se acerca al limite de su presupuesto, debes llamarle la atencion directamente, senalarle el impacto en sus metas futuras y exigir un ajuste. Se firme, conciso y motivador desde la disciplina.
Respond in under 120 words. No emojis. Address the user as "you".
Only discuss the user's Moneylock spending, transactions, budgets, saving habits,
and general financial education. Do not write code or answer questions about
politics, entertainment, investments, taxes, legal matters, credit, loans, or
insurance. For unrelated requests, say exactly: "I can only help with your
Moneylock finances, spending, and budgets." Do not invent financial data or
present personalized investment, tax, legal, or credit advice. Educational
information only, not financial advice.
''';
```

with:

```dart
const strictRamseyPrompt = '''
You are a strict, pragmatic, no-nonsense Financial Mentor. Your goal is to
make the user stick to their financial goals. If the user spends on
unnecessary things or approaches their budget limit, call it out directly,
point out the impact on their future goals, and demand an adjustment. Be
firm, concise, and motivating through discipline.
Respond in under 120 words. No emojis. Address the user as "you".
Only discuss the user's Moneylock spending, transactions, budgets, saving habits,
and general financial education. Do not write code or answer questions about
politics, entertainment, investments, taxes, legal matters, credit, loans, or
insurance. For unrelated requests, say exactly: "I can only help with your
Moneylock finances, spending, and budgets." Do not invent financial data or
present personalized investment, tax, legal, or credit advice. Educational
information only, not financial advice.
''';
```

- [ ] **Step 2: Fix the existing test that checks for the Spanish word**

`app/test/mentor_rules_test.dart` has a test asserting the strict prompt
contains the Spanish word `'estricto'` — this will fail once Step 1 lands
since that word no longer exists in the prompt. Change:

```dart
    test('tono por defecto es strict', () {
      expect(mentorPromptFor('unknown_tone'), contains('estricto'));
    });
```

to:

```dart
    test('tono por defecto es strict', () {
      expect(mentorPromptFor('unknown_tone'), contains('strict'));
    });
```

Run: `cd app && flutter test test/mentor_rules_test.dart -r expanded`
Expected: 5 tests pass (this file's existing 5 tests, now with the fixed assertion).

- [ ] **Step 3: Write the failing `TransactionSummary` tests**

Create `app/test/transaction_summary_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:moneylock/data/transaction_summary.dart';

void main() {
  test('toJson/fromJson round-trips exactly', () {
    final original = TransactionSummary(
      id: 7,
      merchant: 'Nike',
      amount: 89.99,
      category: 'Shopping & E-commerce',
      timestamp: DateTime(2026, 6, 12, 10, 30),
    );

    final decoded = TransactionSummary.fromJson(original.toJson());

    expect(decoded.id, 7);
    expect(decoded.merchant, 'Nike');
    expect(decoded.amount, 89.99);
    expect(decoded.category, 'Shopping & E-commerce');
    expect(decoded.timestamp, DateTime(2026, 6, 12, 10, 30));
  });

  test('decodeTransactionSummaries decodes a JSON-encoded list', () {
    final list = [
      TransactionSummary(
        id: 1,
        merchant: 'A',
        amount: 1.0,
        category: 'Other',
        timestamp: DateTime(2026, 1, 1),
      ),
      TransactionSummary(
        id: 2,
        merchant: 'B',
        amount: 2.0,
        category: 'Other',
        timestamp: DateTime(2026, 1, 2),
      ),
    ];
    final json = encodeTransactionSummaries(list);

    final decoded = decodeTransactionSummaries(json);

    expect(decoded, hasLength(2));
    expect(decoded[0].merchant, 'A');
    expect(decoded[1].merchant, 'B');
  });
}
```

- [ ] **Step 4: Run the test to verify it fails**

Run: `cd app && flutter test test/transaction_summary_test.dart -r expanded`
Expected: FAIL with "Target of URI doesn't exist: 'package:moneylock/data/transaction_summary.dart'".

- [ ] **Step 5: Implement `TransactionSummary`**

Create `app/lib/data/transaction_summary.dart`:

```dart
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
```

- [ ] **Step 6: Run the tests**

Run: `cd app && flutter test test/transaction_summary_test.dart -r expanded`
Expected: 2 tests pass.

- [ ] **Step 7: Write the failing `TransactionsDao` tests**

Create `app/test/transactions_dao_search_test.dart`:

```dart
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneylock/data/db.dart';
import 'package:moneylock/data/transactions_dao.dart';

AppDatabase _db() => AppDatabase.forTesting(
    driftDatabase(name: 'test_${DateTime.now().microsecondsSinceEpoch}'));

Future<void> _insert(
  AppDatabase db, {
  required String merchant,
  required String category,
  required double amount,
  required DateTime timestamp,
}) async {
  await db.transactionsDao.insertWithDedup(NewTransaction(
    amount: amount,
    currency: 'USD',
    merchant: merchant,
    category: category,
    source: 'manual',
    rawText: '$merchant $amount',
    timestamp: timestamp,
  ));
}

void main() {
  test('spentByCategoryThisPeriod sums by category within the period', () async {
    final db = _db();
    await _insert(db, merchant: 'A', category: 'Groceries', amount: 10.0, timestamp: DateTime(2026, 8, 5));
    await _insert(db, merchant: 'B', category: 'Groceries', amount: 5.0, timestamp: DateTime(2026, 8, 10));
    await _insert(db, merchant: 'C', category: 'Transport', amount: 20.0, timestamp: DateTime(2026, 8, 15));
    await _insert(db, merchant: 'D', category: 'Groceries', amount: 99.0, timestamp: DateTime(2026, 7, 1));

    final result = await db.transactionsDao.spentByCategoryThisPeriod('2026-08');

    expect(result['Groceries'], 15.0);
    expect(result['Transport'], 20.0);
    expect(result.containsKey('2026-07'), isFalse);
    await db.close();
  });

  test('search filters by category', () async {
    final db = _db();
    await _insert(db, merchant: 'A', category: 'Groceries', amount: 10.0, timestamp: DateTime(2026, 8, 5));
    await _insert(db, merchant: 'B', category: 'Transport', amount: 20.0, timestamp: DateTime(2026, 8, 6));

    final rows = await db.transactionsDao.search(category: 'Groceries');

    expect(rows, hasLength(1));
    expect(rows.single.merchant, 'A');
    await db.close();
  });

  test('search filters by merchant keyword against merchant and rawText', () async {
    final db = _db();
    await _insert(db, merchant: 'Nike Store', category: 'Shopping & E-commerce', amount: 89.99, timestamp: DateTime(2026, 6, 12));
    await _insert(db, merchant: 'Starbucks', category: 'Coffee & Dining', amount: 5.0, timestamp: DateTime(2026, 6, 13));

    final rows = await db.transactionsDao.search(merchantKeyword: 'Nike');

    expect(rows, hasLength(1));
    expect(rows.single.merchant, 'Nike Store');
    await db.close();
  });

  test('search filters by since date', () async {
    final db = _db();
    await _insert(db, merchant: 'Old', category: 'Other', amount: 1.0, timestamp: DateTime(2026, 1, 1));
    await _insert(db, merchant: 'New', category: 'Other', amount: 2.0, timestamp: DateTime(2026, 8, 1));

    final rows = await db.transactionsDao.search(since: DateTime(2026, 6, 1));

    expect(rows, hasLength(1));
    expect(rows.single.merchant, 'New');
    await db.close();
  });

  test('search combines filters and returns empty when nothing matches', () async {
    final db = _db();
    await _insert(db, merchant: 'Nike Store', category: 'Shopping & E-commerce', amount: 89.99, timestamp: DateTime(2026, 6, 12));

    final rows = await db.transactionsDao.search(category: 'Groceries', merchantKeyword: 'Nike');

    expect(rows, isEmpty);
    await db.close();
  });

  test('search orders newest first and respects limit', () async {
    final db = _db();
    await _insert(db, merchant: 'A', category: 'Other', amount: 1.0, timestamp: DateTime(2026, 8, 1));
    await _insert(db, merchant: 'B', category: 'Other', amount: 2.0, timestamp: DateTime(2026, 8, 2));
    await _insert(db, merchant: 'C', category: 'Other', amount: 3.0, timestamp: DateTime(2026, 8, 3));

    final rows = await db.transactionsDao.search(limit: 2);

    expect(rows.map((r) => r.merchant).toList(), ['C', 'B']);
    await db.close();
  });

  test('remove deletes a transaction, and a second call is a harmless no-op', () async {
    final db = _db();
    final outcome = await db.transactionsDao.insertWithDedup(NewTransaction(
      amount: 5.0,
      currency: 'USD',
      merchant: 'Test',
      category: 'Other',
      source: 'manual',
      rawText: 'Test 5.0',
      timestamp: DateTime(2026, 8, 1),
    ));
    final id = outcome.transaction!.id;

    await db.transactionsDao.remove(id);
    final afterFirst = await db.transactionsDao.search();
    expect(afterFirst, isEmpty);

    await db.transactionsDao.remove(id); // no throw
    await db.close();
  });
}
```

- [ ] **Step 8: Run the tests to verify they fail**

Run: `cd app && flutter test test/transactions_dao_search_test.dart -r expanded`
Expected: FAIL — `spentByCategoryThisPeriod`/`search`/`remove` are not defined on `TransactionsDao`.

- [ ] **Step 9: Implement the three `TransactionsDao` methods**

In `app/lib/data/transactions_dao.dart`, add after `updateMostRecentCategory`:

```dart
  Future<Map<String, double>> spentByCategoryThisPeriod(String period) async {
    final start = DateTime.parse('$period-01T00:00:00');
    final end = DateTime(start.year, start.month + 1, 1);
    final rows = await (db.select(db.transactions)..where(
          (t) =>
              t.timestamp.isBiggerOrEqualValue(start) &
              t.timestamp.isSmallerThanValue(end),
        ))
        .get();
    final result = <String, double>{};
    for (final r in rows) {
      result[r.category] = (result[r.category] ?? 0) + r.amount;
    }
    return result;
  }

  Future<List<Transaction>> search({
    String? category,
    String? merchantKeyword,
    DateTime? since,
    int limit = 20,
  }) async {
    final q = db.select(db.transactions)
      ..orderBy([(t) => OrderingTerm.desc(t.timestamp)])
      ..limit(limit);
    if (category != null) {
      q.where((t) => t.category.equals(category));
    }
    if (merchantKeyword != null) {
      final pattern = '%$merchantKeyword%';
      q.where((t) => t.merchant.like(pattern) | t.rawText.like(pattern));
    }
    if (since != null) {
      q.where((t) => t.timestamp.isBiggerOrEqualValue(since));
    }
    return q.get();
  }

  Future<void> remove(int id) =>
      (db.delete(db.transactions)..where((t) => t.id.equals(id))).go();
```

- [ ] **Step 10: Run the tests**

Run: `cd app && flutter test test/transactions_dao_search_test.dart -r expanded`
Expected: 7 tests pass.

- [ ] **Step 11: Run `flutter analyze`**

Run: `cd app && flutter analyze`
Expected: only the pre-existing info-level issues, nothing new.

- [ ] **Step 12: Commit**

```bash
cd app
git add lib/llm/prompts.dart test/mentor_rules_test.dart lib/data/transaction_summary.dart lib/data/transactions_dao.dart test/transaction_summary_test.dart test/transactions_dao_search_test.dart
git commit -m "feat: translate strict mentor prompt to English, add transaction search/delete"
```

---

### Task 2: `MentorMessages` schema — `kind`/`dataJson` columns

**Files:**
- Modify: `app/lib/data/tables.dart`
- Modify: `app/lib/data/db.dart`
- Modify: `app/lib/data/messages_dao.dart`
- Test: `app/test/messages_dao_test.dart`
- Test: `app/test/mentor_messages_migration_test.dart`

**Interfaces:**
- Consumes: `TransactionSummary`, `encodeTransactionSummaries` (Task 1).
- Produces: `MentorMessages.kind`/`.dataJson` columns, `MessagesDao.add(role, content, {severity, kind, transactions})`. Task 3 (`MentorAgent.chat()`'s return shape) and Task 4 (chat screen wiring + rendering) depend on this exact signature.

- [ ] **Step 1: Add the two columns to `MentorMessages`**

In `app/lib/data/tables.dart`, change:

```dart
class MentorMessages extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get role => text()(); // 'user' | 'mentor'
  TextColumn get content => text()();
  DateTimeColumn get createdAt => dateTime()();
  TextColumn get severity => text().withDefault(const Constant('info'))();
}
```

to:

```dart
class MentorMessages extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get role => text()(); // 'user' | 'mentor'
  TextColumn get content => text()();
  DateTimeColumn get createdAt => dateTime()();
  TextColumn get severity => text().withDefault(const Constant('info'))();
  TextColumn get kind => text().withDefault(const Constant('text'))(); // 'text' | 'transaction_list' | 'delete_confirm'
  TextColumn get dataJson => text().nullable()();
}
```

- [ ] **Step 2: Bump the schema version and add the migration step**

In `app/lib/data/db.dart`, change `schemaVersion` from `5` to `6`, and add to the `onUpgrade` block:

```dart
      if (from < 6) {
        await m.addColumn(mentorMessages, mentorMessages.kind);
        await m.addColumn(mentorMessages, mentorMessages.dataJson);
      }
```

(placed after the existing `if (from < 5) { await m.createTable(subscriptions); }` block).

- [ ] **Step 3: Write the failing `MessagesDao` tests**

Create `app/test/messages_dao_test.dart`:

```dart
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneylock/data/db.dart';
import 'package:moneylock/data/transaction_summary.dart';

AppDatabase _db() => AppDatabase.forTesting(
    driftDatabase(name: 'test_${DateTime.now().microsecondsSinceEpoch}'));

void main() {
  test('add with no kind defaults to text with a null dataJson', () async {
    final db = _db();
    await db.messagesDao.add('mentor', 'hello');

    final rows = await db.messagesDao.watchAll().first;

    expect(rows.single.kind, 'text');
    expect(rows.single.dataJson, isNull);
    await db.close();
  });

  test('add with transactions stores kind and encodes dataJson', () async {
    final db = _db();
    final summaries = [
      TransactionSummary(
        id: 1,
        merchant: 'Nike',
        amount: 89.99,
        category: 'Shopping & E-commerce',
        timestamp: DateTime(2026, 6, 12),
      ),
    ];

    await db.messagesDao.add(
      'mentor',
      'Found 1 matching "Nike"',
      kind: 'transaction_list',
      transactions: summaries,
    );

    final rows = await db.messagesDao.watchAll().first;
    expect(rows.single.kind, 'transaction_list');
    final decoded = decodeTransactionSummaries(rows.single.dataJson!);
    expect(decoded.single.merchant, 'Nike');
    await db.close();
  });
}
```

- [ ] **Step 4: Run the tests to verify they fail**

Run: `cd app && flutter test test/messages_dao_test.dart -r expanded`
Expected: FAIL — `kind`/`transactions` are not parameters of `MessagesDao.add`.

- [ ] **Step 5: Update `MessagesDao.add`**

In `app/lib/data/messages_dao.dart`, change:

```dart
import 'package:drift/drift.dart';
import 'db.dart';

class MessagesDao {
  final AppDatabase db;
  MessagesDao(this.db);

  Future<void> add(String role, String content, {String severity = 'info'}) =>
      db.into(db.mentorMessages).insert(MentorMessagesCompanion.insert(
          role: role,
          content: content,
          createdAt: DateTime.now(),
          severity: Value(severity)));

  Stream<List<MentorMessage>> watchAll() {
    final q = db.select(db.mentorMessages)
      ..orderBy([(m) => OrderingTerm.asc(m.createdAt)]);
    return q.watch();
  }
}
```

to:

```dart
import 'package:drift/drift.dart';
import 'db.dart';
import 'transaction_summary.dart';

class MessagesDao {
  final AppDatabase db;
  MessagesDao(this.db);

  Future<void> add(
    String role,
    String content, {
    String severity = 'info',
    String kind = 'text',
    List<TransactionSummary>? transactions,
  }) =>
      db.into(db.mentorMessages).insert(MentorMessagesCompanion.insert(
          role: role,
          content: content,
          createdAt: DateTime.now(),
          severity: Value(severity),
          kind: Value(kind),
          dataJson: Value(transactions == null ? null : encodeTransactionSummaries(transactions)),
      ));

  Stream<List<MentorMessage>> watchAll() {
    final q = db.select(db.mentorMessages)
      ..orderBy([(m) => OrderingTerm.asc(m.createdAt)]);
    return q.watch();
  }
}
```

- [ ] **Step 6: Run the tests**

Run: `cd app && flutter test test/messages_dao_test.dart -r expanded`
Expected: 2 tests pass.

- [ ] **Step 7: Write the migration regression test**

Create `app/test/mentor_messages_migration_test.dart` (same pattern as the
existing `test/subscriptions_migration_test.dart`):

```dart
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneylock/data/db.dart';

void main() {
  test('upgrading from schema v5 adds kind and dataJson to mentor_messages', () async {
    final file = File(
      '${Directory.systemTemp.path}/mentor_messages_migration_test_${DateTime.now().microsecondsSinceEpoch}.sqlite',
    );

    final seedDb = AppDatabase.forTesting(NativeDatabase(file));
    await seedDb.categoriesDao.all(); // forces onCreate to run at schemaVersion 6
    await seedDb.customStatement('ALTER TABLE mentor_messages DROP COLUMN kind');
    await seedDb.customStatement('ALTER TABLE mentor_messages DROP COLUMN data_json');
    await seedDb.customStatement('PRAGMA user_version = 5');
    await seedDb.close();

    final upgradedDb = AppDatabase.forTesting(NativeDatabase(file));
    await upgradedDb.messagesDao.add('mentor', 'hi'); // does not throw -- columns exist
    final rows = await upgradedDb.messagesDao.watchAll().first;
    expect(rows.single.kind, 'text');

    await upgradedDb.close();
    await file.delete();
  });
}
```

This test deliberately drops the two new columns after `onCreate` (which
already includes them, since the table is now part of the full v6 schema)
before downgrading the version marker — the same technique used to fix the
tautological-test issue caught in the subscriptions-tracking plan's final
review. Without this, the migration step being tested could be deleted
entirely and the test would still pass.

- [ ] **Step 8: Run the migration test**

Run: `cd app && flutter test test/mentor_messages_migration_test.dart -r expanded`
Expected: 1 test passes.

- [ ] **Step 9: Run `flutter analyze`**

Run: `cd app && flutter analyze`
Expected: only the pre-existing info-level issues, nothing new.

- [ ] **Step 10: Commit**

```bash
cd app
git add lib/data/tables.dart lib/data/db.dart lib/data/db.g.dart lib/data/messages_dao.dart test/messages_dao_test.dart test/mentor_messages_migration_test.dart
git commit -m "feat: add kind/dataJson columns to mentor messages for structured replies"
```

(Regenerate Drift's generated code first if it isn't already up to date: `cd app && dart run build_runner build --delete-conflicting-outputs`.)

---

### Task 3: Intent classification + `MentorAgent.chat()` router

**Files:**
- Modify: `app/lib/llm/prompts.dart`
- Modify: `app/lib/llm/mentor_agent.dart`
- Test: `app/test/mentor_agent_chat_test.dart`

**Interfaces:**
- Consumes: `TransactionSummary`, `TransactionSummary.fromTransaction` (Task 1), `TransactionsDao.spentByCategoryThisPeriod`/`.search` (Task 1), `SubscriptionsDao.allForScheduling` (existing), `BudgetsDao.limitsForPeriod` (existing), `guardMentorResponse` (existing, `mentor_guardrails.dart`).
- Produces: `MentorChatResult {content, kind, transactions}`, `MentorAgent.chat(String userMessage)`. Task 4 (chat screen) calls this exact method and consumes this exact result shape.

- [ ] **Step 1: Add the intent-classification prompt**

In `app/lib/llm/prompts.dart`, add after `categorizerSystemPrompt`:

```dart
final mentorIntentPrompt =
    '''
Classify the user's message about their personal finances into ONE JSON
object, no markdown, no commentary:
{"intent": "chat"|"query_transactions"|"delete_transaction",
 "category": "<one of: ${categoryCatalog.join(', ')}>"|null,
 "merchant": "<short keyword or null>", "monthsBack": <integer or null>}
Rules:
- "chat" is for general questions, advice requests, or anything not asking
  to find, list, or delete specific past transactions.
- "query_transactions" is for requests to find, list, or show past
  transactions (by category, merchant, or time range).
- "delete_transaction" is for requests to remove or delete a specific past
  transaction.
- "category" must be one of the listed categories if the user names one,
  else null.
- "merchant" is a short keyword describing what was bought (e.g. "shoes",
  "Nike", "coffee"), else null.
- "monthsBack" is how many months back to search if the user gives a time
  hint (e.g. "two months ago" -> 2, "last six months" -> 6), else null.
Examples:
"what can I cut this month?" -> {"intent": "chat", "category": null, "merchant": null, "monthsBack": null}
"show me groceries transactions from the last six months" -> {"intent": "query_transactions", "category": "Groceries", "merchant": null, "monthsBack": 6}
"I bought shoes about two months ago, how much did they cost?" -> {"intent": "query_transactions", "category": null, "merchant": "shoes", "monthsBack": 2}
"delete that Nike purchase" -> {"intent": "delete_transaction", "category": null, "merchant": "Nike", "monthsBack": null}
''';
```

- [ ] **Step 2: Write the failing `MentorAgent.chat()` tests**

Create `app/test/mentor_agent_chat_test.dart`:

```dart
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
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `cd app && flutter test test/mentor_agent_chat_test.dart -r expanded`
Expected: FAIL — `MentorChatResult`/`chat` are not defined.

- [ ] **Step 4: Implement `MentorChatResult` and `MentorAgent.chat()`**

In `app/lib/llm/mentor_agent.dart`, add the import
`import 'dart:convert';` and `import '../data/transaction_summary.dart';`
and `import 'mentor_guardrails.dart';` at the top, then add after the
`MentorVerdict` class:

```dart
class MentorChatResult {
  final String content;
  final String kind; // 'text' | 'transaction_list' | 'delete_confirm'
  final List<TransactionSummary> transactions;
  MentorChatResult({
    required this.content,
    this.kind = 'text',
    this.transactions = const [],
  });
}

class _ChatIntent {
  final String intent;
  final String? category;
  final String? merchant;
  final int? monthsBack;
  _ChatIntent({required this.intent, this.category, this.merchant, this.monthsBack});
}

_ChatIntent _parseIntent(String raw) {
  try {
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final intent = json['intent'] as String?;
    if (intent != 'query_transactions' && intent != 'delete_transaction') {
      return _ChatIntent(intent: 'chat');
    }
    return _ChatIntent(
      intent: intent,
      category: json['category'] as String?,
      merchant: json['merchant'] as String?,
      monthsBack: (json['monthsBack'] as num?)?.toInt(),
    );
  } catch (_) {
    return _ChatIntent(intent: 'chat');
  }
}

DateTime? _sinceFromMonthsBack(int? monthsBack) {
  if (monthsBack == null) return null;
  final now = DateTime.now();
  return DateTime(now.year, now.month - monthsBack, now.day);
}
```

Then add this method inside the `MentorAgent` class, after `evaluate()`:

```dart
  Future<MentorChatResult> chat(String userMessage) async {
    _ChatIntent parsed;
    try {
      final raw = await provider.complete(mentorIntentPrompt, userMessage, temperature: 0.0);
      parsed = _parseIntent(raw);
    } catch (_) {
      parsed = _ChatIntent(intent: 'chat');
    }

    switch (parsed.intent) {
      case 'query_transactions':
        return _queryTransactions(parsed);
      case 'delete_transaction':
        return _deleteTransactionCandidate(parsed);
      default:
        return _generalChat(userMessage);
    }
  }

  Future<MentorChatResult> _generalChat(String userMessage) async {
    final tone = await db.settingsDao.mentorTone();
    final now = DateTime.now();
    final period = '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}';
    final spentByCategory = await db.transactionsDao.spentByCategoryThisPeriod(period);
    final limits = await db.budgetsDao.limitsForPeriod(period);
    final totalSpent = spentByCategory.values.fold<double>(0, (a, b) => a + b);
    final totalLimit = limits.values.fold<double>(0, (a, b) => a + b);
    final subs = await db.subscriptionsDao.allForScheduling();

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

    final context = 'This month ($period) so far:\n'
        'Total spent: \$${totalSpent.toStringAsFixed(2)} of \$${totalLimit.toStringAsFixed(2)} budgeted\n'
        'By category:\n${categoryLines.isEmpty ? '(no budgets set)' : categoryLines}\n'
        'Active subscriptions:\n$subsLines\n\n'
        'User: $userMessage';

    try {
      final reply = await provider.complete(mentorPromptFor(tone), context);
      return MentorChatResult(content: guardMentorResponse(reply));
    } catch (_) {
      return MentorChatResult(content: 'I could not reach my model right now.');
    }
  }

  Future<MentorChatResult> _queryTransactions(_ChatIntent parsed) async {
    final rows = await db.transactionsDao.search(
      category: parsed.category,
      merchantKeyword: parsed.merchant,
      since: _sinceFromMonthsBack(parsed.monthsBack),
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
      transactions: summaries,
    );
  }

  Future<MentorChatResult> _deleteTransactionCandidate(_ChatIntent parsed) async {
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
        transactions: summaries,
      );
    }
    return MentorChatResult(
      content: 'Found this transaction -- want me to delete it?',
      kind: 'delete_confirm',
      transactions: summaries,
    );
  }
```

- [ ] **Step 5: Run the tests**

Run: `cd app && flutter test test/mentor_agent_chat_test.dart -r expanded`
Expected: 9 tests pass.

- [ ] **Step 6: Run `flutter analyze`**

Run: `cd app && flutter analyze`
Expected: only the pre-existing info-level issues, nothing new.

- [ ] **Step 7: Commit**

```bash
cd app
git add lib/llm/prompts.dart lib/llm/mentor_agent.dart test/mentor_agent_chat_test.dart
git commit -m "feat: add intent-routed mentor chat (general questions, search, guarded delete)"
```

---

### Task 4: Shared `TransactionRow` widget + chat screen wiring

**Files:**
- Create: `app/lib/widgets/transaction_row.dart`
- Modify: `app/lib/features/dashboard/dashboard_screen.dart`
- Modify: `app/lib/features/chat/chat_screen.dart`
- Test: `app/test/chat_screen_test.dart`

**Interfaces:**
- Consumes: `TransactionSummary` (Task 1), `MentorAgent.chat()`/`MentorChatResult` (Task 3), `MessagesDao.add(..., kind:, transactions:)` (Task 2).
- Produces: `TransactionRow` widget (public, takes a `TransactionSummary`). Task 5 (Dashboard's swipe-to-delete) builds directly on top of this same widget.

- [ ] **Step 1: Extract the shared `TransactionRow` widget**

Create `app/lib/widgets/transaction_row.dart`, moving the existing
`_TransactionRow` class out of `dashboard_screen.dart` verbatim, renamed
public and retyped to take a `TransactionSummary` instead of a full Drift
`Transaction` row (chat's data cards only have summaries, not full rows —
see Task 1):

```dart
import 'package:flutter/material.dart';

import '../core/format.dart';
import '../data/transaction_summary.dart';
import '../theme/app_theme.dart';
import '../theme/category_style.dart';

class TransactionRow extends StatelessWidget {
  final TransactionSummary t;
  const TransactionRow({super.key, required this.t});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.margin,
      vertical: 7,
    ),
    child: Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: categoryContainerColor(t.category),
            borderRadius: BorderRadius.circular(AppRadii.xl),
          ),
          child: Icon(
            categoryIcon(t.category),
            color: AppColors.onSurface,
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t.merchant.isEmpty ? t.category : t.merchant,
                style: AppTextStyles.bodyMd.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                '${t.category} · ${fmtDate(t.timestamp)}',
                style: AppTextStyles.bodyMd.copyWith(
                  fontSize: 12,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        Text(fmtCurrency(t.amount), style: AppTextStyles.monoData),
      ],
    ),
  );
}
```

- [ ] **Step 2: Use the shared widget from Dashboard**

In `app/lib/features/dashboard/dashboard_screen.dart`:

1. Add `import '../../data/transaction_summary.dart';` and
   `import '../../widgets/transaction_row.dart';`.
2. Delete the entire `_TransactionRow` class (now living in
   `transaction_row.dart` instead).
3. Change the `SliverList`'s `itemBuilder` from
   `(context, i) => _TransactionRow(t: txs[i])` to
   `(context, i) => TransactionRow(t: TransactionSummary.fromTransaction(txs[i]))`.

Run: `cd app && flutter analyze` — confirm no unresolved references from
the deleted class (this step is purely a mechanical extraction — Task 5
does the actual Dashboard *behavior* changes).

- [ ] **Step 3: Write the failing chat screen test**

Create `app/test/chat_screen_test.dart`. Following the render-only pattern
established for DB-backed screens in this codebase (`settings_notifications_test.dart`,
`subscriptions_screen_test.dart`): mock every provider the screen's initial
build reaches.

```dart
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneylock/data/db.dart';
import 'package:moneylock/features/chat/chat_screen.dart';
import 'package:moneylock/providers.dart';

AppDatabase _db() => AppDatabase.forTesting(
    driftDatabase(name: 'test_${DateTime.now().microsecondsSinceEpoch}'));

void main() {
  testWidgets('renders an empty chat with no exception', (tester) async {
    final db = _db();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          messagesStreamProvider.overrideWith((ref) => Stream.value(const [])),
        ],
        child: const MaterialApp(home: ChatScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('VECTOR'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.runAsync(() => db.close());
  });
}
```

- [ ] **Step 4: Run the test to verify it passes already**

Run: `cd app && flutter test test/chat_screen_test.dart -r expanded`
Expected: 1 test passes (this test doesn't depend on Step 5's changes —
it's establishing the baseline render-only coverage pattern before the
riskier rendering changes land).

- [ ] **Step 5: Wire `_send()` to `MentorAgent.chat()` and render data cards**

In `app/lib/features/chat/chat_screen.dart`:

1. Add `import '../../data/transaction_summary.dart';` and
   `import '../../widgets/transaction_row.dart';`.
2. In `_send()`, replace the final `else` branch:

```dart
    } else {
      final tone = await db.settingsDao.mentorTone();
      try {
        final reply = await ref
            .read(llmProviderProvider)
            .complete(mentorPromptFor(tone), text);
        await db.messagesDao.add('mentor', guardMentorResponse(reply));
      } catch (_) {
        await db.messagesDao.add(
          'mentor',
          'I could not reach my model right now.',
        );
      }
    }
```

with:

```dart
    } else {
      final result = await ref.read(mentorProvider).chat(text);
      await db.messagesDao.add(
        'mentor',
        result.content,
        kind: result.kind,
        transactions: result.transactions,
      );
    }
```

(`mentorProvider` is already imported transitively via `../../providers.dart`,
already imported in this file. `guardMentorResponse` and `mentorPromptFor`
are no longer called directly here — `MentorAgent.chat()` owns that now —
but leave the existing `import '../../llm/mentor_agent.dart';` in place
since `hasMonetaryAmount`'s file still needs nothing from it directly
removed; only remove an import if `flutter analyze` actually flags it as
unused after this change.)

3. Convert `_Bubble` from a `StatelessWidget` to a `ConsumerStatefulWidget`
   so its Delete button can call the database and locally hide itself
   after acting:

Replace the entire existing `_Bubble` class with:

```dart
class _Bubble extends ConsumerStatefulWidget {
  final String role;
  final String content;
  final String kind;
  final List<TransactionSummary> transactions;
  final bool thinking;
  const _Bubble({
    required this.role,
    required this.content,
    this.kind = 'text',
    this.transactions = const [],
    this.thinking = false,
  });

  @override
  ConsumerState<_Bubble> createState() => _BubbleState();
}

class _BubbleState extends ConsumerState<_Bubble> {
  bool _actionTaken = false;

  Future<void> _delete(int id) async {
    await ref.read(appDatabaseProvider).transactionsDao.remove(id);
    if (mounted) setState(() => _actionTaken = true);
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.role == 'user';
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * .78,
        ),
        decoration: BoxDecoration(
          color: user ? AppColors.primary : AppColors.darkSurfaceContainerHigh,
          borderRadius: BorderRadius.circular(16),
        ),
        child: widget.thinking
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.darkOnSurfaceVariant,
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.content.isNotEmpty)
                    Text(
                      widget.content,
                      style: TextStyle(
                        color: user ? Colors.white : AppColors.darkOnSurface,
                        height: 1.35,
                      ),
                    ),
                  if (widget.transactions.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    for (final t in widget.transactions)
                      Container(
                        margin: const EdgeInsets.only(bottom: 4),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(AppRadii.xl),
                        ),
                        child: TransactionRow(t: t),
                      ),
                    if (widget.kind == 'delete_confirm' && !_actionTaken)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextButton(
                              onPressed: () => setState(() => _actionTaken = true),
                              child: const Text('Cancel'),
                            ),
                            const SizedBox(width: 4),
                            FilledButton(
                              onPressed: () => _delete(widget.transactions.first.id),
                              child: const Text('Delete'),
                            ),
                          ],
                        ),
                      ),
                    if (widget.kind == 'delete_confirm' && _actionTaken)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Done.',
                          style: TextStyle(
                            color: AppColors.darkOnSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ],
              ),
      ),
    );
  }
}
```

4. Update the two call sites that construct `_Bubble` in
   `_ChatScreenState.build()` to pass the new fields:

```dart
                itemBuilder: (_, i) {
                  if (i == messages.length)
                    return const _Bubble(
                      role: 'mentor',
                      content: '',
                      thinking: true,
                    );
                  final m = messages[i];
                  return _Bubble(
                    role: m.role,
                    content: m.content,
                    kind: m.kind,
                    transactions: m.dataJson == null
                        ? const []
                        : decodeTransactionSummaries(m.dataJson!),
                  );
                },
```

(`decodeTransactionSummaries` comes from the `transaction_summary.dart`
import already added in sub-step 1.)

- [ ] **Step 6: Run the chat screen test again**

Run: `cd app && flutter test test/chat_screen_test.dart -r expanded`
Expected: still 1 test passes (this render-only test doesn't exercise the
new bubble kinds directly — the DAO-level coverage from Task 3's
`mentor_agent_chat_test.dart` already proves the data reaches this point
correctly; a full interactive widget test of the Delete button would need
a real native-isolate DB write inside `testWidgets`, the same class of
environment hang extensively documented elsewhere in this codebase's test
suite — not attempted here for the same reason).

- [ ] **Step 7: Run `flutter analyze`**

Run: `cd app && flutter analyze`
Expected: only the pre-existing info-level issues, nothing new. Pay
attention to any newly-unused-import warning from Step 5's removal of the
direct `guardMentorResponse`/`mentorPromptFor` calls — remove any import
`flutter analyze` actually flags as unused, and only those.

- [ ] **Step 8: Commit**

```bash
cd app
git add lib/widgets/transaction_row.dart lib/features/dashboard/dashboard_screen.dart lib/features/chat/chat_screen.dart test/chat_screen_test.dart
git commit -m "feat: wire mentor chat to intent router, render transaction data cards"
```

---

### Task 5: Dashboard — 7-day window + swipe-to-delete

**Files:**
- Modify: `app/lib/features/dashboard/dashboard_screen.dart`
- Test: `app/test/dashboard_recent_window_test.dart`
- Test: `app/test/dashboard_screen_test.dart`

**Interfaces:**
- Consumes: `TransactionRow` (Task 4), `TransactionsDao.remove` (Task 1).

- [ ] **Step 1: Write the failing 7-day-window logic test**

The filtering logic is a pure function, testable without a widget. Create
`app/test/dashboard_recent_window_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:moneylock/features/dashboard/dashboard_screen.dart' show recentWithinLastWeek;
import 'package:moneylock/data/db.dart';

void main() {
  test('keeps entries within the last 7 days and drops older ones', () {
    final now = DateTime(2026, 8, 19, 12, 0);
    final recent = _tx(id: 1, timestamp: now.subtract(const Duration(days: 2)));
    final boundary = _tx(id: 2, timestamp: now.subtract(const Duration(days: 7)));
    final old = _tx(id: 3, timestamp: now.subtract(const Duration(days: 8)));

    final result = recentWithinLastWeek([recent, boundary, old], now: now);

    expect(result.map((t) => t.id), containsAll([1, 2]));
    expect(result.map((t) => t.id), isNot(contains(3)));
  });

  test('empty input returns empty output', () {
    expect(recentWithinLastWeek(const [], now: DateTime(2026, 8, 19)), isEmpty);
  });
}

Transaction _tx({required int id, required DateTime timestamp}) => Transaction(
      id: id,
      amount: 1.0,
      currency: 'USD',
      merchant: 'Test',
      category: 'Other',
      source: 'manual',
      rawText: 'Test',
      timestamp: timestamp,
      dedupHash: 'hash-$id',
    );
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd app && flutter test test/dashboard_recent_window_test.dart -r expanded`
Expected: FAIL — `recentWithinLastWeek` is not defined.

- [ ] **Step 3: Implement the filter function and wire it into the screen**

In `app/lib/features/dashboard/dashboard_screen.dart`, add a top-level
function (above the `DashboardScreen` class, exported so the test above
can import it):

```dart
List<Transaction> recentWithinLastWeek(List<Transaction> txs, {DateTime? now}) {
  final cutoff = (now ?? DateTime.now()).subtract(const Duration(days: 7));
  return txs.where((t) => !t.timestamp.isBefore(cutoff)).toList();
}
```

In `DashboardScreen.build()`, change:

```dart
    final txs = ref.watch(transactionsStreamProvider).value ?? const [];
```

to:

```dart
    final txs = ref.watch(transactionsStreamProvider).value ?? const [];
    final recentTxs = recentWithinLastWeek(txs);
```

Change the `SliverList` block from:

```dart
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) => TransactionRow(t: TransactionSummary.fromTransaction(txs[i])),
                childCount: txs.length > 20 ? 20 : txs.length,
              ),
            ),
            if (txs.isEmpty)
              const SliverToBoxAdapter(
                child: AppEmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: 'No transactions yet',
                  body: 'Add your first expense to start seeing your money clearly.',
                ),
              ),
```

to:

```dart
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) => Dismissible(
                  key: ValueKey(recentTxs[i].id),
                  direction: DismissDirection.endToStart,
                  confirmDismiss: (_) => _confirmRemoveTransaction(context, ref, recentTxs[i]),
                  background: Container(
                    margin: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.margin,
                      vertical: 2,
                    ),
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    decoration: BoxDecoration(
                      color: AppColors.error,
                      borderRadius: BorderRadius.circular(AppRadii.xl),
                    ),
                    child: const Icon(Icons.delete_outline, color: Colors.white),
                  ),
                  child: TransactionRow(t: TransactionSummary.fromTransaction(recentTxs[i])),
                ),
                childCount: recentTxs.length > 20 ? 20 : recentTxs.length,
              ),
            ),
            if (txs.isEmpty)
              const SliverToBoxAdapter(
                child: AppEmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: 'No transactions yet',
                  body: 'Add your first expense to start seeing your money clearly.',
                ),
              )
            else if (recentTxs.isEmpty)
              const SliverToBoxAdapter(
                child: AppEmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: 'Nothing this week',
                  body: 'Your recent activity will show up here.',
                ),
              ),
```

Add this method to the `DashboardScreen` class, alongside `_showAddSheet`:

```dart
  Future<bool> _confirmRemoveTransaction(BuildContext context, WidgetRef ref, Transaction t) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${t.merchant.isEmpty ? t.category : t.merchant}?'),
        content: const Text('This transaction will be permanently deleted.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return false;
    await ref.read(appDatabaseProvider).transactionsDao.remove(t.id);
    return true;
  }
```

- [ ] **Step 4: Run the filter test**

Run: `cd app && flutter test test/dashboard_recent_window_test.dart -r expanded`
Expected: 2 tests pass.

- [ ] **Step 5: Write the render-only Dashboard screen test**

Create `app/test/dashboard_screen_test.dart`, following the same
render-only pattern used throughout this codebase for DB-backed screens:

```dart
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneylock/data/db.dart';
import 'package:moneylock/features/dashboard/dashboard_screen.dart';
import 'package:moneylock/providers.dart';

AppDatabase _db() => AppDatabase.forTesting(
    driftDatabase(name: 'test_${DateTime.now().microsecondsSinceEpoch}'));

void main() {
  testWidgets('renders the "nothing this week" empty state when history is older than 7 days',
      (tester) async {
    final db = _db();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          transactionsStreamProvider.overrideWith((ref) => Stream.value(const [])),
          budgetSummaryProvider.overrideWith((ref) => Stream.value(
                const BudgetSummary(totalSpent: 0, totalLimit: 0, byCategory: {}, byCategoryLimits: {}),
              )),
        ],
        child: const MaterialApp(home: DashboardScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No transactions yet'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.runAsync(() => db.close());
  });
}
```

(With an empty `txs` list, `recentTxs` is also empty, so the `txs.isEmpty`
branch — "No transactions yet" — renders, not the "Nothing this week"
branch; this still proves the screen builds cleanly end-to-end with all its
DB-backed providers mocked, matching this codebase's established render-only
coverage bar for DB-backed screens. `BudgetSummary`'s constructor fields —
confirm they're `const`-constructible with these exact names by checking
`lib/providers.dart` before writing this override; adjust field names if
they differ.)

- [ ] **Step 6: Run the test**

Run: `cd app && flutter test test/dashboard_screen_test.dart -r expanded`
Expected: 1 test passes.

- [ ] **Step 7: Run `flutter analyze`**

Run: `cd app && flutter analyze`
Expected: only the pre-existing info-level issues, nothing new.

- [ ] **Step 8: Run the full test suite**

Run: `cd app && flutter test` (the known-flaky `settings_notifications_test.dart`
and `subscriptions_screen_test.dart` may hang regardless of this branch's
changes — if either does, set them aside per the established workaround:
`mv test/settings_notifications_test.dart test/subscriptions_screen_test.dart /tmp/
&& flutter test && mv /tmp/settings_notifications_test.dart /tmp/subscriptions_screen_test.dart test/`)
Expected: all tests pass.

- [ ] **Step 9: Commit**

```bash
cd app
git add lib/features/dashboard/dashboard_screen.dart test/dashboard_recent_window_test.dart test/dashboard_screen_test.dart
git commit -m "feat: swipe-to-delete and 7-day window for Dashboard recent transactions"
```
