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
