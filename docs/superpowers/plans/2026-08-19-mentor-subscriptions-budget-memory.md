# Mentor subscriptions/budget management + conversational memory Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the mentor chat search/cancel access to subscriptions and update access to budget category limits, and give the model short-term conversational memory so follow-ups like "cancel it" work.

**Architecture:** Extends the existing `MentorAgent.chat()` intent router (three intents today: `chat`/`query_transactions`/`delete_transaction`) with three more (`query_subscriptions`/`cancel_subscription`/`update_budget_limit`), reusing the exact same DAO-search → summary-DTO → structured-chat-message → confirm-button pattern already shipped for transactions. Generalizes `MentorChatResult`/`MessagesDao.add()` from a transaction-specific `transactions: List<TransactionSummary>` field to a kind-agnostic `dataJson: String?` so each new data kind doesn't need its own DAO/model parameter. Adds a `MessagesDao.recent(limit)` read and folds the last few turns into both the intent-classification prompt and the general-chat prompt.

**Tech Stack:** Flutter/Dart, Riverpod, Drift/SQLite (same as the rest of this codebase).

## Global Constraints

- All UI copy is in English. No Spanish (or any other language) strings in any user-facing text, including LLM prompts.
- The mentor never mutates data itself. Deleting a transaction, canceling a subscription, and changing a budget limit all require the user to tap a real, dedicated button — free-text confirmation is never sufficient.
- A delete/cancel/confirm button is never shown next to an ambiguous (2+ match) search result — only when a search narrows to exactly one candidate.
- Count/total arithmetic on any data the mentor retrieves is always computed in Dart, never delegated to the on-device model.
- `DateTime` month/year arithmetic uses direct constructor arithmetic (`DateTime(y, m±n, d)`), never `Duration`-based — not touched by this plan's own code, but don't introduce a violation.

---

### Task 1: Conversational memory — `MessagesDao.recent()` + prompt injection

**Files:**
- Modify: `app/lib/data/messages_dao.dart`
- Modify: `app/lib/llm/mentor_agent.dart`
- Test: `app/test/messages_dao_test.dart`
- Test: `app/test/mentor_agent_chat_test.dart`

**Interfaces:**
- Produces: `MessagesDao.recent(int limit)` — `Future<List<MentorMessage>>`, newest-first internally, returned chronological (oldest-first). Task 4/5/6 don't depend on this directly, but every `MentorAgent` method built in this plan inherits the history-aware prompts this task wires into `classify()`/`_generalChat()`.

- [ ] **Step 1: Write the failing `recent()` test**

Append to `app/test/messages_dao_test.dart`:

```dart
  test('recent returns the newest N messages in chronological order', () async {
    final db = _db();
    for (var i = 0; i < 5; i++) {
      await db.messagesDao.add('user', 'message $i');
    }

    final recent = await db.messagesDao.recent(3);

    expect(recent.map((m) => m.content).toList(), ['message 2', 'message 3', 'message 4']);
    await db.close();
  });
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd app && flutter test test/messages_dao_test.dart -r expanded`
Expected: FAIL — `recent` is not defined on `MessagesDao`.

- [ ] **Step 3: Implement `MessagesDao.recent()`**

In `app/lib/data/messages_dao.dart`, add this method to the `MessagesDao` class (alongside `add`/`watchAll`):

```dart
  Future<List<MentorMessage>> recent(int limit) async {
    final rows = await (db.select(db.mentorMessages)
          ..orderBy([
            (m) => OrderingTerm.desc(m.createdAt),
            (m) => OrderingTerm.desc(m.id),
          ])
          ..limit(limit))
        .get();
    return rows.reversed.toList();
  }
```

The `id` tiebreaker matters: this codebase's `DateTime` columns store second-level precision, so several messages inserted within the same second (a burst, or a fast test loop) would otherwise tie on `createdAt` alone and sort unpredictably. `id` is `autoIncrement()`, so it's a reliable, strictly-increasing tiebreaker that matches true insertion order.

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd app && flutter test test/messages_dao_test.dart -r expanded`
Expected: 3 tests pass (the 2 existing ones plus this new one).

- [ ] **Step 5: Write the failing history-in-prompt tests**

Append to `app/test/mentor_agent_chat_test.dart`:

```dart
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
```

Add `_CapturingLlm` alongside the existing `_ScriptedLlm`/`_ThrowingLlm` fakes at the top of `app/test/mentor_agent_chat_test.dart`:

```dart
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
```

- [ ] **Step 6: Run the tests to verify they fail**

Run: `cd app && flutter test test/mentor_agent_chat_test.dart -r expanded`
Expected: the 3 new tests FAIL (no history is included yet — `lastUserPrompt` won't contain the seeded prior turns; the third test's exact-match will fail because today's `classify()` doesn't add a `User:` prefix at all, it sends the raw message).

- [ ] **Step 7: Implement history injection**

In `app/lib/llm/mentor_agent.dart`, add this private method to `MentorAgent` (near `classify`):

```dart
  Future<String> _historyBlock() async {
    // recent() includes the just-saved current turn as its newest row --
    // every call site in chat_screen.dart persists the user's message via
    // messagesDao.add() before calling classify()/chat(). Drop the newest
    // row so it isn't duplicated against the userMessage param each caller
    // already appends explicitly. Safe even when nothing was pre-saved
    // (e.g. these unit tests calling agent.chat() directly): dropping "the
    // newest of zero-to-N rows" never removes a real prior turn that
    // wasn't already accounted for.
    final rows = await db.messagesDao.recent(7);
    final priorTurns = rows.isEmpty ? rows : rows.sublist(0, rows.length - 1);
    if (priorTurns.isEmpty) return '';
    final lines = priorTurns
        .map((m) => '${m.role == 'user' ? 'User' : 'Mentor'}: ${m.content}')
        .join('\n');
    return 'Recent conversation:\n$lines\n\n';
  }
```

Change `classify()` from:

```dart
  Future<ChatIntent> classify(String userMessage) async {
    try {
      final raw = await provider.complete(mentorIntentPrompt, userMessage, temperature: 0.0);
      return _parseIntent(raw);
    } catch (_) {
      return ChatIntent(intent: 'chat');
    }
  }
```

to:

```dart
  Future<ChatIntent> classify(String userMessage) async {
    try {
      final history = await _historyBlock();
      final raw = await provider.complete(
        mentorIntentPrompt,
        '${history}User: $userMessage',
        temperature: 0.0,
      );
      return _parseIntent(raw);
    } catch (_) {
      return ChatIntent(intent: 'chat');
    }
  }
