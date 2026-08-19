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

  test('tomorrowMorning survives a DST fall-back day (25-hour day)', () async {
    final db = _db();
    final fake = _FakeNotifications();
    final scheduler = NotificationScheduler(
      db,
      fake,
      now: () => DateTime(2026, 11, 1, 7, 0),
    );
    await scheduler.refresh();

    expect(fake.scheduled[9004]?.$1, DateTime(2026, 11, 2, 9, 0));
    await db.close();
  });

  test('a subscription 1 day out gets a reminder scheduled', () async {
    final db = _db();
    await db.subscriptionsDao.add(SubscriptionsCompanion.insert(
      name: 'Netflix',
      amount: 15.99,
      cycle: 'monthly',
      nextChargeDate: DateTime(2026, 8, 18),
      createdAt: DateTime(2026, 1, 1),
    ));
    final fake = _FakeNotifications();
    final scheduler = NotificationScheduler(db, fake, now: () => DateTime(2026, 8, 17, 7, 0));

    await scheduler.refresh();

    final rows = await db.subscriptionsDao.allForScheduling();
    final id = subscriptionNotificationId(rows.single.id);
    expect(fake.scheduled[id]?.$2, contains('Netflix'));
    await db.close();
  });

  test('a subscription 5 days out gets no reminder', () async {
    final db = _db();
    await db.subscriptionsDao.add(SubscriptionsCompanion.insert(
      name: 'Netflix',
      amount: 15.99,
      cycle: 'monthly',
      nextChargeDate: DateTime(2026, 8, 22),
      createdAt: DateTime(2026, 1, 1),
    ));
    final fake = _FakeNotifications();
    final scheduler = NotificationScheduler(db, fake, now: () => DateTime(2026, 8, 17, 7, 0));

    await scheduler.refresh();

    final rows = await db.subscriptionsDao.allForScheduling();
    final id = subscriptionNotificationId(rows.single.id);
    expect(fake.scheduled.containsKey(id), isFalse);
    await db.close();
  });

  test('a past-due monthly subscription rolls forward to next month', () async {
    final db = _db();
    final id = await db.subscriptionsDao.add(SubscriptionsCompanion.insert(
      name: 'Netflix',
      amount: 15.99,
      cycle: 'monthly',
      nextChargeDate: DateTime(2026, 7, 1),
      createdAt: DateTime(2026, 1, 1),
    ));
    final fake = _FakeNotifications();
    final scheduler = NotificationScheduler(db, fake, now: () => DateTime(2026, 8, 17, 7, 0));

    await scheduler.refresh();

    final rows = await db.subscriptionsDao.allForScheduling();
    expect(rows.single.nextChargeDate, DateTime(2026, 9, 1));
    expect(id, isNotNull);
    await db.close();
  });

  test('a past-due yearly subscription rolls forward by a year', () async {
    final db = _db();
    await db.subscriptionsDao.add(SubscriptionsCompanion.insert(
      name: 'iCloud+',
      amount: 99.0,
      cycle: 'yearly',
      nextChargeDate: DateTime(2025, 8, 1),
      createdAt: DateTime(2026, 1, 1),
    ));
    final fake = _FakeNotifications();
    final scheduler = NotificationScheduler(db, fake, now: () => DateTime(2026, 8, 17, 7, 0));

    await scheduler.refresh();

    final rows = await db.subscriptionsDao.allForScheduling();
    expect(rows.single.nextChargeDate, DateTime(2027, 8, 1));
    await db.close();
  });
}
