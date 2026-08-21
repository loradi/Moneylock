# Notification Scheduling System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a local-notification scheduling system that reminds the user at 9:00 AM and 2:00 PM to log their first expense of the day (only if they haven't yet), and sends a once-a-day 8:00 PM encouraging check-in with their real month-to-date spend vs. budget.

**Architecture:** A new `NotificationScheduler` class holds all the "what should be scheduled right now" logic as pure, testable decisions (given a "has an entry today" flag and month spend/limit numbers), and calls out to an injected `NotificationScheduling`-shaped dependency to actually schedule/cancel. The real `LocalNotifications` class implements that interface by wrapping `flutter_local_notifications`'s `zonedSchedule`/`cancel`. `refresh()` is called from three trigger points — app launch, app resume (new lifecycle observer), and right after a transaction is successfully recorded — so whatever's scheduled with the OS stays accurate without needing background execution.

**Tech Stack:** Flutter, Riverpod, Drift (SQLite), `flutter_local_notifications` (already a dependency), `timezone` + `flutter_timezone` (new dependencies).

## Global Constraints

- All UI copy is in English. No Spanish (or any other language) strings in any user-facing text.
- This plan covers `app/lib/core/notifications.dart`, `app/lib/core/notification_scheduler.dart` (new), `app/lib/data/db.dart`, `app/lib/data/transactions_dao.dart`, `app/lib/features/settings/settings_screen.dart`, `app/lib/main.dart`, `app/lib/features/add/add_transaction_flow.dart`, and `app/pubspec.yaml`.
- Data model note: the app currently only tracks *monthly* budget caps (`BudgetsDao`, `period` = `'YYYY-MM'`) — there is no weekly aggregation anywhere in the codebase. The 8:00 PM check-in therefore reports month-to-date spend vs. this month's total limit, not a weekly figure — the closest honest match to data that actually exists, rather than inventing a new weekly-tracking concept for one notification string.
- Notification IDs are fixed constants: `9001` = morning reminder, `9002` = afternoon reminder, `9003` = evening check-in. Reuse these exact values everywhere so `cancel()` calls always target the right pending request.

---

### Task 1: Data layer additions — `SettingsDao` toggle + `TransactionsDao` queries

**Files:**
- Modify: `app/lib/data/db.dart:12-64` (`SettingsDao`)
- Modify: `app/lib/data/transactions_dao.dart:69-81` (add methods near `categorySpentThisPeriod`)
- Test: Create `app/test/notification_data_test.dart`

**Interfaces:**
- Consumes: existing `Settings`/`Transactions` Drift tables (no schema change).
- Produces: `SettingsDao.notificationsEnabled() → Future<bool>` (default `true` when unset), `SettingsDao.setNotificationsEnabled(bool) → Future<void>`. `TransactionsDao.hasEntrySince(DateTime start) → Future<bool>`. `TransactionsDao.totalSpentThisPeriod(String period) → Future<double>` (same shape as the existing `categorySpentThisPeriod`, but summed across all categories for the month).

**Context:** `Settings`' primary key *is* the `key` column (see `app/lib/data/tables.dart:53-58`: `Set<Column> get primaryKey => {key}`), so `insertOnConflictUpdate` on this table is safe as-is — this table does **not** have the primary-key-vs-unique-constraint bug that `Categories`/`Budgets` had (those have separate autoincrement `id` columns; `Settings` doesn't). Follow the exact same pattern as `SettingsDao.setMentorTone`/`onboardingCompleted` (lines 23-34).

- [ ] **Step 1: Write the failing tests**

Create `app/test/notification_data_test.dart`:

