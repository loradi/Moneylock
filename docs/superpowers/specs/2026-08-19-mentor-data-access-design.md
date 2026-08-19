# Mentor data access + scope expansion

Sub-project 4 of 5 in the larger onboarding/notifications/subscriptions/mentor
initiative (see [2026-08-17-budget-tab-auto-save-design.md](2026-08-17-budget-tab-auto-save-design.md)
for the full decomposition and build order). Built fourth so onboarding
(sub-project 5) can showcase a mentor that actually reasons over the user's
real data, and so the whole app has real subscriptions (sub-project 3) and
notifications (sub-project 2) data to draw on.

## Constraint

All UI copy is in English. No Spanish (or any other language) strings in
any user-facing text — this also fixes a pre-existing violation (see §1).

## Problem

The mentor chat (`lib/features/chat/chat_screen.dart`) currently has two
paths for a free-text message: recategorize the most recent transaction, or
call the raw LLM with the user's message and nothing else — no budget data,
no spend history, no subscriptions. Every financial question gets a
context-free guess. Separately:

1. `strictRamseyPrompt` (`lib/llm/prompts.dart`), the system prompt for the
   app's default mentor tone, is written in Spanish. Since it's the system
   prompt guiding the on-device model's own output style, this risks the
   mentor actually replying in Spanish under the default tone — a direct
   violation of the English-only constraint.
2. The user wants to *ask* the mentor to find specific past transactions
   ("I bought shoes about two months ago, how much did they cost?", "show
   me the last six months of groceries transactions") and to *delete* a
   transaction by describing it in chat — neither is possible today; there
   is no transaction search, and `TransactionsDao` has no delete method at
   all.
3. Dashboard's "Recent Transactions" list shows the newest 20 transactions
   regardless of age, with no way to remove one from that screen.

## Design

### 1. Fix the Spanish system prompt

Rewrite `strictRamseyPrompt` in `lib/llm/prompts.dart` to English, matching
the tone/content of `neutralAnalystPrompt` and `friendlyCoachPrompt` (firm,
concise, disciplined — same substance, just not Spanish).

### 2. Intent classification for free-text chat

New prompt `mentorIntentPrompt` in `lib/llm/prompts.dart`, following the
exact constrained-JSON-output pattern already proven in this codebase by
`categorizerSystemPrompt`: given the user's raw message, the model returns
one JSON object classifying it into `"chat"`, `"query_transactions"`, or
`"delete_transaction"`, plus best-effort parameters (`category` — one of
the existing category catalog or null, `merchant` — a short keyword or
null, `monthsBack` — an integer or null). The model never computes dates
itself; `monthsBack` is just "how many months back the user implied," and
the app converts that to an actual `DateTime` using the codebase's
established constructor-arithmetic pattern (`DateTime(y, m - n, d)`), never
`Duration` math.

If the JSON fails to parse or names an intent this app doesn't handle, fall
back to `"chat"` — a free-text question always gets *some* answer, never a
silent failure. This mirrors the existing `try/catch` fallback style
already used in `MentorAgent.evaluate()` and `chat_screen.dart`'s `_send()`.

### 3. `MentorAgent.chat()` — three-way router

New method on the existing `MentorAgent` class (`lib/llm/mentor_agent.dart`),
called from `chat_screen.dart`'s free-text branch in place of today's raw
`llmProviderProvider.complete()` call:

- **`chat`** (general question/advice): builds a compact monthly-summary
  context — total spent vs. total budget for the current period, spend by
  category vs. each category's limit (a new `TransactionsDao` aggregate
  query, §4), and active subscriptions with their next charge date (already
  available via `SubscriptionsDao.allForScheduling()`) — and sends it to
  the model alongside the user's message, same shape as the existing
  `evaluate()` method's per-category context block.
