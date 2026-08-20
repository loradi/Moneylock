# Mentor CRUD expansion: add/edit subscriptions, edit transactions, scoped search, spending insight

Follow-up to [2026-08-19-mentor-subscriptions-budget-memory-design.md](2026-08-19-mentor-subscriptions-budget-memory-design.md).
That sub-project gave the mentor search/cancel access to subscriptions and
update access to budget limits. Live testing (and a direct scope request
from the user) surfaced the remaining gaps: the mentor still can't *add* a
subscription, can't *edit* an existing transaction or subscription (only
recategorize/delete/cancel), can't answer "give me my last 5 transactions"
without miscounting, and answers "what am I spending the most on?" by
trusting the on-device model to scan a text block and find the max rather
than computing it.

## Constraint

All UI copy is in English. No Spanish (or any other language) strings in
any user-facing text, including LLM prompts — standing rule, unchanged.

The mentor never mutates data itself. Adding a subscription, editing a
transaction, and editing a subscription all require the user to tap a
real, dedicated Confirm button — free-text confirmation is never
sufficient. This explicitly extends the existing delete/cancel/budget-
update rule to the two new mutation kinds this sub-project adds.

A mutating button (Confirm/Delete/Cancel) is never shown next to an
ambiguous (2+ match) search result — only when a search narrows to exactly
one candidate. Applies to `edit_transaction` and `edit_subscription`
exactly as it already applies to `delete_transaction`/`cancel_subscription`.

Count/total arithmetic — and now "which category is highest" — is always
computed in Dart, never delegated to the on-device model.

## Scope decisions (confirmed with the user)

- **Editing a transaction** can change amount and/or merchant (category
  correction already exists via `parseCategoryCorrection`, untouched by
  this plan).
- **Editing a subscription** changes amount only (mirrors
  `update_budget_limit`'s "one number at a time" shape).
- **Adding a subscription via chat** only supports monthly cycles with a
  day-of-month (e.g. "recurring on the 20th"). A chat request for a yearly
  subscription doesn't parse confidently and falls back to `chat` — the
  user adds it through the existing manual Subscriptions-screen form
  instead, which already supports yearly.
- Restricting the mentor to finance-only topics (no politics, no coding
  help, no health advice) is **already implemented** via
  `mentorRequestAllowed`/`mentorGuardrails` — no work needed here.

## Design

### 1. `add_subscription`

New intent. The model extracts a subscription name (reusing the existing
`merchant` field — already documented as the generic "short identifying
keyword" field, doing double duty here as "the name to save" rather than
"a search keyword"), an `amount`, and a `dayOfMonth` (1-31). `ChatIntent`
gains two new fields: `double? amount` (also used by `edit_transaction`/
`edit_subscription` below — a single generic "the new number" field,
distinct from `newLimit` which stays specific to budget limits) and
`int? dayOfMonth`. Both required (alongside `merchant` as the name) for
`add_subscription` to parse; missing either falls back to `chat`.

`MentorAgent._addSubscription(parsed)` computes the next occurrence of
`dayOfMonth` from today using direct `DateTime` constructor arithmetic
(never `Duration`-based, per the standing rule): if today's day-of-month
is less than or equal to `dayOfMonth`, the next charge is `DateTime(now.year,
now.month, dayOfMonth)`; otherwise `DateTime(now.year, now.month + 1,
dayOfMonth)`. Returns `kind: 'add_subscription_confirm'` with a new
single-object `NewSubscriptionSummary{name, amount, nextChargeDate}`
JSON-encoded into `dataJson`, and reply text like "Add Netflix at
$30.00/month, starting Sep 20?". Confirm calls
`SubscriptionsDao.add(SubscriptionsCompanion.insert(name:, amount:,
cycle: Value('monthly'), nextChargeDate:, createdAt:))` (the existing
`.add()` method, unchanged).

### 2. `edit_transaction`

New intent, mirroring `delete_transaction`'s search shape exactly (same
`category`/`merchant`/`monthsBack` params, same `TransactionsDao.search()`
call, same 0/1/2+ branching) but proposing a field change instead of a
deletion. The model additionally extracts `amount` and/or a new field
`newMerchant` (`String?`) — at least one of `amount`/`newMerchant` must be
present, else fall back to `chat`.

`TransactionsDao` gains `Future<void> updateFields(int id, {double? amount,
String? merchant})`, mirroring the existing `updateMostRecentCategory`'s
`db.update(...).write(TransactionsCompanion(...))` shape, writing only the
fields that were passed (each wrapped in `Value(...)` only when non-null,
otherwise `Value.absent()` — Drift's existing convention, already used
throughout this codebase's `Companion` writes).

0 matches → text-only "couldn't find that." 2+ matches → informational
`transaction_list` (no edit affordance), same rule as delete. Exactly 1 →
`kind: 'edit_transaction_confirm'`, `dataJson` holds a new single-object
`TransactionEditSummary{transaction: TransactionSummary, newAmount:
double?, newMerchant: String?}`, reply text shows old → new (e.g. "Change
this transaction's amount from $45.00 to $50.00?" or, if merchant is also
changing, "...and merchant from 'Store' to 'Starbucks'?"). Confirm calls
`TransactionsDao.updateFields(id, amount: newAmount, merchant:
newMerchant)`.

### 3. `edit_subscription`

New intent, mirroring `cancel_subscription`'s search shape exactly (same
`merchant`-as-name-keyword param, same `SubscriptionsDao.search()` call,
same 0/1/2+ branching) but proposing an amount change instead of
cancellation. The model additionally extracts `amount` (required, else
fall back to `chat`).