```dart
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneylock/data/db.dart';
import 'package:moneylock/data/transactions_dao.dart';

AppDatabase _db() => AppDatabase.forTesting(
    driftDatabase(name: 'test_${DateTime.now().microsecondsSinceEpoch}'));

void main() {
  test('notificationsEnabled defaults to true and round-trips', () async {
    final db = _db();
    expect(await db.settingsDao.notificationsEnabled(), isTrue);
    await db.settingsDao.setNotificationsEnabled(false);
    expect(await db.settingsDao.notificationsEnabled(), isFalse);
    await db.settingsDao.setNotificationsEnabled(true);
    expect(await db.settingsDao.notificationsEnabled(), isTrue);
    await db.close();
  });

  test('hasEntrySince is false with no transactions, true after one', () async {
    final db = _db();
    final start = DateTime(2026, 8, 17);
    expect(await db.transactionsDao.hasEntrySince(start), isFalse);
    await db.transactionsDao.insertWithDedup(NewTransaction(
      amount: 10.0,
      currency: 'USD',
      merchant: 'Test',
      category: 'Other',
      source: 'manual',
      rawText: 'test entry',
      timestamp: DateTime(2026, 8, 17, 10),
    ));
    expect(await db.transactionsDao.hasEntrySince(start), isTrue);
    await db.close();
  });

  test('hasEntrySince ignores transactions before the given start', () async {
    final db = _db();
    await db.transactionsDao.insertWithDedup(NewTransaction(
      amount: 10.0,
      currency: 'USD',
      merchant: 'Yesterday',
      category: 'Other',
      source: 'manual',
      rawText: 'yesterday entry',
      timestamp: DateTime(2026, 8, 16, 23, 59),
    ));
    expect(await db.transactionsDao.hasEntrySince(DateTime(2026, 8, 17)), isFalse);
    await db.close();
  });

  test('totalSpentThisPeriod sums across all categories for the month', () async {
    final db = _db();
    await db.transactionsDao.insertWithDedup(NewTransaction(
      amount: 30.0,
      currency: 'USD',
      merchant: 'A',
      category: 'Coffee & Dining',
      source: 'manual',
      rawText: 'a',
      timestamp: DateTime(2026, 8, 5),
    ));
    await db.transactionsDao.insertWithDedup(NewTransaction(
      amount: 20.0,
      currency: 'USD',
      merchant: 'B',
      category: 'Groceries',
      source: 'manual',
      rawText: 'b',
      timestamp: DateTime(2026, 8, 20),
    ));
    await db.transactionsDao.insertWithDedup(NewTransaction(
      amount: 999.0,
      currency: 'USD',
      merchant: 'C',
      category: 'Other',
      source: 'manual',
      rawText: 'c',
      timestamp: DateTime(2026, 7, 31),
    ));
    expect(await db.transactionsDao.totalSpentThisPeriod('2026-08'), closeTo(50.0, 0.001));
    await db.close();
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd app && flutter test test/notification_data_test.dart`
Expected: FAIL — `notificationsEnabled`, `setNotificationsEnabled`, `hasEntrySince`, and `totalSpentThisPeriod` don't exist yet (compile errors).

- [ ] **Step 3: Add `SettingsDao` methods**

In `app/lib/data/db.dart`, inside `class SettingsDao` (after `onboardingCompleted()`, before `completeOnboarding()`, i.e. after line 34):

```dart
  Future<bool> notificationsEnabled() async {
    final row = await (db.select(
      db.settings,
    )..where((s) => s.key.equals('notifications_enabled'))).getSingleOrNull();
    return row?.value != 'false';
  }

  Future<void> setNotificationsEnabled(bool enabled) => db
      .into(db.settings)
      .insertOnConflictUpdate(
        SettingsCompanion.insert(
          key: 'notifications_enabled',
          value: enabled ? 'true' : 'false',
        ),
      );
```

Note the default-true logic (`row?.value != 'false'`, not `== 'true'`): unlike `onboardingCompleted` which must default to `false` when unset, notifications must default to **on** — so "unset" and `'true'` both count as enabled, only an explicit `'false'` turns it off.

- [ ] **Step 4: Add `TransactionsDao` methods**

In `app/lib/data/transactions_dao.dart`, after `categorySpentThisPeriod` (after line 81):

```dart
  Future<bool> hasEntrySince(DateTime start) async {
    final row = await (db.select(db.transactions)
          ..where((t) => t.timestamp.isBiggerOrEqualValue(start))
          ..limit(1))
        .getSingleOrNull();
    return row != null;
  }

  Future<double> totalSpentThisPeriod(String period) async {
    final start = DateTime.parse('$period-01T00:00:00');
    final end = DateTime(start.year, start.month + 1, 1);
    final rows = await (db.select(db.transactions)..where(
          (t) =>
              t.timestamp.isBiggerOrEqualValue(start) &
              t.timestamp.isSmallerThanValue(end),
        ))
        .get();
    return rows.fold<double>(0.0, (sum, r) => sum + r.amount);
  }
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd app && flutter test test/notification_data_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 6: Run the full test suite and analyzer to check for regressions**

Run: `cd app && flutter analyze && flutter test`
Expected: no new analyzer issues, all tests pass.

- [ ] **Step 7: Commit**

```bash
cd app && git add lib/data/db.dart lib/data/transactions_dao.dart test/notification_data_test.dart
git commit -m "feat: add notification settings toggle and daily/monthly spend queries