```

In `_generalChat()`, change the `context` assembly from:

```dart
    final context = 'This month ($period) so far:\n'
        'Total spent: \$${totalSpent.toStringAsFixed(2)} of \$${totalLimit.toStringAsFixed(2)} budgeted\n'
        'By category:\n${categoryLines.isEmpty ? '(no budgets set)' : categoryLines}\n'
        'Active subscriptions:\n$subsLines\n\n'
        'User: $userMessage';
```

to:

```dart
    final history = await _historyBlock();
    final context = '${history}This month ($period) so far:\n'
        'Total spent: \$${totalSpent.toStringAsFixed(2)} of \$${totalLimit.toStringAsFixed(2)} budgeted\n'
        'By category:\n${categoryLines.isEmpty ? '(no budgets set)' : categoryLines}\n'
        'Active subscriptions:\n$subsLines\n\n'
        'User: $userMessage';
```

- [ ] **Step 8: Run the tests to verify they pass**

Run: `cd app && flutter test test/mentor_agent_chat_test.dart -r expanded`
Expected: all tests pass (the 12 existing plus the 3 new ones = 15).

- [ ] **Step 9: Run `flutter analyze`**

Run: `cd app && flutter analyze`
Expected: only the same pre-existing info-level issues as before this task, nothing new.

- [ ] **Step 10: Commit**

```bash
cd app
git add lib/data/messages_dao.dart lib/llm/mentor_agent.dart test/messages_dao_test.dart test/mentor_agent_chat_test.dart
git commit -m "feat: add recent-message history to mentor chat and intent-classification prompts"
```

---

### Task 2: Generalize `MentorChatResult`/`MessagesDao.add()` from typed transactions to raw `dataJson`

This is a refactor of an existing, shipped interface — no new user-facing behavior, but every later task in this plan (subscriptions, budget) needs `MentorChatResult`/`MessagesDao.add()` to carry arbitrary structured data, not just a transaction list.

**Files:**
- Modify: `app/lib/llm/mentor_agent.dart`
- Modify: `app/lib/data/messages_dao.dart`
- Modify: `app/lib/features/chat/chat_screen.dart`
- Test: `app/test/messages_dao_test.dart`
- Test: `app/test/mentor_agent_chat_test.dart`
- Test: `app/test/chat_screen_test.dart` (no logic change needed — its `_msg()` helper already builds `MentorMessage` rows with a raw `dataJson` string; confirm it still compiles/passes as-is)

**Interfaces:**
- Consumes: `TransactionSummary`/`encodeTransactionSummaries`/`decodeTransactionSummaries` (unchanged, from `app/lib/data/transaction_summary.dart`).
- Produces: `MentorChatResult{content, kind, dataJson}` (replaces the `transactions` field) and `MessagesDao.add(role, content, {severity, kind, dataJson})` (replaces the `transactions` parameter) — every task after this one builds new `MentorAgent` methods and `_Bubble` rendering branches against this shape.

- [ ] **Step 1: Update `MessagesDao.add()`**

In `app/lib/data/messages_dao.dart`, change:

```dart
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
```

to:

```dart
  Future<void> add(
    String role,
    String content, {
    String severity = 'info',
    String kind = 'text',
    String? dataJson,
  }) =>
      db.into(db.mentorMessages).insert(MentorMessagesCompanion.insert(
          role: role,
          content: content,
          createdAt: DateTime.now(),
          severity: Value(severity),
          kind: Value(kind),
          dataJson: Value(dataJson),
      ));
```

Remove the now-unused `import 'transaction_summary.dart';` from this file only if `flutter analyze` actually flags it as unused after this change (it likely will, since `encodeTransactionSummaries` was the only use).

- [ ] **Step 2: Update `messages_dao_test.dart`**

Change the second test in `app/test/messages_dao_test.dart` from:

```dart
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
```

to:

```dart
  test('add with a dataJson payload stores kind and dataJson as given', () async {
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
      dataJson: encodeTransactionSummaries(summaries),
    );

    final rows = await db.messagesDao.watchAll().first;
    expect(rows.single.kind, 'transaction_list');
    final decoded = decodeTransactionSummaries(rows.single.dataJson!);
    expect(decoded.single.merchant, 'Nike');
    await db.close();
  });
```

- [ ] **Step 3: Run the DAO test to verify it passes**

Run: `cd app && flutter test test/messages_dao_test.dart -r expanded`
Expected: 3 tests pass.

- [ ] **Step 4: Update `MentorChatResult` and its two builders**

In `app/lib/llm/mentor_agent.dart`, change:

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
```

to:

```dart
class MentorChatResult {
  final String content;
  final String kind; // 'text' | 'transaction_list' | 'delete_confirm'
  final String? dataJson;
  MentorChatResult({
    required this.content,
    this.kind = 'text',
    this.dataJson,
  });
}
```

Change `_queryTransactions` from:

```dart
    final total = summaries.fold<double>(0, (a, t) => a + t.amount);
    final label = parsed.merchant ?? parsed.category ?? 'transactions';
    return MentorChatResult(
      content: 'Found ${summaries.length} matching "$label", totaling \$${total.toStringAsFixed(2)}.',
      kind: 'transaction_list',
      transactions: summaries.take(20).toList(),
    );
```

to:

```dart
    final total = summaries.fold<double>(0, (a, t) => a + t.amount);
    final label = parsed.merchant ?? parsed.category ?? 'transactions';
    return MentorChatResult(
      content: 'Found ${summaries.length} matching "$label", totaling \$${total.toStringAsFixed(2)}.',
      kind: 'transaction_list',
      dataJson: encodeTransactionSummaries(summaries.take(20).toList()),
    );
```

Change `_deleteTransactionCandidate`'s two `MentorChatResult(...transactions: summaries...)` returns similarly — both `transactions: summaries` become `dataJson: encodeTransactionSummaries(summaries)`.

- [ ] **Step 5: Update `mentor_agent_chat_test.dart`'s assertions**

Every existing assertion of the shape `expect(result.transactions, hasLength(N))` or `expect(result.transactions, isEmpty)` needs to decode `result.dataJson` first. Add this import at the top of the file: `import 'package:moneylock/data/transaction_summary.dart';`. Then replace each such assertion, e.g. change:

