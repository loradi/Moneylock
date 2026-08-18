# Subscriptions tracking

Sub-project 3 of 5 in the larger onboarding/notifications/subscriptions/mentor
initiative (see [2026-08-17-budget-tab-auto-save-design.md](2026-08-17-budget-tab-auto-save-design.md)
for the full decomposition and build order). Built third so onboarding
(sub-project 5) can showcase a real, working subscriptions screen, and so
the mentor (sub-project 4) has real subscription data to reason about
("unpaid subscriptions", wasted recurring spend).

## Constraint

All UI copy is in English. No Spanish (or any other language) strings in
any user-facing text.

## Problem

The app has no concept of recurring subscriptions today. Transactions like
"Netflix" or "Spotify" get recorded as one-off spends, categorized generically
(`fallback_parser.dart` already maps some of these merchant keywords to
"Entertainment"), with no visibility into what's coming up, what a user is
paying for repeatedly, or a way to get reminded before a charge hits.

## Scope boundary

Subscriptions are a standalone tracking feature in this phase. They do
**not** generate transactions, do **not** affect Budget/Insights/Dashboard
spend totals, and do **not** touch `TransactionsDao`'s write path. Purely
additive: a new table, a new DAO, a new screen, and an extension to the
existing `NotificationScheduler`.

## Design

### 1. Data model

New table in `lib/data/tables.dart`:

```dart
class Subscriptions extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get brandKey => text().nullable()(); // key into the curated icon set, null = generic initial avatar
  RealColumn get amount => real()();
  TextColumn get currency => text().withDefault(const Constant('USD'))();
  TextColumn get cycle => text()(); // 'monthly' | 'yearly'
  DateTimeColumn get nextChargeDate => dateTime()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get source => text().withDefault(const Constant('manual'))(); // 'manual' | 'suggested'
  DateTimeColumn get createdAt => dateTime()();
}
```

New `lib/data/subscriptions_dao.dart`, `SubscriptionsDao`, following the
existing DAO pattern (see `budgets_dao.dart`/`categories_dao.dart`):

- `Stream<List<Subscription>> watchActive()` — active subscriptions ordered
  by `nextChargeDate` ascending, for the screen's list.
- `Future<int> add(SubscriptionsCompanion entry)` — plain insert (no
  conflict target needed; nothing unique-constrains this table).
- `Future<void> update(int id, SubscriptionsCompanion changes)`.
- `Future<void> setActive(int id, bool active)` — pause/cancel without
  deleting (keeps history, keeps it out of `watchActive()` and out of
  notification scheduling).
- `Future<void> remove(int id)`.
- `Future<List<Subscription>> allActiveForScheduling()` — one-shot read
  (not a stream) used by `NotificationScheduler.refresh()`.
- `Future<void> rollForwardIfPast(int id, DateTime newNextChargeDate)` —
  used by the rollover logic in §4.

Bump `AppDatabase`'s schema version and add a `from < 5` migration step
that creates the `Subscriptions` table (mirrors the existing versioned
migration pattern in `db.dart`; no data backfill needed, it's a new table).

### 2. Manual add/edit + brand icon picker

New `lib/features/subscriptions/subscriptions_screen.dart`. Settings gets
one more `_Section('SUBSCRIPTIONS')` entry (a simple `ListTile`-style row,
"Manage subscriptions" + chevron) that pushes `/subscriptions` (new
`GoRoute`, `parentNavigatorKey: _rootNavigatorKey`, same shape as the
existing `/chat` and `/settings` routes in `router.dart`).

The screen: an app bar with back button + "Subscriptions" title, a
"Suggested" section (§3) when non-empty, then the active-subscriptions list
(from `watchActive()`), each row showing the brand icon, name, next charge
date (e.g. "Renews Aug 24"), and amount. A trailing `+` button (app bar
action) opens `_AddSubscriptionSheet` (bottom sheet, matching the existing
`_AddCategoryDialog` pattern in `budget_screen.dart` for form-in-overlay
style): text field for name, amount field (reuses the currency-aware input
pattern from `manual_form.dart`), a two-segment `SegmentedButton` for
cycle (Monthly/Yearly), a date picker for next charge date, and a brand
icon grid picker.

New `lib/widgets/brand_icon.dart`: a curated `Map<String, BrandIcon>` (key
= `brandKey`, e.g. `'netflix'`, `'spotify'`) covering ~15-20 common
services (Netflix, Spotify, Disney+, YouTube Premium, Amazon Prime, Apple
Music, Apple TV+, HBO Max, iCloud+, Hulu, PlayStation Plus, Xbox Game
Pass, Adobe Creative Cloud, Dropbox, 1Password, ChatGPT Plus, Notion).
Each `BrandIcon` is `{Color color, IconData icon}` — a Material icon on a
colored circle (e.g. Netflix: red circle + `Icons.play_arrow`, Spotify:
green circle + `Icons.graphic_eq`), not a reproduction of the official
logo. A `SubscriptionAvatar(String? brandKey, String name)` widget renders
the matching `BrandIcon` if `brandKey` is set, otherwise a colored circle
with the name's first letter (color hashed from the name, same idea as
existing category-color assignment).