Prerequisite data-layer pieces for the notification scheduler: a
notifications_enabled setting (defaults to on) and two TransactionsDao
queries it needs (has anything been logged since a given time, and
total spend across all categories for a month)."
```

---

### Task 2: `LocalNotifications` scheduling API + timezone setup

**Files:**
- Modify: `app/lib/core/notifications.dart`
- Modify: `app/lib/main.dart:1-20`
- Modify: `app/pubspec.yaml:44-47` (add `timezone`, `flutter_timezone`)

**Interfaces:**
- Consumes: nothing new.
- Produces: `abstract class NotificationScheduling { Future<void> scheduleAt(int id, DateTime when, String title, String body); Future<void> cancel(int id); }`, implemented by `LocalNotifications`. Task 3's `NotificationScheduler` depends on this interface, not on `LocalNotifications` directly.

**Context:** `flutter_local_notifications` 22.3.0's `zonedSchedule` takes named parameters (`required int id, required TZDateTime scheduledDate, required NotificationDetails notificationDetails, required AndroidScheduleMode androidScheduleMode, String? title, String? body, ...}`) — matches the existing named-parameter style already used by `show()` in this file. `TZDateTime` comes from `package:timezone/timezone.dart`, which `flutter_local_notifications` already depends on transitively, but the app needs it as a *direct* dependency to construct `TZDateTime` values itself. `flutter_timezone` reads the device's actual IANA timezone name so "9:00 AM" means the user's local 9:00 AM, not UTC.

- [ ] **Step 1: Add dependencies**

In `app/pubspec.yaml`, after `flutter_local_notifications: ^22.3.0` (line 46), add:

```yaml
  timezone: ^0.11.0
  flutter_timezone: ^4.1.1
```

Run: `cd app && flutter pub get`

If `flutter_timezone`'s API differs from `FlutterTimezone.getLocalTimezone() → Future<String>` (check `flutter pub get`'s resolved version and, if needed, the package's example/README under `~/.pub-cache/hosted/pub.dev/flutter_timezone-*`), adapt Step 4 below to match the actual API — this is the one part of this task worth double-checking against the real installed package before writing code that won't compile.

- [ ] **Step 2: Write a smoke-test confirming the app still analyzes cleanly with the new scheduling API present**

This task's code can't be meaningfully unit-tested in isolation (it's a thin wrapper over a native plugin — the same reason `show()` has no test today). Verification for this task is `flutter analyze` passing with zero new issues, confirmed in Step 5. Task 3's tests are what actually exercise scheduling *decisions* through a fake implementation of the `NotificationScheduling` interface added here.

- [ ] **Step 3: Extend `lib/core/notifications.dart`**

Replace the full file:

```dart
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../llm/mentor_agent.dart';

abstract class NotificationScheduling {
  Future<void> scheduleAt(int id, DateTime when, String title, String body);
  Future<void> cancel(int id);
}

class LocalNotifications implements NotificationScheduling {
  final _plugin = FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    const settings = InitializationSettings(
        iOS: DarwinInitializationSettings(requestAlertPermission: true,
            requestBadgePermission: true, requestSoundPermission: true));
    await _plugin.initialize(settings: settings);
  }

  Future<void> show(String title, String body, Severity severity) =>
      _plugin.show(
          id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          title: title,
          body: body,
          notificationDetails: const NotificationDetails(
              iOS: DarwinNotificationDetails(badgeNumber: 1)),
          payload: severity.name);

  @override
  Future<void> scheduleAt(
    int id,
    DateTime when,
    String title,
    String body,
  ) =>
      _plugin.zonedSchedule(
        id: id,
        title: title,
        body: body,
        scheduledDate: tz.TZDateTime.from(when, tz.local),
        notificationDetails: const NotificationDetails(
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );

  @override
  Future<void> cancel(int id) => _plugin.cancel(id: id);
}
```

- [ ] **Step 4: Initialize the timezone database in `main.dart`**

In `app/lib/main.dart`, add imports (alphabetically with the existing ones):

```dart
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
```

Replace the body of `main()` (lines 11-19):

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz_data.initializeTimeZones();
  tz.setLocalLocation(tz.getLocation(await FlutterTimezone.getLocalTimezone()));
  await LocalNotifications().init();
  final container = ProviderContainer();
  unawaited(container.read(deepLinkHandlerProvider).startListening());
  runApp(UncontrolledProviderScope(
    container: container,
    child: const MoneylockApp(),
  ));
}
```

(`NotificationScheduler.refresh()` on launch is wired in Task 4, not here — this step is purely the timezone setup prerequisite.)

- [ ] **Step 5: Run the full test suite and analyzer**

Run: `cd app && flutter analyze && flutter test`
Expected: no new analyzer issues, all tests pass (this task adds no new tests of its own, per Step 2 — the existing suite must stay green).

- [ ] **Step 6: Commit**