```dart
    expect(result.kind, 'transaction_list');
    expect(result.transactions, hasLength(2));
    expect(result.content, contains('90.00'));
```

to:

```dart
    expect(result.kind, 'transaction_list');
    expect(decodeTransactionSummaries(result.dataJson!), hasLength(2));
    expect(result.content, contains('90.00'));
```

Apply the same pattern to every other test in this file asserting on `result.transactions` (there are 6: the two `query_transactions` tests, the `delete_transaction` exactly-one/multiple/no-match tests, and the "caps rendered cards at 20" test — for that last one, `hasLength(20)` becomes `expect(decodeTransactionSummaries(result.dataJson!), hasLength(20))`). For the tests asserting `result.transactions, isEmpty` (no-match cases), change to `expect(result.dataJson, isNull);` instead — an empty-match `MentorChatResult` never sets `dataJson` at all (its `content`-only branches never pass a `dataJson:` argument, so it stays `null` by the class's default), which is a cleaner and more precise assertion than decoding an empty list would be.

- [ ] **Step 6: Run mentor_agent tests to verify they pass**

Run: `cd app && flutter test test/mentor_agent_chat_test.dart -r expanded`
Expected: 15 tests pass.

- [ ] **Step 7: Update `chat_screen.dart`**

Change the two `_send()` call sites that build the mentor's reply message. Both currently look like:

```dart
        await db.messagesDao.add(
          'mentor',
          result.content,
          kind: result.kind,
          transactions: result.transactions,
        );
```

Change both to:

```dart
        await db.messagesDao.add(
          'mentor',
          result.content,
          kind: result.kind,
          dataJson: result.dataJson,
        );
```

Change the `itemBuilder` in `build()` from:

```dart
                  final m = messages[i];
                  return _Bubble(
                    role: m.role,
                    content: m.content,
                    kind: m.kind,
                    transactions: m.dataJson == null
                        ? const []
                        : decodeTransactionSummaries(m.dataJson!),
                  );
```

to:

```dart
                  final m = messages[i];
                  return _Bubble(
                    role: m.role,
                    content: m.content,
                    kind: m.kind,
                    dataJson: m.dataJson,
                  );
```

Change `_Bubble`'s fields/constructor from:

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
```

to:

```dart
class _Bubble extends ConsumerStatefulWidget {
  final String role;
  final String content;
  final String kind;
  final String? dataJson;
  final bool thinking;
  const _Bubble({
    required this.role,
    required this.content,
    this.kind = 'text',
    this.dataJson,
    this.thinking = false,
  });
```

In `_BubbleState`, add this getter (near `_actionTaken`):

```dart
  List<TransactionSummary> get _transactions =>
      (widget.kind == 'transaction_list' || widget.kind == 'delete_confirm') && widget.dataJson != null
          ? decodeTransactionSummaries(widget.dataJson!)
          : const [];
```

Everywhere `build()` currently reads `widget.transactions`, change it to `_transactions` (the getter above) — this includes the `if (widget.transactions.isNotEmpty)` guard, the `for (final t in widget.transactions)` loop, and `widget.transactions.first.id` in the Delete button's `onPressed`. No other rendering logic changes — this is a pure plumbing swap, the visual output for `transaction_list`/`delete_confirm` is unchanged.

- [ ] **Step 8: Run `flutter analyze`**

Run: `cd app && flutter analyze`
Expected: only the same pre-existing info-level issues, nothing new. If `TransactionSummary`'s import in `chat_screen.dart` is now only used for the `_transactions` getter's return type/`decodeTransactionSummaries` call, it stays — don't remove it.

- [ ] **Step 9: Run the chat screen and mentor agent tests once more together**

Run: `cd app && flutter test test/mentor_agent_chat_test.dart test/messages_dao_test.dart -r expanded`
Expected: all pass (18 total). Do not run `test/chat_screen_test.dart` — it uses the known pre-existing `driftDatabase()`-under-`pumpAndSettle()` hang documented in this codebase's test history; it should still compile correctly against the new `_Bubble(dataJson: ...)` shape (its `_msg()` helper already builds raw `dataJson` strings, unaffected by this refactor), confirm via `flutter analyze` only.

- [ ] **Step 10: Commit**

```bash
cd app
git add lib/llm/mentor_agent.dart lib/data/messages_dao.dart lib/features/chat/chat_screen.dart test/messages_dao_test.dart test/mentor_agent_chat_test.dart
git commit -m "refactor: generalize MentorChatResult/MessagesDao.add to raw dataJson"
```

---

### Task 3: Subscriptions data layer — `SubscriptionSummary` DTO + `SubscriptionsDao.search()`

**Files:**
- Create: `app/lib/data/subscription_summary.dart`
- Modify: `app/lib/data/subscriptions_dao.dart`
- Test: `app/test/subscription_summary_test.dart`
- Test: `app/test/subscriptions_dao_search_test.dart`

**Interfaces:**
- Produces: `SubscriptionSummary{id, name, brandKey, amount, currency, cycle, nextChargeDate}` with `.fromSubscription`, `.fromJson`, `.toJson`, top-level `encodeSubscriptionSummaries`/`decodeSubscriptionSummaries`; `SubscriptionsDao.search({String? nameKeyword, int limit = 20})`. Task 4 consumes both directly.

- [ ] **Step 1: Write the failing DTO test**

Create `app/test/subscription_summary_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:moneylock/data/subscription_summary.dart';

void main() {
  test('round-trips through JSON encode/decode', () {
    final original = [
      SubscriptionSummary(
        id: 1,
        name: 'Netflix',
        brandKey: 'netflix',
        amount: 15.99,
        currency: 'USD',
        cycle: 'monthly',
        nextChargeDate: DateTime(2026, 9, 1),
      ),
      SubscriptionSummary(
        id: 2,
        name: 'Adobe Creative Cloud',
        brandKey: null,
        amount: 599.88,
        currency: 'USD',
        cycle: 'yearly',
        nextChargeDate: DateTime(2027, 1, 15),
      ),
    ];

    final decoded = decodeSubscriptionSummaries(encodeSubscriptionSummaries(original));

    expect(decoded, hasLength(2));
    expect(decoded[0].name, 'Netflix');
    expect(decoded[0].brandKey, 'netflix');
    expect(decoded[1].brandKey, isNull);
    expect(decoded[1].cycle, 'yearly');
    expect(decoded[1].nextChargeDate, DateTime(2027, 1, 15));
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd app && flutter test test/subscription_summary_test.dart -r expanded`
Expected: FAIL — the file `lib/data/subscription_summary.dart` doesn't exist.

- [ ] **Step 3: Create `SubscriptionSummary`**

Create `app/lib/data/subscription_summary.dart`:

```dart
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
```

- [ ] **Step 4: Run the DTO test to verify it passes**

Run: `cd app && flutter test test/subscription_summary_test.dart -r expanded`
Expected: 1 test passes.

- [ ] **Step 5: Write the failing `SubscriptionsDao.search()` tests**

Create `app/test/subscriptions_dao_search_test.dart`:

```dart
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneylock/data/db.dart';

AppDatabase _db() => AppDatabase.forTesting(
    driftDatabase(name: 'test_${DateTime.now().microsecondsSinceEpoch}'));

Future<int> _addSub(AppDatabase db, String name, {String cycle = 'monthly', double amount = 10.0}) =>
    db.subscriptionsDao.add(SubscriptionsCompanion.insert(
      name: name,
      amount: amount,
      cycle: cycle,
      nextChargeDate: DateTime(2026, 9, 1),
      createdAt: DateTime.now(),
    ));

void main() {
  test('search matches by name keyword, case-insensitively on substring', () async {
    final db = _db();
    await _addSub(db, 'Netflix');
    await _addSub(db, 'Spotify');

    final results = await db.subscriptionsDao.search(nameKeyword: 'flix');

    expect(results, hasLength(1));
    expect(results.single.name, 'Netflix');
    await db.close();
  });

  test('search with no keyword returns everything up to the limit', () async {
    final db = _db();
    await _addSub(db, 'Netflix');
    await _addSub(db, 'Spotify');

    final results = await db.subscriptionsDao.search();

    expect(results, hasLength(2));
    await db.close();
  });

  test('search with no matches returns an empty list', () async {
    final db = _db();
    await _addSub(db, 'Netflix');

    final results = await db.subscriptionsDao.search(nameKeyword: 'nothing');

    expect(results, isEmpty);
    await db.close();
  });

  test('search respects the limit parameter', () async {
    final db = _db();
    for (var i = 0; i < 5; i++) {
      await _addSub(db, 'Sub $i');
    }

    final results = await db.subscriptionsDao.search(limit: 3);

    expect(results, hasLength(3));
    await db.close();
  });
}
```

- [ ] **Step 6: Run the tests to verify they fail**

Run: `cd app && flutter test test/subscriptions_dao_search_test.dart -r expanded`
Expected: FAIL — `search` is not defined on `SubscriptionsDao`.

- [ ] **Step 7: Implement `SubscriptionsDao.search()`**

In `app/lib/data/subscriptions_dao.dart`, add this method to the `SubscriptionsDao` class:

```dart
  Future<List<Subscription>> search({String? nameKeyword, int limit = 20}) async {
    final q = db.select(db.subscriptions)
      ..orderBy([(s) => OrderingTerm.asc(s.nextChargeDate)])
      ..limit(limit);
    if (nameKeyword != null) {
      q.where((s) => s.name.like('%$nameKeyword%'));
    }
    return q.get();
  }
```

- [ ] **Step 8: Run the tests to verify they pass**

Run: `cd app && flutter test test/subscriptions_dao_search_test.dart -r expanded`
Expected: 4 tests pass.

- [ ] **Step 9: Run `flutter analyze`**

Run: `cd app && flutter analyze`
Expected: only the same pre-existing info-level issues, nothing new.

- [ ] **Step 10: Commit**

```bash
cd app
git add lib/data/subscription_summary.dart lib/data/subscriptions_dao.dart test/subscription_summary_test.dart test/subscriptions_dao_search_test.dart
git commit -m "feat: add SubscriptionSummary DTO and SubscriptionsDao.search"
```

---

### Task 4: Subscriptions intents — `query_subscriptions`/`cancel_subscription` in `MentorAgent`

**Files:**
- Modify: `app/lib/llm/prompts.dart`
- Modify: `app/lib/llm/mentor_agent.dart`
- Test: `app/test/mentor_agent_chat_test.dart`

**Interfaces:**
- Consumes: `SubscriptionSummary`/`encodeSubscriptionSummaries` (Task 3), `SubscriptionsDao.search`/`.remove` (Task 3 / already existing).
- Produces: `MentorChatResult` with `kind: 'subscription_list'|'cancel_confirm'` and `dataJson` holding an encoded `List<SubscriptionSummary>`. Task 5 renders these.

Note: the classifier's existing `merchant` field on `ChatIntent` is reused as the generic "short keyword" field for subscription name matching too (a subscription "name keyword" and a transaction "merchant keyword" are the same kind of fuzzy substring match) — no new field needed for this task.

- [ ] **Step 1: Write the failing tests**

Append to `app/test/mentor_agent_chat_test.dart` (add `import 'package:moneylock/data/subscription_summary.dart';` and `import 'package:moneylock/data/db.dart';` — the latter may already be imported):

```dart
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd app && flutter test test/mentor_agent_chat_test.dart -r expanded`
Expected: the 5 new tests FAIL (`query_subscriptions`/`cancel_subscription` aren't recognized intents yet, so the classifier fallback routes everything to `chat`, and the second scripted LLM response — a plain-text reply the fallback `_generalChat` path expects — is missing from these tests' single-response `_ScriptedLlm` lists, so they'll error on an out-of-range list index).

- [ ] **Step 3: Extend `mentorIntentPrompt`**

In `app/lib/llm/prompts.dart`, change `mentorIntentPrompt` from:

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

to:

```dart
final mentorIntentPrompt =
    '''
Classify the user's message about their personal finances into ONE JSON
object, no markdown, no commentary:
{"intent": "chat"|"query_transactions"|"delete_transaction"|"query_subscriptions"|"cancel_subscription",
 "category": "<one of: ${categoryCatalog.join(', ')}>"|null,
 "merchant": "<short keyword or null>", "monthsBack": <integer or null>}
Rules:
- "chat" is for general questions, advice requests, or anything not asking
  to find, list, cancel, or delete a specific past transaction or
  subscription.
- "query_transactions" is for requests to find, list, or show past
  transactions (by category, merchant, or time range).
- "delete_transaction" is for requests to remove or delete a specific past
  transaction.
- "query_subscriptions" is for requests to find, list, or ask about
  recurring subscriptions (e.g. "how much do I pay for streaming?", "when
  does Netflix renew?").
- "cancel_subscription" is for requests to cancel or remove a specific
  subscription.
- "category" must be one of the listed categories if the user names one,
  else null. Not used for subscription intents.
- "merchant" is a short keyword identifying what was bought or which
  subscription is meant (e.g. "shoes", "Nike", "Netflix"), else null.
- "monthsBack" is how many months back to search if the user gives a time
  hint (e.g. "two months ago" -> 2, "last six months" -> 6), else null. Not
  used for subscription intents.
Examples:
"what can I cut this month?" -> {"intent": "chat", "category": null, "merchant": null, "monthsBack": null}
"show me groceries transactions from the last six months" -> {"intent": "query_transactions", "category": "Groceries", "merchant": null, "monthsBack": 6}
"I bought shoes about two months ago, how much did they cost?" -> {"intent": "query_transactions", "category": null, "merchant": "shoes", "monthsBack": 2}
"delete that Nike purchase" -> {"intent": "delete_transaction", "category": null, "merchant": "Nike", "monthsBack": null}
"how much do I pay in subscriptions?" -> {"intent": "query_subscriptions", "category": null, "merchant": null, "monthsBack": null}
"cancel my Netflix" -> {"intent": "cancel_subscription", "category": null, "merchant": "Netflix", "monthsBack": null}
''';
```

- [ ] **Step 4: Update `_parseIntent`'s recognized-intent guard**

`mentorIntentPrompt` now asks the model for two more intent values, but `_parseIntent` still only recognizes the original two — without this step, `query_subscriptions`/`cancel_subscription` responses would be silently rejected and fall back to `chat`, and every test from Step 1 would fail. In `app/lib/llm/mentor_agent.dart`, change `_parseIntent` from:

```dart
ChatIntent _parseIntent(String raw) {
  try {
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final intent = json['intent'] as String?;
    if (intent != 'query_transactions' && intent != 'delete_transaction') {
      return ChatIntent(intent: 'chat');
    }
    return ChatIntent(
      intent: intent!,
      category: json['category'] as String?,
      merchant: json['merchant'] as String?,
      monthsBack: (json['monthsBack'] as num?)?.toInt(),
    );
  } catch (_) {
    return ChatIntent(intent: 'chat');
  }
}
```

to:

```dart
ChatIntent _parseIntent(String raw) {
  try {
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final intent = json['intent'] as String?;
    const recognized = {
      'query_transactions',
      'delete_transaction',
      'query_subscriptions',
      'cancel_subscription',
    };
    if (intent == null || !recognized.contains(intent)) {
      return ChatIntent(intent: 'chat');
    }
    return ChatIntent(
      intent: intent,
      category: json['category'] as String?,
      merchant: json['merchant'] as String?,
      monthsBack: (json['monthsBack'] as num?)?.toInt(),
    );
  } catch (_) {
    return ChatIntent(intent: 'chat');
  }
}
```

(Task 6 extends this `recognized` set once more, adding `update_budget_limit` plus a category/newLimit presence check — treat this step's version as the current state, not a final one.)

- [ ] **Step 5: Add the two `MentorAgent` methods and wire the switch**

In `app/lib/llm/mentor_agent.dart`, add `import '../data/subscription_summary.dart';` at the top.

Change `chat()`'s switch from:

```dart
  Future<MentorChatResult> chat(String userMessage, {ChatIntent? preclassified}) async {
    final parsed = preclassified ?? await classify(userMessage);
    switch (parsed.intent) {
      case 'query_transactions':
        return _queryTransactions(parsed);
      case 'delete_transaction':
        return _deleteTransactionCandidate(parsed);
      default:
        return _generalChat(userMessage);
    }
  }
```

to:

```dart
  Future<MentorChatResult> chat(String userMessage, {ChatIntent? preclassified}) async {
    final parsed = preclassified ?? await classify(userMessage);
    switch (parsed.intent) {
      case 'query_transactions':
        return _queryTransactions(parsed);
      case 'delete_transaction':
        return _deleteTransactionCandidate(parsed);
      case 'query_subscriptions':
        return _querySubscriptions(parsed);
      case 'cancel_subscription':
        return _cancelSubscriptionCandidate(parsed);
      default:
        return _generalChat(userMessage);
    }
  }
```

Add these two methods after `_deleteTransactionCandidate`:

```dart
  Future<MentorChatResult> _querySubscriptions(ChatIntent parsed) async {
    final rows = await db.subscriptionsDao.search(nameKeyword: parsed.merchant, limit: 100);
    final summaries = rows.map(SubscriptionSummary.fromSubscription).toList();
    if (summaries.isEmpty) {
      return MentorChatResult(content: "I couldn't find any matching subscriptions.");
    }
    final monthlyTotal = summaries.fold<double>(
      0,
      (a, s) => a + (s.cycle == 'yearly' ? s.amount / 12 : s.amount),
    );
    return MentorChatResult(
      content: 'Found ${summaries.length} subscription${summaries.length == 1 ? '' : 's'}, '
          '~\$${monthlyTotal.toStringAsFixed(2)}/month.',
      kind: 'subscription_list',
      dataJson: encodeSubscriptionSummaries(summaries),
    );
  }

  Future<MentorChatResult> _cancelSubscriptionCandidate(ChatIntent parsed) async {
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
    return MentorChatResult(
      content: 'Found this subscription -- want me to cancel it?',
      kind: 'cancel_confirm',
      dataJson: encodeSubscriptionSummaries(summaries),
    );
  }
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `cd app && flutter test test/mentor_agent_chat_test.dart -r expanded`
Expected: all pass (20 total: the 15 from Task 1 plus these 5).

- [ ] **Step 7: Run `flutter analyze`**

Run: `cd app && flutter analyze`
Expected: only the same pre-existing info-level issues, nothing new.

- [ ] **Step 8: Commit**

```bash
cd app
git add lib/llm/prompts.dart lib/llm/mentor_agent.dart test/mentor_agent_chat_test.dart
git commit -m "feat: add subscription search/cancel intents to mentor chat"
```

---

### Task 5: Subscriptions UI — shared `SubscriptionRow` widget + chat cards

**Files:**
- Create: `app/lib/widgets/subscription_row.dart`
- Modify: `app/lib/features/subscriptions/subscriptions_screen.dart`
- Modify: `app/lib/features/chat/chat_screen.dart`
- Test: `app/test/chat_screen_test.dart`

**Interfaces:**
- Consumes: `SubscriptionSummary` (Task 3), `MentorChatResult`/message `kind`s `subscription_list`/`cancel_confirm` (Task 4), `SubscriptionsDao.remove` (already existing).
- Produces: `SubscriptionRow` widget (public, takes a `SubscriptionSummary`), reused by both the Subscriptions screen and chat's data cards — same relationship `TransactionRow` already has with Dashboard and chat.

- [ ] **Step 1: Extract the shared `SubscriptionRow` widget**

Create `app/lib/widgets/subscription_row.dart`, adapting `subscriptions_screen.dart`'s existing `_SubscriptionRow` inner content (the `AppCard`/`Row` body, not the `Dismissible` wrapper around it) to take a `SubscriptionSummary` instead of a full Drift `Subscription` row:

```dart
import 'package:flutter/material.dart';

import '../core/format.dart';
import '../data/subscription_summary.dart';
import '../theme/app_theme.dart';
import 'brand_icon.dart';
import 'kit.dart';

class SubscriptionRow extends StatelessWidget {
  final SubscriptionSummary s;
  const SubscriptionRow({super.key, required this.s});
  @override
  Widget build(BuildContext context) => AppCard(
    child: Row(
      children: [
        SubscriptionAvatar(brandKey: s.brandKey, name: s.name),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.name, style: AppTextStyles.bodyMd.copyWith(fontWeight: FontWeight.w600)),
              Text(
                'Renews ${fmtDate(s.nextChargeDate)}',
                style: AppTextStyles.bodyMd.copyWith(fontSize: 13, color: AppColors.onSurfaceVariant),
              ),
            ],
          ),
        ),
        Text(fmtCurrency(s.amount), style: AppTextStyles.bodyMd.copyWith(fontWeight: FontWeight.w600)),
      ],
    ),
  );
}
```

- [ ] **Step 2: Use the shared widget from the Subscriptions screen**

In `app/lib/features/subscriptions/subscriptions_screen.dart`:

1. Add `import '../../data/subscription_summary.dart';` and `import '../../widgets/subscription_row.dart';`.
2. In `_SubscriptionRow.build()`, replace the `child: AppCard(child: Row(...))` block (everything from `AppCard(` through its matching close, currently containing the `SubscriptionAvatar`/`Column`/`Text` amount) with `child: SubscriptionRow(s: SubscriptionSummary.fromSubscription(subscription))`, keeping the outer `Padding`/`Dismissible` wrapper exactly as it is. `_SubscriptionRow` itself (the `Dismissible`-wrapped screen-specific widget) stays — only its inner card body is now delegated to the new shared `SubscriptionRow`.

Run: `cd app && flutter analyze` — confirm no unresolved references (this step is a mechanical extraction, not a behavior change).

- [ ] **Step 3: Write the failing chat screen tests**

Append to `app/test/chat_screen_test.dart` (add `import 'package:moneylock/data/subscription_summary.dart';` and `import 'package:moneylock/widgets/subscription_row.dart';`):

```dart
  testWidgets('renders a subscription_list bubble with cards and no Cancel-subscription button',
      (tester) async {
    final db = _db();
    final message = _msg(
      id: 1,
      kind: 'subscription_list',
      content: 'Found 1 subscription, ~\$15.99/month.',
      dataJson: encodeSubscriptionSummaries([
        SubscriptionSummary(
          id: 1,
          name: 'Netflix',
          brandKey: 'netflix',
          amount: 15.99,
          currency: 'USD',
          cycle: 'monthly',
          nextChargeDate: DateTime(2026, 9, 1),
        ),
      ]),
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

    expect(find.byType(SubscriptionRow), findsOneWidget);
    expect(find.text('Netflix'), findsOneWidget);
    expect(find.text('Cancel Subscription'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.runAsync(() => db.close());
  });

  testWidgets('renders a cancel_confirm bubble with Cancel Subscription and Keep It buttons',
      (tester) async {
    final db = _db();
    final message = _msg(
      id: 1,
      kind: 'cancel_confirm',
      content: 'Found this subscription -- want me to cancel it?',
      dataJson: encodeSubscriptionSummaries([
        SubscriptionSummary(
          id: 1,
          name: 'Netflix',
          brandKey: 'netflix',
          amount: 15.99,
          currency: 'USD',
          cycle: 'monthly',
          nextChargeDate: DateTime(2026, 9, 1),
        ),
      ]),
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

    expect(find.byType(SubscriptionRow), findsOneWidget);
    expect(find.text('Cancel Subscription'), findsOneWidget);
    expect(find.text('Keep It'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.runAsync(() => db.close());
  });
```

- [ ] **Step 4: Confirm the tests type-check (do not run them)**

`chat_screen_test.dart` uses the known pre-existing `driftDatabase()`-under-`pumpAndSettle()` hang documented in this codebase's test history (also affects `dashboard_screen_test.dart`, `settings_notifications_test.dart`, `subscriptions_screen_test.dart`). Do not run this file — it will hang for up to 10 minutes for reasons unrelated to this task's code. Confirm correctness by tracing the code by hand and via `flutter analyze` in Step 7 below.

- [ ] **Step 5: Add subscription rendering to `_Bubble`**

In `app/lib/features/chat/chat_screen.dart`, add the import: `import '../../data/subscription_summary.dart';` and `import '../../widgets/subscription_row.dart';`.

In `_BubbleState`, add a getter alongside `_transactions`:

```dart
  List<SubscriptionSummary> get _subscriptions =>
      (widget.kind == 'subscription_list' || widget.kind == 'cancel_confirm') && widget.dataJson != null
          ? decodeSubscriptionSummaries(widget.dataJson!)
          : const [];
```

Add a cancel method alongside `_delete`:

```dart
  Future<void> _cancelSubscription(int id) async {
    await ref.read(appDatabaseProvider).subscriptionsDao.remove(id);
    if (mounted) setState(() => _actionTaken = true);
  }
```

In `build()`'s `Column` (the non-`thinking` branch), after the existing `if (widget.transactions.isNotEmpty) ...[...]` block (now `if (_transactions.isNotEmpty) ...[...]` per Task 2's rename), add a parallel block:

```dart
                  if (_subscriptions.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    for (final s in _subscriptions)
                      Container(
                        margin: const EdgeInsets.only(bottom: 4),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(AppRadii.xl),
                        ),
                        child: SubscriptionRow(s: s),
                      ),
                    if (widget.kind == 'cancel_confirm' && !_actionTaken)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextButton(
                              onPressed: () => setState(() => _actionTaken = true),
                              style: TextButton.styleFrom(foregroundColor: AppColors.darkPrimary),
                              child: const Text('Keep It'),
                            ),
                            const SizedBox(width: 4),
                            FilledButton(
                              onPressed: () => _cancelSubscription(_subscriptions.first.id),
                              child: const Text('Cancel Subscription'),
                            ),
                          ],
                        ),
                      ),
                    if (widget.kind == 'cancel_confirm' && _actionTaken)
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
```

(This mirrors the transaction block's structure exactly, using "Keep It"/"Cancel Subscription" instead of "Cancel"/"Delete" so the two confirmation flows are visually distinguishable in a chat where both kinds of cards can appear.)

- [ ] **Step 6: Run `flutter analyze`**

Run: `cd app && flutter analyze`
Expected: only the same pre-existing info-level issues, nothing new.

- [ ] **Step 7: Run the non-hanging tests touched by this task**

Run: `cd app && flutter test test/subscriptions_dao_search_test.dart test/subscription_summary_test.dart -r expanded`
Expected: all pass (unaffected by this task, sanity check only). Do not run `test/subscriptions_screen_test.dart` or `test/chat_screen_test.dart` — both are on the known-hanging list.

- [ ] **Step 8: Commit**

```bash
cd app
git add lib/widgets/subscription_row.dart lib/features/subscriptions/subscriptions_screen.dart lib/features/chat/chat_screen.dart test/chat_screen_test.dart
git commit -m "feat: render subscription search/cancel data cards in mentor chat"
```

---

### Task 6: Budget limit updates via chat

**Files:**
- Create: `app/lib/data/budget_change_summary.dart`
- Modify: `app/lib/llm/prompts.dart`
- Modify: `app/lib/llm/mentor_agent.dart`
- Modify: `app/lib/features/chat/chat_screen.dart`
- Test: `app/test/budget_change_summary_test.dart`
- Test: `app/test/mentor_agent_chat_test.dart`
- Test: `app/test/chat_screen_test.dart`

**Interfaces:**
- Consumes: `BudgetsDao.limitsForPeriod`/`.upsert` (already existing, unchanged).
- Produces: `BudgetChangeSummary{category, currentLimit, proposedLimit, period}`, `MentorChatResult` with `kind: 'budget_confirm'`.

- [ ] **Step 1: Write the failing `BudgetChangeSummary` test**

Create `app/test/budget_change_summary_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:moneylock/data/budget_change_summary.dart';

void main() {
  test('round-trips a single change through JSON encode/decode', () {
    final original = BudgetChangeSummary(
      category: 'Groceries',
      currentLimit: 300.0,
      proposedLimit: 400.0,
      period: '2026-08',
    );

    final decoded = decodeBudgetChangeSummary(encodeBudgetChangeSummary(original));

    expect(decoded.category, 'Groceries');
    expect(decoded.currentLimit, 300.0);
    expect(decoded.proposedLimit, 400.0);
    expect(decoded.period, '2026-08');
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd app && flutter test test/budget_change_summary_test.dart -r expanded`
Expected: FAIL — the file doesn't exist.

- [ ] **Step 3: Create `BudgetChangeSummary`**

Create `app/lib/data/budget_change_summary.dart`:

```dart
import 'dart:convert';

class BudgetChangeSummary {
  final String category;
  final double currentLimit;
  final double proposedLimit;
  final String period;

  const BudgetChangeSummary({
    required this.category,
    required this.currentLimit,
    required this.proposedLimit,
    required this.period,
  });

  factory BudgetChangeSummary.fromJson(Map<String, dynamic> json) => BudgetChangeSummary(
        category: json['category'] as String,
        currentLimit: (json['currentLimit'] as num).toDouble(),
        proposedLimit: (json['proposedLimit'] as num).toDouble(),
        period: json['period'] as String,
      );

  Map<String, dynamic> toJson() => {
        'category': category,
        'currentLimit': currentLimit,
        'proposedLimit': proposedLimit,
        'period': period,
      };
}

String encodeBudgetChangeSummary(BudgetChangeSummary s) => jsonEncode(s.toJson());

BudgetChangeSummary decodeBudgetChangeSummary(String json) =>
    BudgetChangeSummary.fromJson(jsonDecode(json) as Map<String, dynamic>);
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd app && flutter test test/budget_change_summary_test.dart -r expanded`
Expected: 1 test passes.

- [ ] **Step 5: Write the failing `MentorAgent` tests**

Append to `app/test/mentor_agent_chat_test.dart` (add `import 'package:moneylock/data/budget_change_summary.dart';`):

```dart
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
```

- [ ] **Step 6: Run the tests to verify they fail**

Run: `cd app && flutter test test/mentor_agent_chat_test.dart -r expanded`
Expected: the 4 new tests FAIL — `update_budget_limit` isn't a recognized intent yet, `ChatIntent` has no `newLimit` field, and `_parseIntent`'s guard doesn't accept it.

- [ ] **Step 7: Extend `mentorIntentPrompt`, `ChatIntent`, and `_parseIntent`**

In `app/lib/llm/prompts.dart`, change `mentorIntentPrompt`'s JSON shape line and intent enum (from Task 4's version) from:

```dart
{"intent": "chat"|"query_transactions"|"delete_transaction"|"query_subscriptions"|"cancel_subscription",
 "category": "<one of: ${categoryCatalog.join(', ')}>"|null,
 "merchant": "<short keyword or null>", "monthsBack": <integer or null>}
```

to:

```dart
{"intent": "chat"|"query_transactions"|"delete_transaction"|"query_subscriptions"|"cancel_subscription"|"update_budget_limit",
 "category": "<one of: ${categoryCatalog.join(', ')}>"|null,
 "merchant": "<short keyword or null>", "monthsBack": <integer or null>,
 "newLimit": <number or null>}
```

Add a new rule line after the existing `cancel_subscription` rule:

```
- "update_budget_limit" is for requests to change a category's monthly
  spending limit (e.g. "raise my groceries limit to $400", "set travel
  budget to $200"). Requires both "category" (one of the listed
  categories) and "newLimit" (the target amount as a plain number, no
  currency symbol) -- if either can't be confidently determined, use
  "chat" instead of guessing.
- "newLimit" is the requested new limit as a plain number if the intent is
  "update_budget_limit", else null.
```

Add one more example at the end:

```
"raise my groceries limit to $400" -> {"intent": "update_budget_limit", "category": "Groceries", "merchant": null, "monthsBack": null, "newLimit": 400}
```

In `app/lib/llm/mentor_agent.dart`, change `ChatIntent` from:

```dart
class ChatIntent {
  final String intent;
  final String? category;
  final String? merchant;
  final int? monthsBack;
  ChatIntent({required this.intent, this.category, this.merchant, this.monthsBack});
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
  ChatIntent({
    required this.intent,
    this.category,
    this.merchant,
    this.monthsBack,
    this.newLimit,
  });
}
```

Change `_parseIntent` from the four-value `recognized` set Task 4 left it with (`query_transactions`, `delete_transaction`, `query_subscriptions`, `cancel_subscription`) to this full, current-state body — a straightforward extension adding the fifth intent plus its category/newLimit presence check:

```dart
ChatIntent _parseIntent(String raw) {
  try {
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final intent = json['intent'] as String?;
    const recognized = {
      'query_transactions',
      'delete_transaction',
      'query_subscriptions',
      'cancel_subscription',
      'update_budget_limit',
    };
    if (intent == null || !recognized.contains(intent)) {
      return ChatIntent(intent: 'chat');
    }
    if (intent == 'update_budget_limit' &&
        (json['category'] == null || json['newLimit'] == null)) {
      return ChatIntent(intent: 'chat');
    }
    return ChatIntent(
      intent: intent,
      category: json['category'] as String?,
      merchant: json['merchant'] as String?,
      monthsBack: (json['monthsBack'] as num?)?.toInt(),
      newLimit: (json['newLimit'] as num?)?.toDouble(),
    );
  } catch (_) {
    return ChatIntent(intent: 'chat');
  }
}
```

- [ ] **Step 8: Add `_updateBudgetLimit` and wire the switch**

In `app/lib/llm/mentor_agent.dart`, add `import '../data/budget_change_summary.dart';` at the top.

Change `chat()`'s switch to add one more case:

```dart
      case 'update_budget_limit':
        return _updateBudgetLimit(parsed);
```

(placed alongside the other `case` lines, before `default:`).

Add this method after `_cancelSubscriptionCandidate`:

```dart
  Future<MentorChatResult> _updateBudgetLimit(ChatIntent parsed) async {
    final category = parsed.category!;
    final newLimit = parsed.newLimit!;
    final now = DateTime.now();
    final period = '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}';
    final limits = await db.budgetsDao.limitsForPeriod(period);
    final currentLimit = limits[category] ?? 0.0;
    final change = BudgetChangeSummary(
      category: category,
      currentLimit: currentLimit,
      proposedLimit: newLimit,
      period: period,
    );
    return MentorChatResult(
      content: 'Change your $category limit from \$${currentLimit.toStringAsFixed(2)} '
          'to \$${newLimit.toStringAsFixed(2)}?',
      kind: 'budget_confirm',
      dataJson: encodeBudgetChangeSummary(change),
    );
  }
```

(`parsed.category!`/`parsed.newLimit!` are safe here: `_parseIntent`'s guard in Step 7 only ever produces `intent: 'update_budget_limit'` when both fields are non-null, and `chat()`'s switch only reaches this method for that exact intent string.)

- [ ] **Step 9: Run the tests to verify they pass**

Run: `cd app && flutter test test/mentor_agent_chat_test.dart -r expanded`
Expected: all pass (24 total).

- [ ] **Step 10: Add `budget_confirm` rendering to `_Bubble`**

In `app/lib/features/chat/chat_screen.dart`, add the import: `import '../../data/budget_change_summary.dart';`.

In `_BubbleState`, add a getter:

```dart
  BudgetChangeSummary? get _budgetChange =>
      widget.kind == 'budget_confirm' && widget.dataJson != null
          ? decodeBudgetChangeSummary(widget.dataJson!)
          : null;
```

Add a confirm method alongside `_delete`/`_cancelSubscription`:

```dart
  Future<void> _confirmBudgetChange(BudgetChangeSummary change) async {
    await ref.read(appDatabaseProvider).budgetsDao.upsert(
          change.category,
          change.proposedLimit,
          change.period,
        );
    if (mounted) setState(() => _actionTaken = true);
  }
```

In `build()`'s `Column`, after the `_subscriptions`-driven block from Task 5, add:

```dart
                  if (_budgetChange != null) ...[
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
                              onPressed: () => _confirmBudgetChange(_budgetChange!),
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
                          style: TextStyle(
                            color: AppColors.darkOnSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
```

(This kind has no data-card row to render above the buttons — the confirmation text itself, already shown via `widget.content`, carries the before/after numbers. Unlike the transaction/subscription blocks, there's no `for` loop here since `BudgetChangeSummary` is a single object, not a list.)

- [ ] **Step 11: Write the failing chat screen test**

Append to `app/test/chat_screen_test.dart` (add `import 'package:moneylock/data/budget_change_summary.dart';`):

```dart
  testWidgets('renders a budget_confirm bubble with Confirm and Cancel buttons',
      (tester) async {
    final db = _db();
    final message = _msg(
      id: 1,
      kind: 'budget_confirm',
      content: 'Change your Groceries limit from \$300.00 to \$400.00?',
      dataJson: encodeBudgetChangeSummary(const BudgetChangeSummary(
        category: 'Groceries',
        currentLimit: 300.0,
        proposedLimit: 400.0,
        period: '2026-08',
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

    expect(find.textContaining('Groceries limit'), findsOneWidget);
    expect(find.text('Confirm'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.runAsync(() => db.close());
  });
```

Do not run this file (or `test/subscriptions_screen_test.dart`) — same pre-existing hang as Task 5's tests. Confirm correctness via `flutter analyze` only.

- [ ] **Step 12: Run `flutter analyze`**

Run: `cd app && flutter analyze`
Expected: only the same pre-existing info-level issues, nothing new.

- [ ] **Step 13: Run the non-hanging tests touched by this task**

Run: `cd app && flutter test test/mentor_agent_chat_test.dart test/budget_change_summary_test.dart -r expanded`
Expected: all pass (25 total).

- [ ] **Step 14: Commit**

```bash
cd app
git add lib/data/budget_change_summary.dart lib/llm/prompts.dart lib/llm/mentor_agent.dart lib/features/chat/chat_screen.dart test/budget_change_summary_test.dart test/mentor_agent_chat_test.dart test/chat_screen_test.dart
git commit -m "feat: add budget limit updates via mentor chat"
```
