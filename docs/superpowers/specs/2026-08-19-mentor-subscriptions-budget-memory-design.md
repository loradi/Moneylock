# Mentor subscriptions/budget management + conversational memory

Follow-up to [2026-08-19-mentor-data-access-design.md](2026-08-19-mentor-data-access-design.md)
(sub-project 4 of the larger onboarding/notifications/subscriptions/mentor
initiative, already shipped). That sub-project gave the mentor search/delete
access to **transactions** only. Two gaps surfaced once a person actually
used it: the mentor can't touch **subscriptions** or **budget limits** at
all, and every chat message is handled in total isolation — the model never
sees what was said one turn ago.

## Constraint

All UI copy is in English. No Spanish (or any other language) strings in
any user-facing text, including LLM prompts — same standing rule as every
other sub-project in this initiative.

The mentor never mutates data itself. Deleting a transaction, canceling a
subscription, and changing a budget limit all require the user to tap a
real, dedicated button — free-text confirmation is never sufficient. A
delete/cancel/confirm affordance is never shown next to an ambiguous (2+
match) search result. Count/total arithmetic on retrieved data is always
computed in Dart, never delegated to the on-device model.

## Problem

1. `MentorAgent.chat()`'s intent router only knows `chat` /
   `query_transactions` / `delete_transaction`. Subscriptions are visible to
   the mentor only as read-only context inside general chat (a static list
   with no next-charge math a user could act on), and budget limits aren't
   visible or actionable at all beyond the existing monthly-summary context.
   A user asking "cancel my Netflix" or "raise my groceries limit to $400"
   gets a generic chat reply, not action.
2. Every call to `MentorAgent.chat()` is stateless
   (`lib/llm/llama_service.dart`'s `_generate()` opens a fresh `chat`
   session per call — "stateless by design," per its own comment). The
   model never sees prior turns of the conversation. A natural follow-up
   like "cancel it" after the mentor just listed one matching subscription
   fails, because nothing tells the model what "it" refers to.

## Design

### 1. Conversational memory

Both the intent-classification call and the general-chat call gain the
last 6 messages (3 user/mentor turn-pairs) from `mentor_messages`, formatted
as a plain transcript and prepended to the prompt's context. 6 was chosen
to keep prompt size modest against the model's 2048-token context window
(`ContextParams.mobile(nCtx: 2048, ...)`) while covering the common
one-turn-back follow-up ("cancel it", "the second one").

`MessagesDao` gains `Future<List<MentorMessage>> recent(int limit)` —
newest-first from the DB, reversed to chronological order for prompt
building. Only each message's `content` (the prose) goes into the
transcript — structured card data (`dataJson`) is not re-serialized into
the prompt; it stays a UI-only concern.

`MentorAgent.classify()` and `_generalChat()` both build:

```
Recent conversation:
User: <content>
Mentor: <content>
...

<existing context/system message continues below>
```

This is best-effort, not a guarantee — the on-device model may still
mis-resolve an ambiguous follow-up. That's an acceptable degradation: a
mis-resolved follow-up falls back to `chat` (existing fallback behavior) or
to an empty/wrong search result, and the delete/cancel/confirm button gate
still requires the user to visually confirm the right thing before any
mutation happens either way.

### 2. `MentorChatResult`/`MessagesDao.add` generalized for future data kinds

Today `MentorChatResult.transactions` is a `List<TransactionSummary>` and
`MessagesDao.add()` takes that same typed list and JSON-encodes it
internally. Adding subscriptions and budget-change payloads as their own
typed list params would mean a new DAO parameter (and a new `MentorChatResult`
field) every time the mentor's data surface grows.