```bash
cd app && git add lib/core/notifications.dart lib/main.dart pubspec.yaml pubspec.lock
git commit -m "feat: add local-notification scheduling API and timezone setup

Extends LocalNotifications with scheduleAt/cancel (via
flutter_local_notifications' zonedSchedule) behind a NotificationScheduling
interface, and initializes the timezone database + device-local timezone
at app startup so scheduled times are interpreted correctly."
```

---

### Task 3: `NotificationScheduler` — the core scheduling logic

**Files:**
- Create: `app/lib/core/notification_scheduler.dart`
- Test: Create `app/test/notification_scheduler_test.dart`

**Interfaces:**
- Consumes: `NotificationScheduling` (Task 2), `TransactionsDao.hasEntrySince`/`totalSpentThisPeriod` (Task 1), `SettingsDao.notificationsEnabled` (Task 1), `BudgetsDao.limitsForPeriod` (existing).
- Produces: `NotificationScheduler(AppDatabase db, NotificationScheduling notifications, {DateTime Function() now})` with `Future<void> refresh() async`. The `now` parameter defaults to `DateTime.now` but is injectable so tests can control "the current time" deterministically.

**Context:** This is the task with real design judgment — read the design spec's "Design §1" section for the full decision table (`docs/superpowers/specs/2026-08-17-notification-scheduling-design.md`) before writing code. Notification IDs: `9001` morning, `9002` afternoon, `9003` evening check-in (see Global Constraints). Times: 9:00 AM, 2:00 PM, 8:00 PM, all in the device's local time (handled by `LocalNotifications.scheduleAt`'s `tz.TZDateTime.from`, which this class doesn't need to think about — it just passes plain `DateTime` values).

- [ ] **Step 1: Write the failing tests**

Create `app/test/notification_scheduler_test.dart`:

```dart
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneylock/core/notification_scheduler.dart';
import 'package:moneylock/core/notifications.dart';
import 'package:moneylock/data/db.dart';
import 'package:moneylock/data/transactions_dao.dart';

class _FakeNotifications implements NotificationScheduling {
  final scheduled = <int, (DateTime, String, String)>{};
  final cancelled = <int>[];

  @override
  Future<void> scheduleAt(int id, DateTime when, String title, String body) async {
    scheduled[id] = (when, title, body);
  }

  @override
  Future<void> cancel(int id) async {
    cancelled.add(id);
    scheduled.remove(id);
  }
}

AppDatabase _db() => AppDatabase.forTesting(
    driftDatabase(name: 'test_${DateTime.now().microsecondsSinceEpoch}'));

void main() {
  test('before 9am with no entry today: schedules morning, afternoon, tomorrow morning, and tonight check-in',
      () async {
    final db = _db();
    final fake = _FakeNotifications();
    final scheduler = NotificationScheduler(
      db,
      fake,
      now: () => DateTime(2026, 8, 17, 7, 0),
    );
    await scheduler.refresh();

    expect(fake.scheduled[9001]?.$1, DateTime(2026, 8, 17, 9, 0));
    expect(fake.scheduled[9002]?.$1, DateTime(2026, 8, 17, 14, 0));
    expect(fake.scheduled[9003]?.$1, DateTime(2026, 8, 17, 20, 0));
    expect(fake.scheduled[9004]?.$1, DateTime(2026, 8, 18, 9, 0));
    await db.close();
  });

  test('between 9am and 2pm with no entry today: skips morning, still schedules afternoon',
      () async {
    final db = _db();
    final fake = _FakeNotifications();
    final scheduler = NotificationScheduler(
      db,
      fake,
      now: () => DateTime(2026, 8, 17, 11, 0),
    );
    await scheduler.refresh();

    expect(fake.scheduled.containsKey(9001), isFalse);
    expect(fake.scheduled[9002]?.$1, DateTime(2026, 8, 17, 14, 0));
    await db.close();
  });

  test('after an entry today: skips both reminders but still schedules the check-in',
      () async {
    final db = _db();
    await db.transactionsDao.insertWithDedup(NewTransaction(
      amount: 12.0,
      currency: 'USD',
      merchant: 'Coffee',
      category: 'Coffee & Dining',
      source: 'manual',
      rawText: 'coffee',
      timestamp: DateTime(2026, 8, 17, 8, 30),
    ));
    final fake = _FakeNotifications();
    final scheduler = NotificationScheduler(
      db,
      fake,
      now: () => DateTime(2026, 8, 17, 10, 0),
    );
    await scheduler.refresh();

    expect(fake.scheduled.containsKey(9001), isFalse);
    expect(fake.scheduled.containsKey(9002), isFalse);
    expect(fake.scheduled.containsKey(9003), isTrue);
    await db.close();
  });

  test('after 8pm: does not schedule tonight\'s check-in, still pre-schedules tomorrow morning',
      () async {
    final db = _db();
    final fake = _FakeNotifications();
    final scheduler = NotificationScheduler(
      db,
      fake,
      now: () => DateTime(2026, 8, 17, 21, 0),
    );
    await scheduler.refresh();

    expect(fake.scheduled.containsKey(9003), isFalse);
    expect(fake.scheduled[9004]?.$1, DateTime(2026, 8, 18, 9, 0));
    await db.close();
  });

  test('check-in body mentions the real month-to-date total', () async {
    final db = _db();
    await db.budgetsDao.upsert('Coffee & Dining', 200.0, '2026-08');
    await db.transactionsDao.insertWithDedup(NewTransaction(
      amount: 45.0,
      currency: 'USD',
      merchant: 'Coffee',
      category: 'Coffee & Dining',
      source: 'manual',
      rawText: 'coffee',
      timestamp: DateTime(2026, 8, 10),
    ));
    final fake = _FakeNotifications();
    final scheduler = NotificationScheduler(
      db,
      fake,
      now: () => DateTime(2026, 8, 17, 7, 0),
    );
    await scheduler.refresh();

    final body = fake.scheduled[9003]?.$3 ?? '';
    expect(body, contains('45'));
    expect(body, contains('200'));
    await db.close();
  });

  test('cancels all three same-day IDs before recomputing, every call', () async {
    final db = _db();
    final fake = _FakeNotifications();
    final scheduler = NotificationScheduler(
      db,
      fake,
      now: () => DateTime(2026, 8, 17, 7, 0),
    );
    await scheduler.refresh();
    await scheduler.refresh();

    expect(fake.cancelled, containsAll([9001, 9002, 9003]));
    await db.close();
  });

  test('notifications disabled: cancels everything and schedules nothing', () async {
    final db = _db();
    await db.settingsDao.setNotificationsEnabled(false);
    final fake = _FakeNotifications();
    final scheduler = NotificationScheduler(
      db,
      fake,
      now: () => DateTime(2026, 8, 17, 7, 0),
    );
    await scheduler.refresh();

    expect(fake.scheduled, isEmpty);
    await db.close();
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd app && flutter test test/notification_scheduler_test.dart`
Expected: FAIL — `NotificationScheduler` doesn't exist yet (compile error).

