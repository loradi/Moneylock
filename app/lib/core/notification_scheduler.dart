import '../core/format.dart';
import '../data/db.dart';
import 'notifications.dart';

const morningReminderId = 9001;
const afternoonReminderId = 9002;
const eveningCheckInId = 9003;
const nextMorningReminderId = 9004;

int subscriptionNotificationId(int subscriptionId) => 10000 + subscriptionId;

DateTime addCycle(DateTime date, String cycle) {
  final months = cycle == 'yearly' ? 12 : 1;
  final totalMonths = date.month - 1 + months;
  final year = date.year + totalMonths ~/ 12;
  final month = totalMonths % 12 + 1;
  final lastDayOfMonth = DateTime(year, month + 1, 0).day;
  final day = date.day < lastDayOfMonth ? date.day : lastDayOfMonth;
  return DateTime(year, month, day);
}

const _morningReminderTitle = 'Log your first expense';
const _morningReminderBody =
    'Start the day by tracking your first expense — it only takes a second.';

class NotificationScheduler {
  final AppDatabase db;
  final NotificationScheduling notifications;
  final DateTime Function() now;

  NotificationScheduler(this.db, this.notifications, {DateTime Function()? now})
      : now = now ?? DateTime.now;

  Future<void> cancel(int id) => notifications.cancel(id);

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
    final tomorrowMorning = DateTime(today.year, today.month, today.day + 1, 9);

    if (!hasEntryToday) {
      if (today.isBefore(morning)) {
        await notifications.scheduleAt(
          morningReminderId,
          morning,
          _morningReminderTitle,
          _morningReminderBody,
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
      _morningReminderTitle,
      _morningReminderBody,
    );

    final subscriptions = await db.subscriptionsDao.allForScheduling();
    for (final subscription in subscriptions) {
      var nextCharge = subscription.nextChargeDate;
      while (nextCharge.isBefore(startOfToday)) {
        nextCharge = addCycle(nextCharge, subscription.cycle);
      }
      if (nextCharge != subscription.nextChargeDate) {
        await db.subscriptionsDao.rollForwardTo(subscription.id, nextCharge);
      }

      final id = subscriptionNotificationId(subscription.id);
      await notifications.cancel(id);
      final daysOut = DateTime(nextCharge.year, nextCharge.month, nextCharge.day)
          .difference(startOfToday)
          .inDays;
      final reminderTime = DateTime(nextCharge.year, nextCharge.month, nextCharge.day - 1, 10);
      if (daysOut >= 1 && daysOut <= 2 && today.isBefore(reminderTime)) {
        await notifications.scheduleAt(
          id,
          reminderTime,
          '${subscription.name} renews soon',
          '${subscription.name} charges ${fmtCurrency(subscription.amount)} on ${fmtDate(nextCharge)}.',
        );
      }
    }
  }
}
