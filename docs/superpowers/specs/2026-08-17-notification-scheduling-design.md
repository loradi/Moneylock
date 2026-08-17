# Notification scheduling system

Sub-project 2 of 5 in the larger onboarding/notifications/subscriptions/mentor
initiative (see [2026-08-17-budget-tab-auto-save-design.md](2026-08-17-budget-tab-auto-save-design.md)
for the full decomposition and build order). Built second so the onboarding
redesign (sub-project 5) can show a real, working notification-permission
step instead of a placeholder.

## Constraint

All UI copy is in English. No Spanish (or any other language) strings in
any user-facing text.

## Problem

The app currently has no notification scheduling at all —
`lib/core/notifications.dart` only fires immediate, ad-hoc notifications
(used today by `AddTransactionFlow` right after a transaction is recorded).
The user wants three kinds of proactive local notifications:

1. A reminder at **9:00 AM** if they haven't logged their first expense of
   the day yet.
2. A follow-up reminder at **2:00 PM** if they still haven't logged
   anything that day.
3. A once-a-day, **8:00 PM** encouraging check-in showing their real
   spending for the day/week (e.g. "You're at $120 of $400 this week —
   right on track").

## Why this needs app-driven scheduling, not just a static recurring alarm

iOS local notifications scheduled with `zonedSchedule` fire from the OS
even when the app isn't running — no background modes or app extensions
needed. But whether reminders 1-2 should fire at all depends on live data
("has the user logged anything today?"), and reminder 3's *content* depends
on live data too (real spend numbers). iOS has no way to evaluate that
condition itself without a `UNNotificationServiceExtension` (a separate
iOS app-extension target, out of scope for a Flutter-only implementation).

Instead, the app recomputes and re-schedules on every opportunity it gets
to run: app launch, app resume from background, and immediately after a
transaction is successfully recorded. Between those refreshes, whatever was
last scheduled sits with the OS and fires on time — including a
same-day reminder if the user never reopens the app, and next-morning's
9:00 AM reminder pre-scheduled a day ahead so it still fires even if the
app isn't opened before then.

## Design

### 1. `NotificationScheduler.refresh()` — the core recompute-and-reschedule step

New file `lib/core/notification_scheduler.dart`. Called from three places:
app launch (`main.dart`), app resume (a new `WidgetsBindingObserver`), and
right after `AddTransactionFlow.run()` successfully records a transaction.

Each call:
1. Cancels the three well-known notification IDs (morning reminder,
   afternoon reminder, evening check-in) — always start from a clean slate.
2. If notifications are disabled in Settings, stop here (nothing gets
   rescheduled).
3. Queries whether any transaction has been recorded since local midnight
   today (new `TransactionsDao` method).
4. If no entry yet today: schedules the 9:00 AM reminder for today if that
   time hasn't passed yet, and the 2:00 PM reminder for today if that time
   hasn't passed yet.
5. Always schedules the 8:00 PM check-in for today (if that time hasn't
   passed), computing today's spend and this week's spend/limit from
   `TransactionsDao`/`BudgetsDao` at schedule time, with encouraging copy.
6. Always pre-schedules **tomorrow's** 9:00 AM reminder, so it still fires
   even if the app isn't reopened before then.

### 2. `LocalNotifications` scheduling API

Extend `lib/core/notifications.dart` with `scheduleAt(int id, DateTime
when, String title, String body)` (wraps `zonedSchedule`, one-off, no
`matchDateTimeComponents` — every occurrence is scheduled explicitly by
`refresh()`, not left to iOS's own recurrence) and `cancel(int id)`. Add
the `timezone` and `flutter_timezone` packages so `when` is interpreted in
the device's real local timezone, initialized once in `main.dart`
alongside the existing `LocalNotifications().init()` call.

### 3. Settings toggle

New "NOTIFICATIONS" section in `settings_screen.dart`, following the
existing `_Section` + `_Card` pattern used for mentor tone. A `Switch`
reads/writes a new `notifications_enabled` key in `SettingsDao` (same
string `'true'`/`'false'` convention as `onboarding_completed`, default
`'true'`). Toggling off calls `refresh()` immediately (which cancels
everything and reschedules nothing per step 2 above); toggling on calls
`refresh()` to schedule fresh.

### 4. Data layer additions

- `TransactionsDao`: new method to check whether any transaction exists
  with a timestamp at or after local midnight today.
- `SettingsDao`: `notificationsEnabled()` / `setNotificationsEnabled(bool)`,
  same pattern as `onboardingCompleted()`/mentor tone methods.

## Testing

`NotificationScheduler`'s decision logic (which of the three notifications
should be (re)scheduled, for what time, with what content, given a known
"has an entry today" state and known spend/limit numbers) is tested as pure
logic: the scheduler takes a `LocalNotifications`-shaped dependency, and
tests inject a fake that just records `scheduleAt`/`cancel` calls instead
of touching the real plugin. This avoids needing to mock
`flutter_local_notifications`'s native platform channel. A widget/DAO test
also covers the new "has an entry since midnight" query directly against a
real test database.