- [ ] **Step 3: Implement `NotificationScheduler`**

Create `app/lib/core/notification_scheduler.dart`:

```dart
import '../core/format.dart';
import '../data/db.dart';
import 'notifications.dart';

const morningReminderId = 9001;
const afternoonReminderId = 9002;
const eveningCheckInId = 9003;
const nextMorningReminderId = 9004;

class NotificationScheduler {
  final AppDatabase db;
  final NotificationScheduling notifications;
  final DateTime Function() now;

  NotificationScheduler(this.db, this.notifications, {DateTime Function()? now})
      : now = now ?? DateTime.now;

  Future<void> refresh() async {
    await notifications.cancel(morningReminderId);
    await notifications.cancel(afternoonReminderId);
    await notifications.cancel(eveningCheckInId);
    await notifications.cancel(nextMorningReminderId);

    if (!await db.settingsDao.notificationsEnabled()) return;

    final today = now();
    final startOfToday = DateTime(today.year, today.month, today.day);
    final hasEntryToday = await db.transactionsDao.hasEntrySince(startOfToday);

    final morning = DateTime(today.year, today.month, today.day, 9);
    final afternoon = DateTime(today.year, today.month, today.day, 14);
    final evening = DateTime(today.year, today.month, today.day, 20);
    final tomorrow = startOfToday.add(const Duration(days: 1));
    final tomorrowMorning =
        DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 9);

    if (!hasEntryToday) {
      if (today.isBefore(morning)) {
        await notifications.scheduleAt(
          morningReminderId,
          morning,
          'Log your first expense',
          'Start the day by tracking your first expense — it only takes a second.',
        );
      }
      if (today.isBefore(afternoon)) {
        await notifications.scheduleAt(
          afternoonReminderId,
          afternoon,
          'Still nothing logged today?',
          'A quick log now keeps your budget picture accurate.',
        );
      }
    }

    if (today.isBefore(evening)) {
      final period =
          '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}';
      final spent = await db.transactionsDao.totalSpentThisPeriod(period);
      final limits = await db.budgetsDao.limitsForPeriod(period);
      final totalLimit = limits.values.fold<double>(0.0, (a, b) => a + b);
      final body = totalLimit > 0
          ? "You're at ${fmtCurrency(spent)} of ${fmtCurrency(totalLimit)} this month — keep it up!"
          : "You've spent ${fmtCurrency(spent)} this month so far.";
      await notifications.scheduleAt(
        eveningCheckInId,
        evening,
        "Tonight's check-in",
        body,
      );
    }

    await notifications.scheduleAt(
      nextMorningReminderId,
      tomorrowMorning,
      'Log your first expense',
      'Start the day by tracking your first expense — it only takes a second.',
    );
  }
}
```