Instead: `MentorChatResult` carries an already-JSON-encoded `String? dataJson`
(the specific encoder — `encodeTransactionSummaries`, a new
`encodeSubscriptionSummaries`, or a new budget-change encoder — is chosen
inside `MentorAgent`, which knows which kind it's building). `MessagesDao.add()`
takes that same raw `String? dataJson` straight through, no longer
transaction-specific. `chat_screen.dart`'s `_Bubble` already switches
rendering behavior on `kind`; it now also switches *decoding* on `kind`
(`decodeTransactionSummaries` for `transaction_list`/`delete_confirm`,
`decodeSubscriptionSummaries` for the two new subscription kinds, a
single-object decode for `budget_confirm`).

### 3. Subscriptions: search + cancel

New `lib/data/subscription_summary.dart`, mirroring `transaction_summary.dart`:
`SubscriptionSummary{id, name, brandKey, amount, currency, cycle,
nextChargeDate}`, with `.fromSubscription`, `.fromJson`, `.toJson`, and
top-level `encodeSubscriptionSummaries`/`decodeSubscriptionSummaries`.

`SubscriptionsDao` gains `search({String? nameKeyword, int limit = 20})` —
a `LIKE '%keyword%'` match on `name`, ordered by `nextChargeDate` ascending,
same parameterized-query shape as `TransactionsDao.search`. `.remove(id)`
already exists and is reused as-is for cancellation.

Two new intents in `mentorIntentPrompt`: `query_subscriptions` and
`cancel_subscription`, both taking a best-effort `nameKeyword` param (or
null, meaning "all").

`MentorAgent` gains `_querySubscriptions`/`_cancelSubscriptionCandidate`,
mirroring `_queryTransactions`/`_deleteTransactionCandidate` exactly:
- Query: reports count and a **monthly-equivalent total** — summing raw
  `amount` across mixed `monthly`/`yearly` cycles would misstate the number
  (the same class of bug just fixed for transaction totals), so the total is
  `Σ (cycle == 'yearly' ? amount / 12 : amount)`, computed in Dart, labeled
  "~$X/month" in the reply so the approximation is visible, not implied as
  exact.
- Cancel: 0 matches → text-only "couldn't find that." Exactly 1 match →
  `kind: 'cancel_confirm'`, a Cancel/Confirm-Cancel-Subscription button pair
  (mirrors `delete_confirm`'s Cancel/Delete pair). 2+ matches →
  `kind: 'subscription_list'`, informational only, no cancel button.

New `lib/widgets/subscription_row.dart`, extracted from
`subscriptions_screen.dart`'s `_SubscriptionRow` the same way Task 4 of the
prior sub-project extracted `TransactionRow` from Dashboard's
`_TransactionRow` — a plain (non-`Dismissible`) row taking a
`SubscriptionSummary`, reused by both the Subscriptions screen and chat's
data cards.

### 4. Budget/category limits: query (already works) + update (new)

Querying already works today — every general-chat context block already
includes spend-vs-limit per category. No new intent needed for reading.

One new intent: `update_budget_limit`, taking `category` (matched
case-insensitively against the existing category catalog the classifier
already knows from `mentorIntentPrompt`'s existing category list) and
`newLimit` (a number). If the model can't confidently extract both, the
intent falls back to `chat` (same fallback-on-uncertainty pattern already
used everywhere else) rather than guessing.

`MentorAgent._updateBudgetLimit(parsed)`: looks up the category's current
limit for the current period via `db.budgetsDao.limitsForPeriod(period)`,
and returns `kind: 'budget_confirm'` with a small new
`BudgetChangeSummary{category, currentLimit, proposedLimit, period}`
(single object, not a list — `dataJson` is just its JSON, not a JSON array)
and reply text like "Change your Groceries limit from $300.00 to $400.00?".
A Cancel/Confirm button pair renders in `_Bubble` for this kind; Confirm
calls `db.budgetsDao.upsert(category, newLimit, period)` (already exists,
does the update) and Cancel just hides the buttons locally, no DB write —
exact same interaction shape as `delete_confirm`.

### 5. Ambiguous-match safety, generalized

The existing rule — never show a mutating button next to a 2+-match result
— already extends naturally to subscriptions (`cancel_confirm` only at
exactly 1 match, same as today's `delete_confirm`) and doesn't apply to
budget limits at all (a resolved category name is either found or not,
never ambiguous the way a merchant-keyword search is).

## Testing

- `MessagesDao.recent(limit)`: DAO test seeding more than `limit` messages,
  asserting the right count/order (chronological, not reverse).
- Conversational memory: `MentorAgent.chat`/`classify` tests using a fake
  `LlmProvider` that captures the prompt it was called with, asserting a
  seeded prior turn's content appears in that prompt.
- `SubscriptionsDao.search`: DAO tests for keyword match, no-match, and the
  existing `.remove` idempotency (already covered, not re-tested).
- `MentorAgent._querySubscriptions`/`_cancelSubscriptionCandidate`: same
  shape as the existing transaction tests — 0/1/2+ match cases, and a test
  proving the monthly-equivalent total is computed correctly in Dart for a
  mix of monthly and yearly subscriptions (not sourced from the fake LLM).
- `MentorAgent._updateBudgetLimit`: tests for a resolvable category+limit
  (returns `budget_confirm` with the right before/after numbers) and an
  unresolvable one (falls back to `chat`).
- Chat screen: two more render-only widget tests, one per new kind
  category (`subscription_list`/`cancel_confirm` sharing one test the same
  way the existing transaction ones do, plus one for `budget_confirm`),
  following the established render-only pattern.
