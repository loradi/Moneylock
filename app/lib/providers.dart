import 'dart:async';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/deep_links.dart';
import 'core/notification_scheduler.dart';
import 'core/notifications.dart';
import 'data/db.dart';
import 'data/exchange_rate_service.dart';
import 'data/savings_goal.dart';
import 'features/add/add_transaction_flow.dart';
import 'features/insights/insights_agent.dart';
import 'features/insights/spending_trend.dart';
import 'features/budget/plan_period.dart';
import 'llm/categorizer_agent.dart';
import 'llm/llama_service.dart';
import 'llm/llm_provider.dart';
import 'llm/mentor_agent.dart';
import 'sync/sync_service.dart';
import 'sync/sync_credential_store.dart';
import 'voice/speech_service.dart';

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase(driftDatabase(name: 'moneylock'));
  ref.onDispose(db.close);
  return db;
});

final llamaServiceProvider = Provider<LlamaService>((ref) => LlamaService());

final llmProviderProvider = Provider<LlmProvider>(
  (ref) => LocalLlmProvider(ref.watch(llamaServiceProvider)),
);

final categorizerProvider = Provider<CategorizerAgent>(
  (ref) => CategorizerAgent(ref.watch(llmProviderProvider)),
);

final mentorProvider = Provider<MentorAgent>(
  (ref) => MentorAgent(
    ref.watch(llmProviderProvider),
    ref.watch(appDatabaseProvider),
  ),
);

final notificationSchedulerProvider = Provider<NotificationScheduler>(
  (ref) => NotificationScheduler(
    ref.watch(appDatabaseProvider),
    LocalNotifications(),
  ),
);

final addFlowProvider = Provider<AddTransactionFlow>(
  (ref) => AddTransactionFlow(
    categorizer: ref.watch(categorizerProvider),
    mentor: ref.watch(mentorProvider),
    db: ref.watch(appDatabaseProvider),
    notifications: LocalNotifications(),
    scheduler: ref.watch(notificationSchedulerProvider),
  ),
);

final deepLinkHandlerProvider = Provider<DeepLinkHandler>(
  (ref) => DeepLinkHandler(flow: ref.watch(addFlowProvider)),
);

final syncCredentialStoreProvider = Provider<SyncCredentialStore>(
  (ref) => PlatformSyncCredentialStore(),
);

final exchangeRateServiceProvider = Provider<ExchangeRateService>(
  (ref) => ExchangeRateService(),
);

final syncServiceProvider = Provider<SyncService>(
  (ref) => SyncService(
    ref.watch(appDatabaseProvider),
    credentialStore: ref.watch(syncCredentialStoreProvider),
  ),
);

final speechServiceProvider = Provider<SpeechToTextService>(
  (ref) => SpeechToTextService(),
);

final transactionsStreamProvider = StreamProvider<List<Transaction>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final q = db.select(db.transactions)
    ..orderBy([(t) => OrderingTerm.desc(t.timestamp)]);
  return q.watch();
});

final messagesStreamProvider = StreamProvider<List<MentorMessage>>(
  (ref) => ref.watch(appDatabaseProvider).messagesDao.watchAll(),
);

final subscriptionsProvider = StreamProvider<List<Subscription>>(
  (ref) => ref.watch(appDatabaseProvider).subscriptionsDao.watchAll(),
);

final mentorToneProvider = FutureProvider<String>(
  (ref) => ref.watch(appDatabaseProvider).settingsDao.mentorTone(),
);

final notificationsEnabledProvider = FutureProvider<bool>(
  (ref) => ref.watch(appDatabaseProvider).settingsDao.notificationsEnabled(),
);

final defaultCurrencyProvider = FutureProvider<String>(
  (ref) => ref.watch(appDatabaseProvider).settingsDao.defaultCurrency(),
);

final planCycleProvider = FutureProvider<String>(
  (ref) => ref.watch(appDatabaseProvider).settingsDao.planCycle(),
);

final savingsGoalProvider = FutureProvider<SavingsGoal?>(
  (ref) => ref.watch(appDatabaseProvider).settingsDao.savingsGoal(),
);