`fmtCurrency` already exists in `lib/core/format.dart` (used by `budget_screen.dart`) — reuse it rather than hand-rolling currency formatting again.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd app && flutter test test/notification_scheduler_test.dart`
Expected: PASS (7 tests).

- [ ] **Step 5: Run the full test suite and analyzer to check for regressions**

Run: `cd app && flutter analyze && flutter test`
Expected: no new analyzer issues, all tests pass.

- [ ] **Step 6: Commit**

```bash
cd app && git add lib/core/notification_scheduler.dart test/notification_scheduler_test.dart
git commit -m "feat: add NotificationScheduler with testable scheduling decisions

Recomputes which of the morning/afternoon reminders and the evening
check-in should be scheduled, given whether an entry exists today and
this month's real spend vs. limit. Always pre-schedules tomorrow's
morning reminder so it still fires if the app isn't reopened before
then. Not wired into the app yet -- that's the next task."
```

---

### Task 4: Wire `refresh()` into app launch, resume, and transaction flow

**Files:**
- Modify: `app/lib/main.dart`
- Modify: `app/lib/features/add/add_transaction_flow.dart:31-63`
- Test: Create `app/test/add_transaction_flow_notification_test.dart`

**Interfaces:**
- Consumes: `NotificationScheduler.refresh()` (Task 3).
- Produces: `AddTransactionFlow` gains a required `NotificationScheduler` constructor parameter (`scheduler`), calling `scheduler.refresh()` after a transaction is successfully inserted (not on dedup-skip or error paths).

**Context:** `AddTransactionFlow` is constructed in `lib/providers.dart`'s `addFlowProvider` — that provider's call site needs the new constructor argument too, but `providers.dart` is not in this plan's Global Constraints file list; touching it here is a necessary, minimal exception since `AddTransactionFlow`'s constructor is changing and every call site must follow — this is the kind of "the change literally cannot compile otherwise" exception the file-scope constraint is not meant to block.

- [ ] **Step 1: Write the failing test**

Create `app/test/add_transaction_flow_notification_test.dart`:

```dart
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneylock/core/notification_scheduler.dart';
import 'package:moneylock/core/notifications.dart';
import 'package:moneylock/data/db.dart';
import 'package:moneylock/features/add/add_transaction_flow.dart';
import 'package:moneylock/llm/categorizer_agent.dart';
import 'package:moneylock/llm/llm_provider.dart';
import 'package:moneylock/llm/mentor_agent.dart';

class _FakeLlm implements LlmProvider {
  @override
  Future<String> complete(String system, String user, {double? temperature}) async =>
      '{"amount": 12.0, "merchant": "Test", "category": "Other", "currency": "USD"}';
}

class _FakeNotifications implements NotificationScheduling {
  int refreshTriggeringCancelCalls = 0;
  @override
  Future<void> scheduleAt(int id, DateTime when, String title, String body) async {}
  @override
  Future<void> cancel(int id) async => refreshTriggeringCancelCalls++;
}

AppDatabase _db() => AppDatabase.forTesting(
    driftDatabase(name: 'test_${DateTime.now().microsecondsSinceEpoch}'));

void main() {
  test('a successfully recorded transaction triggers a scheduler refresh', () async {
    final db = _db();
    final llm = _FakeLlm();
    final fakeNotifications = _FakeNotifications();
    final flow = AddTransactionFlow(
      categorizer: CategorizerAgent(llm),
      mentor: MentorAgent(llm, db),
      db: db,
      notifications: LocalNotifications(),
      scheduler: NotificationScheduler(db, fakeNotifications),
    );

    await flow.run(rawText: 'Test 12 USD', source: 'manual');

    // refresh() always cancels the 4 known IDs first; a non-zero count
    // proves refresh() ran as a result of this call.
    expect(fakeNotifications.refreshTriggeringCancelCalls, greaterThan(0));
    await db.close();
  });
}
```

Note: this test constructs a real `LocalNotifications()` for the `notifications` param (used for the existing ad-hoc `show()` call inside `run()`) since that's unrelated to this task's change — only `scheduler` is new. If `LocalNotifications()` can't be constructed outside a Flutter test/app context in this test file, replace it with a minimal fake implementing just enough of the class's public surface used by `run()` (`show`) — check `add_transaction_flow.dart`'s actual usage before deciding.

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd app && flutter test test/add_transaction_flow_notification_test.dart`
Expected: FAIL — `AddTransactionFlow` has no `scheduler` parameter yet (compile error).