### 3. Suggested subscriptions

Pure function in `lib/features/subscriptions/subscription_suggestions.dart`:

```dart
List<SuggestedSubscription> detectSuggestions({
  required List<Transaction> transactions,
  required List<Subscription> existingSubscriptions,
  required Set<String> dismissedMerchants,
});
```

Groups transactions by `merchant` (case-insensitive, trimmed), keeps groups
with 2+ entries whose `amount`s are all within ±10% of the group's average,
excludes any merchant that case-insensitively matches an existing
`Subscription.name` or is in `dismissedMerchants`. Each surviving group
becomes a `SuggestedSubscription {merchant, averageAmount, occurrenceCount,
mostRecentDate}`. No DB access in this function — it's handed
already-loaded lists, so it's tested as pure logic (matches the
`NotificationScheduler` decision-logic testing approach from sub-project 2).

The screen loads transactions via the existing `transactionsStreamProvider`
and active subscriptions via `watchActive()`, runs `detectSuggestions`, and
renders a "Suggested" card per candidate with Add / Dismiss buttons.
**Add** opens `_AddSubscriptionSheet` pre-filled with the merchant name and
average amount (cycle defaults to Monthly, next charge date defaults to
"averageDate + 30 days", both user-editable before saving). **Dismiss**
appends the merchant name (lowercased) to a comma-joined list stored under
a new `SettingsDao` key `dismissed_subscription_suggestions` (same
string-value convention as `notifications_enabled`/`mentor_tone`) via two
new `SettingsDao` methods: `dismissedSubscriptionSuggestions()` returning
`Set<String>`, and `dismissSubscriptionSuggestion(String merchant)`
appending to it.

### 4. Notification integration

Extend `NotificationScheduler.refresh()` (in
`lib/core/notification_scheduler.dart`): after the existing
morning/afternoon/evening/next-morning scheduling, add a step that:

1. Reads `db.subscriptionsDao.allActiveForScheduling()`.
2. For each subscription whose `nextChargeDate` is in the past relative to
   `now()`, rolls it forward by one cycle (`+1 month` via the same
   `DateTime(y, m+1, d)` constructor-arithmetic pattern already used for
   the DST-safe "tomorrow" calculation — never `Duration`-based add — for
   `'monthly'`; `DateTime(y+1, m, d)` for `'yearly'`), repeating until the
   date is in the future, and persists it via `rollForwardIfPast`.
3. For each active subscription (using the ID scheme `10000 +
   subscription.id`, chosen to not collide with the existing fixed IDs
   9001-9004): cancels that ID first, then — only if its (possibly-just-
   rolled) `nextChargeDate` is 1-2 days out — reschedules it via
   `scheduleAt` with copy like `"Netflix charges $15.99 tomorrow"` / body
   naming the renewal date. This is the same cancel-then-maybe-reschedule
   shape already used for the 4 fixed IDs, just looped over the dynamic
   set of currently-active subscriptions instead of a fixed list.
4. A subscription that becomes inactive or gets deleted is, by definition,
   no longer in `allActiveForScheduling()`, so step 3's loop never revisits
   its ID — `refresh()` alone cannot cancel a stale reminder for a
   subscription it no longer knows about. To avoid a dangling notification,
   `SubscriptionsDao.setActive(id, false)` and `.remove(id)` are always
   called from the screen alongside an explicit
   `notifications.cancel(10000 + id)` (via the same `NotificationScheduling`
   instance the screen already has through `notificationSchedulerProvider`),
   at the call site — mirroring how the Settings notifications toggle
   (sub-project 2) calls `scheduler.refresh()` right at its own mutation
   site rather than relying on a later opportunistic refresh to catch it.
5. Skipped entirely if `notificationsEnabled()` is `false`, same as the
   rest of `refresh()` (the existing early return already covers this,
   since it happens before any scheduling in the function).

### 5. Testing

- `subscriptions_dao_test.dart`: CRUD, `watchActive()` ordering, `setActive`
  excluding from `watchActive()`, `allActiveForScheduling()`.
- `subscription_suggestions_test.dart`: candidate detected at 2+ occurrences
  within ±10%; no candidate below the threshold or outside the amount
  band; excluded when already an active subscription (case-insensitive);
  excluded when dismissed.
- `notification_scheduler_test.dart`: extend the existing fake-`NotificationScheduling`-based
  tests with cases for a subscription 1 day out (scheduled), 5 days out
  (not scheduled), a past-due date (rolled forward, then evaluated against
  the 1-2 day window on the rolled date), and yearly-cycle rollover.
- One widget test on the new screen: rendering a suggestion and tapping
  Add opens the pre-filled sheet (matching the render-focused approach
  established for `settings_notifications_test.dart` in sub-project 2,
  given the same real-native-isolate-DB-in-`testWidgets` environment
  constraint documented there — mock the DB-backed providers for the
  render, verify DAO-level behavior separately).