/// Combina el stream de transacciones y el de presupuestos: se re-emite
/// cuando cualquiera de las dos tablas cambia, así editar un límite en
/// Settings refresca las barras del Dashboard sin esperar una transacción.
final budgetSummaryProvider = StreamProvider<BudgetSummary>((ref) async* {
  final db = ref.watch(appDatabaseProvider);
  final txsStream = db.select(db.transactions).watch();
  final budgetsStream = db.select(db.budgets).watch();
  final settingsStream = db.select(db.settings).watch();
  final events = StreamController<Object?>();

  List<Transaction>? txRows;
  final budgetRows = <Budget>[];
  final settings = <String, String>{};
  final txSub = txsStream.listen((rows) {
    txRows = rows;
    events.add(null);
  });
  final bSub = budgetsStream.listen((rows) {
    budgetRows
      ..clear()
      ..addAll(rows);
    events.add(null);
  });
  final settingsSub = settingsStream.listen((rows) {
    settings
      ..clear()
      ..addEntries(rows.map((row) => MapEntry(row.key, row.value)));
    events.add(null);
  });

  final it = StreamIterator(events.stream);
  try {
    while (await it.moveNext()) {
      final rows = txRows;
      if (rows == null) continue;
      final now = DateTime.now();
      final cycle = PlanCycle.fromStorage(settings['plan_cycle'] ?? 'monthly');
      final period = cycle.keyFor(now);
      final start = cycle.startFor(now);
      final end = cycle.endFor(now);
      var activeBudgets = budgetRows
          .where(
            (b) =>
                b.enabled &&
                b.cycle == cycle.storageValue &&
                b.period == period,
          )
          .toList();
      var budgetScale = 1.0;
      if (activeBudgets.isEmpty && cycle != PlanCycle.monthly) {
        // A user can change cadence before copying the existing plan. Keep
        // the Dashboard useful immediately by deriving the current shorter
        // cycle from this month's allocations until the Plan screen saves
        // the new period explicitly.
        final monthlyPeriod = PlanCycle.monthly.keyFor(now);
        final monthlyBudgets = budgetRows
            .where(
              (b) =>
                  b.enabled &&
                  b.cycle == PlanCycle.monthly.storageValue &&
                  b.period == monthlyPeriod,
            )
            .toList();
        if (monthlyBudgets.isNotEmpty) {
          activeBudgets = monthlyBudgets;
          budgetScale = cycle.daysFor(now) / PlanCycle.monthly.daysFor(now);
        }
      }
      final limits = {
        for (final b in activeBudgets) b.category: b.monthlyLimit * budgetScale,
      };
      // Existing plans own their currency. Prefer it over the global
      // default so changing Settings cannot blank Budget Health by making
      // an older plan's USD rows look like foreign-currency transactions.
      final currency =
          activeBudgets.map((b) => b.currency).firstOrNull ??
          settings['plan_currency_$period'] ??
          settings['default_currency'] ??
          'USD';
      final byCategory = <String, double>{};
      final unconvertedTotals = <String, double>{};
      for (final t in rows.where(
        (t) => !t.timestamp.isBefore(start) && t.timestamp.isBefore(end),
      )) {
        if (t.currency != currency) {
          unconvertedTotals[t.currency] =
              (unconvertedTotals[t.currency] ?? 0) + t.amount;
          continue;
        }
        byCategory[t.category] = (byCategory[t.category] ?? 0) + t.amount;
      }
      final totalSpent = byCategory.values.fold(0.0, (a, b) => a + b);
      final totalLimit = limits.values.fold(0.0, (a, b) => a + b);
      yield BudgetSummary(
        totalSpent: totalSpent,
        totalLimit: totalLimit,
        currency: currency,
        cycle: cycle.storageValue,
        periodStart: start,
        periodEnd: end,
        byCategory: byCategory,
        byCategoryLimits: limits,
        unconvertedTotals: unconvertedTotals,
      );
    }
  } finally {
    await txSub.cancel();
    await bSub.cancel();
    await settingsSub.cancel();
    await events.close();
  }
});

final insightsProvider = Provider<AsyncValue<List<InsightCapsule>>>(
  (ref) => ref.watch(budgetSummaryProvider).whenData(generateInsights),
);

/// A six-month, chronological spending series for the Insights chart.
final spendingTrendProvider = Provider<List<MonthlySpendPoint>>((ref) {
  final transactions =
      ref.watch(transactionsStreamProvider).valueOrNull ?? const [];
  final currency =
      ref.watch(budgetSummaryProvider).valueOrNull?.currency ?? 'USD';
  return buildMonthlySpendingTrend(
    transactions: transactions
        .where((transaction) => transaction.currency == currency)
        .toList(),
  );
});