- [ ] **Step 3: Add the `scheduler` parameter and call it in `AddTransactionFlow`**

In `app/lib/features/add/add_transaction_flow.dart`, add an import:

```dart
import '../../core/notification_scheduler.dart';
```

Update the class (lines 23-30):

```dart
class AddTransactionFlow {
  final CategorizerAgent categorizer;
  final MentorAgent mentor;
  final AppDatabase db;
  final LocalNotifications notifications;
  final NotificationScheduler scheduler;
  AddTransactionFlow({required this.categorizer, required this.mentor,
      required this.db, required this.notifications, required this.scheduler});
```

In `run()`, right after the successful insert check (after line 46, before computing `verdict`):

```dart
      if (!outcome.inserted) {
        return AddResult(inserted: false);
      }
      await scheduler.refresh();
      final verdict = await mentor.evaluate(
```

- [ ] **Step 4: Update the `addFlowProvider` call site in `lib/providers.dart`**

Find `addFlowProvider`'s definition (constructs `AddTransactionFlow(...)`) and add `scheduler: NotificationScheduler(ref.watch(appDatabaseProvider), LocalNotifications())` to the constructor call, matching however `notifications:` is already being supplied there (if it's `LocalNotifications()` constructed inline, construct a second inline `LocalNotifications()` for the scheduler the same way, for consistency — don't introduce a new provider indirection this task doesn't need). Read the current `addFlowProvider` body first to match its exact style.

- [ ] **Step 5: Wire `refresh()` into app launch and resume in `main.dart`**

In `app/lib/main.dart`, add an import:

```dart
import 'core/notification_scheduler.dart';
```

After `await LocalNotifications().init();` in `main()`, add a launch-time refresh once the container exists:

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz_data.initializeTimeZones();
  tz.setLocalLocation(tz.getLocation(await FlutterTimezone.getLocalTimezone()));
  final localNotifications = LocalNotifications();
  await localNotifications.init();
  final container = ProviderContainer();
  unawaited(container.read(deepLinkHandlerProvider).startListening());
  unawaited(NotificationScheduler(
    container.read(appDatabaseProvider),
    localNotifications,
  ).refresh());
  runApp(UncontrolledProviderScope(
    container: container,
    child: MoneylockApp(notifications: localNotifications),
  ));
}
```

Change `MoneylockApp` to accept and wrap itself with a lifecycle observer:

```dart
class MoneylockApp extends StatefulWidget {
  final LocalNotifications notifications;
  const MoneylockApp({super.key, required this.notifications});

  @override
  State<MoneylockApp> createState() => _MoneylockAppState();
}

class _MoneylockAppState extends State<MoneylockApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final container = ProviderScope.containerOf(context, listen: false);
      NotificationScheduler(
        container.read(appDatabaseProvider),
        widget.notifications,
      ).refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Moneylock',
      theme: buildAppTheme(),
      routerConfig: appRouter,
      debugShowCheckedModeBanner: false,
    );
  }
}
```

`ProviderScope.containerOf(context, listen: false)` works here because `MoneylockApp` is rendered inside the `UncontrolledProviderScope` set up in `main()` — it can read the same container `main()` already has, without needing a new provider.

- [ ] **Step 6: Run the full test suite and analyzer**

Run: `cd app && flutter analyze && flutter test`
Expected: no new analyzer issues (in particular, no unused-import warnings on either file), all tests pass, including the new test from Step 1.

- [ ] **Step 7: Manual verification in the simulator**

Boot the iOS Simulator, run the app, and confirm it launches without crashing (the timezone/scheduler wiring runs on every cold start now — a mistake here would crash the app immediately). Background the app (simulator Home button or swipe) and foreground it again; confirm no crash. This task's actual notification firing at 9/2/8 isn't practical to observe live in a few minutes — trust Task 3's tests for the scheduling *decisions* and this manual pass for "does the app still start and resume correctly."

- [ ] **Step 8: Commit**

```bash
cd app && git add lib/main.dart lib/providers.dart lib/features/add/add_transaction_flow.dart test/add_transaction_flow_notification_test.dart
git commit -m "feat: wire NotificationScheduler into app launch, resume, and transaction flow