0 matches → text-only. 2+ matches → informational `subscription_list` (no
edit affordance). Exactly 1 → `kind: 'edit_subscription_confirm'`,
`dataJson` holds a new single-object `SubscriptionEditSummary{subscription:
SubscriptionSummary, newAmount: double}`, reply text shows old → new (e.g.
"Change Netflix from $15.99 to $18.99/month?"). Confirm calls the existing
`SubscriptionsDao.update(id, SubscriptionsCompanion(amount:
Value(newAmount)))` — no DAO change needed, `.update()` already exists and
already takes an arbitrary `SubscriptionsCompanion`.

### 4. Scoped search: "give me my last 5 transactions"

`ChatIntent` gains `int? count`, meaningful only for `query_transactions`.
When the user gives an explicit count with no category/merchant filter (or
even with one — "my last 5 Starbucks purchases"), the model sets `count`;
`_queryTransactions` uses `limit: count.clamp(1, 50)` (the clamp guards
against a user asking for an unreasonable number flooding the chat UI, the
same defensive spirit as the existing `.take(20)` cap) instead of the
default `limit: 500`, and skips the `.take(20)` display cap since the
result set is already small and intentional. Reply wording changes when
`count` is set: "Here are your last N transactions, totaling $X" instead
of the existing "Found N matching "$label", totaling $X" (which stays
exactly as-is when `count` is absent — this is additive, not a rewrite of
the existing behavior).

### 5. Spending-insight context: "what am I spending the most on?"

`_generalChat()` already fetches `spentByCategory` (a `Map<String,
double>`) before building its context block. Add one Dart-computed line:
find the category with the highest value via `entries.reduce((a, b) =>
a.value > b.value ? a : b)` (only when the map is non-empty), and add
`'Highest spending category this month: $topCategory ($topAmount).\n'` to
the context block, right after the existing "By category:" lines. This
gives the model a pre-resolved fact for "what am I spending the most on?"
instead of asking it to scan the category breakdown text and find the max
itself — consistent with this codebase's standing rule that arithmetic
(including "which of these numbers is biggest") stays in Dart.

### 6. UI: three new confirm-card kinds

`chat_screen.dart`'s `_Bubble`/`_BubbleState` gains three more kind-gated
getters and rendering blocks, each following the exact established
pattern (`_transactions`/`_subscriptions`/`_budgetChange` getters and their
Confirm/Cancel button pairs):

- `add_subscription_confirm`: decodes `NewSubscriptionSummary`, shows a
  `SubscriptionRow`-style preview (name/amount/next-charge-date) plus
  Confirm/Cancel. Confirm calls `SubscriptionsDao.add(...)`.
- `edit_transaction_confirm`: decodes `TransactionEditSummary`, shows the
  existing `TransactionRow` for the found transaction plus Confirm/Cancel.
  Confirm calls `TransactionsDao.updateFields(...)`.
- `edit_subscription_confirm`: decodes `SubscriptionEditSummary`, shows
  the existing `SubscriptionRow` for the found subscription plus
  Confirm/Cancel. Confirm calls `SubscriptionsDao.update(...)`.

All three reuse the same `_actionTaken`/"Done." pattern already
established for `delete_confirm`/`cancel_confirm`/`budget_confirm`.

## Testing

- `TransactionsDao.updateFields`: DAO tests for amount-only, merchant-only,
  and both-fields updates, plus confirming an omitted field is left
  unchanged.
- `MentorAgent._addSubscription`: tests for the day-of-month → next-charge-
  date computation (both branches: day not yet passed this month, day
  already passed this month), and a missing-amount/missing-day fallback to
  `chat`.
- `MentorAgent._editTransactionCandidate`/`_editSubscriptionCandidate`:
  same 0/1/2+ match shape already tested for delete/cancel, plus a test
  proving the proposed old→new values in the confirm summary are correct.
- `MentorAgent._queryTransactions` with `count` set: a test seeding more
  transactions than the requested count, asserting exactly `count` rows
  are returned and the total is computed over just those, not all matches.
- `_generalChat`'s highest-spending-category line: a test seeding multiple
  categories with distinct spend amounts, asserting the correct (highest)
  one appears in the prompt sent to the model.
- Chat screen: one render-only widget test per new confirm kind, following
  the established pattern (mocked providers, assert the right buttons/data
  render).