- **`query_transactions`** (find/list past transactions): the app computes
  a `since` date from `monthsBack` (or none, meaning all-time) and calls a
  new `TransactionsDao.search(category, merchantKeyword, since)`. The
  **count and total are computed in Dart**, never asked of the model — a
  small on-device model doing arithmetic on retrieved data is unreliable,
  Dart summing a list is not. The reply is a short text summary ("Found 3
  matching 'Nike', totaling $267.98") plus the matching transactions
  attached as a data card (§5).
- **`delete_transaction`**: same search as above. Zero matches → a
  text-only "couldn't find that" reply. Exactly one match → a message
  carrying that single transaction plus a real Delete/Cancel button pair
  (§5) — the mentor never deletes anything itself, only surfaces the
  candidate for the user to confirm. Two or more matches → an
  **informational** list (no delete buttons at all) asking the user to be
  more specific — a delete button next to an ambiguous candidate is exactly
  the kind of mistake this needs to design out, not just discourage.

### 4. `TransactionsDao` additions

- `spentByCategoryThisPeriod(String period)` — returns `Map<String, double>`,
  the current period's spend grouped by category. Backs the `chat` intent's
  monthly-summary context (§3). Conceptually the same aggregation
  `budgetSummaryProvider` (`lib/providers.dart`) already computes for the
  UI, but as a plain one-shot DAO query rather than a live stream — `chat()`
  needs a single read for one LLM call, not a subscription.
- `search({String? category, String? merchantKeyword, DateTime? since, int limit = 20})` —
  a parameterized Drift query (category equality, merchant/rawText
  `LIKE '%keyword%'`, timestamp lower bound, all optional and combinable),
  ordered newest-first. Drift's `.like()` is a bound parameter, not string
  concatenation — no injection risk despite building a `%...%` pattern.
- `remove(int id)` — plain delete by id. This one method serves three
  callers: the chat delete-confirmation flow (§3), and the Dashboard
  swipe-to-delete (§7) — no duplication.

### 5. Structured chat messages

`MentorMessages` (`lib/data/tables.dart`) gains two columns: `kind` (text,
default `'text'` — `'text'` | `'transaction_list'` | `'delete_confirm'`)
and `dataJson` (nullable text — a JSON-encoded list of `{id, merchant,
amount, category, timestamp}` for the two non-text kinds). Schema version
bumps 5 → 6 with a `from < 6` migration adding both columns. `MessagesDao.add`
gains optional `kind`/`transactions` parameters, encoding the list to JSON
when present.

`chat_screen.dart`'s `_Bubble` renders `content` (if non-empty) followed by,
when `kind != 'text'`, a small card matching the existing "Recent
Transactions" row style (`_TransactionRow` from the Dashboard — same
merchant/category/date/amount layout, reused rather than rebuilt). For
`kind == 'delete_confirm'` specifically, the card also renders
Delete/Cancel buttons; tapping Delete calls `TransactionsDao.remove` (a
second tap on an already-deleted row is a harmless no-op — SQL `DELETE`
matching zero rows doesn't error) and Cancel just clears the buttons from
that bubble locally, no DB write.

### 6. Everything else about the chat stays as-is

The existing scope guardrails (`mentorRequestAllowed`, `guardMentorResponse`
in `lib/llm/mentor_guardrails.dart`) already correctly reject non-finance
topics (code, politics, entertainment, investments, tax/legal, credit/loans)
before any of the above runs — not touched. The category-correction and
monetary-amount-detection branches in `chat_screen.dart`'s `_send()` are
unrelated to this work and stay exactly as they are.

### 7. Dashboard: swipe-to-delete + 7-day window

`dashboard_screen.dart`'s "Recent Transactions" section currently shows
`min(20, txs.length)` transactions regardless of age. Change to: filter
`txs` to the last 7 days first, then keep the existing 20-item cap applied
on top of that filtered list (belt-and-suspenders — the 7-day window will
almost always be the binding constraint in practice, but an unusually
active week still can't blow up the list). Each
`_TransactionRow` wraps in a `Dismissible` (`DismissDirection.endToStart`,
confirm dialog, red trash-icon background) — the exact pattern already
shipped in Budget and Subscriptions — calling `TransactionsDao.remove(id)`
from §4 on confirm.

Two distinct empty states, since "filtered to nothing" and "never added
anything" mean different things to the user: if `txs` (unfiltered) is
empty, keep the existing "No transactions yet" copy; if the 7-day-filtered
list is empty but `txs` is not, show new copy along the lines of "Nothing
this week" / "Your recent activity will show up here" — both English,
neither implying the user's history was lost.

## Testing

- `prompts.dart`: no test needed (a translated constant), but the mentor
  guardrail tests already covering scope refusal should be re-run to
  confirm nothing regressed.
- `mentor_intent` classification: unit tests against a fake `LlmProvider`
  returning canned JSON (valid `chat`/`query_transactions`/
  `delete_transaction` payloads, malformed JSON, an unrecognized intent
  string) proving the router calls the right path and the fallback-to-chat
  behavior holds.
- `TransactionsDao.search`: DAO tests for category-only, merchant-only,
  since-only, and combined filters, plus a no-match case.
- `TransactionsDao.remove`: DAO test proving deletion, and proving a second
  call on an already-removed id doesn't throw.
- `MentorAgent.chat`: tests per intent branch using a fake `LlmProvider`
  and a real test database seeded with known transactions/budgets/
  subscriptions, asserting the returned `MentorChatResult.kind` and that
  count/total text is computed correctly (not sourced from the fake LLM).
- Chat screen: one render-only widget test for each new bubble kind
  (`transaction_list`, `delete_confirm`), following the established
  render-only pattern from `settings_notifications_test.dart` given this
  screen is DB-backed.
- Dashboard: DAO-level coverage for the 7-day filter logic (pure function,
  testable without a widget), plus a render-only widget test for the
  swipe-to-delete row structure, matching the same established pattern.