refresh() now runs on cold start, on returning to the foreground (new
WidgetsBindingObserver on MoneylockApp), and right after a transaction
is successfully recorded -- the three points where the app can
recompute what should be scheduled with the OS."
```

---

### Task 5: Settings toggle UI

**Files:**
- Modify: `app/lib/features/settings/settings_screen.dart`
- Test: Create `app/test/settings_notifications_test.dart`

**Interfaces:**
- Consumes: `SettingsDao.notificationsEnabled()`/`setNotificationsEnabled()` (Task 1).
- Produces: nothing consumed elsewhere — this is a leaf UI task.

**Context:** Follow the exact `_Section` + `_Card` pattern already used for `MENTOR TONE` (`settings_screen.dart:34-35`). There's no existing `Switch`/toggle precedent in this file (the closest is `_ToneSelector`'s `SegmentedButton`) — a plain `Switch` inside a `_Card` with a `Row` (label + switch) is the simplest fit, matching Material's standard settings-row idiom.

- [ ] **Step 1: Write the failing test**

Create `app/test/settings_notifications_test.dart`:

```dart
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneylock/data/db.dart';
import 'package:moneylock/features/settings/settings_screen.dart';
import 'package:moneylock/providers.dart';

AppDatabase _db() => AppDatabase.forTesting(
    driftDatabase(name: 'test_${DateTime.now().microsecondsSinceEpoch}'));

void main() {
  testWidgets('notifications toggle reflects and updates SettingsDao', (tester) async {
    final db = _db();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final switchFinder = find.byType(Switch);
    expect(switchFinder, findsOneWidget);
    expect(tester.widget<Switch>(switchFinder).value, isTrue);

    await tester.tap(switchFinder);
    await tester.pump();

    expect(await db.settingsDao.notificationsEnabled(), isFalse);
    await db.close();
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd app && flutter test test/settings_notifications_test.dart`
Expected: FAIL — no `Switch` exists in `SettingsScreen` yet.

- [ ] **Step 3: Add the notifications section**

In `app/lib/features/settings/settings_screen.dart`, add a new section after `VOICE` (after line 41):

```dart
            const SizedBox(height: 28),
            const _Section('NOTIFICATIONS'),
            const _NotificationsCard(),
```

Add the new widget (near `_ToneSelector`, e.g. right after it):

```dart
class _NotificationsCard extends ConsumerWidget {
  const _NotificationsCard();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabledAsync = ref.watch(notificationsEnabledProvider);
    final enabled = enabledAsync.valueOrNull ?? true;
    return _Card(
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Daily reminders and spending check-ins',
              style: AppTextStyles.bodyMd,
            ),
          ),
          Switch(
            value: enabled,
            onChanged: (v) async {
              await ref.read(appDatabaseProvider).settingsDao.setNotificationsEnabled(v);
              ref.invalidate(notificationsEnabledProvider);
            },
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Add `notificationsEnabledProvider` to `lib/providers.dart`**

Add near `mentorToneProvider`:

```dart
final notificationsEnabledProvider = FutureProvider<bool>(
  (ref) => ref.watch(appDatabaseProvider).settingsDao.notificationsEnabled(),
);
```

`settings_screen.dart` already has `import '../../providers.dart';`, which covers this new provider without an additional import.

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd app && flutter test test/settings_notifications_test.dart`
Expected: PASS.

- [ ] **Step 6: Run the full test suite and analyzer**

Run: `cd app && flutter analyze && flutter test`
Expected: no new analyzer issues, all tests pass.

- [ ] **Step 7: Manual verification in the simulator**

Boot the iOS Simulator, run the app, navigate to Settings, confirm the "NOTIFICATIONS" section renders with the switch on by default, and toggling it off/on doesn't crash and persists across a screen revisit.

- [ ] **Step 8: Commit**

```bash
cd app && git add lib/features/settings/settings_screen.dart lib/providers.dart test/settings_notifications_test.dart
git commit -m "feat: add notifications toggle to Settings

Lets the user turn off the 9am/2pm reminders and 8pm check-in without
leaving the app; NotificationScheduler.refresh() (already wired to
launch/resume/transaction-add) picks up the change on its next run."
```

---

## Self-Review Notes

- **Spec coverage:** 9:00 AM / 2:00 PM conditional reminders (Task 3), 8:00 PM check-in with real numbers (Task 3, using month-to-date since no weekly tracking exists — documented in Global Constraints), refresh on launch/resume/post-transaction (Task 4), Settings toggle (Task 5), English-only copy (all new strings are English) — all covered.
- **Type consistency:** `NotificationScheduling` (Task 2) is the single interface `NotificationScheduler` (Task 3) and its tests depend on; `LocalNotifications` implements it without changing `show()`'s existing signature. `AddTransactionFlow`'s new `scheduler` parameter (Task 4) matches `NotificationScheduler`'s constructor from Task 3 exactly.
- **Known risk flagged inline:** Task 2's exact `flutter_timezone` API is unverified against the real package (not installed at plan-writing time) — Step 1 explicitly tells the implementer to check the resolved package before trusting the plan's code verbatim, rather than silently hoping it's right.
