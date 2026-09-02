import 'package:drift/drift.dart';

import 'budgets_dao.dart';
import 'categories_dao.dart';
import 'memories_dao.dart';
import 'savings_goal.dart';
import 'messages_dao.dart';
import 'subscriptions_dao.dart';
import 'tables.dart';
import 'transactions_dao.dart';

part 'db.g.dart';

class SettingsDao {
  final AppDatabase db;
  SettingsDao(this.db);

  Future<String> mentorTone() async {
    final row = await (db.select(
      db.settings,
    )..where((s) => s.key.equals('mentor_tone'))).getSingleOrNull();
    return row?.value ?? 'strict_ramsey';
  }

  Future<void> setMentorTone(String tone) => db
      .into(db.settings)
      .insertOnConflictUpdate(
        SettingsCompanion.insert(key: 'mentor_tone', value: tone),
      );

  Future<bool> onboardingCompleted() async {
    final row = await (db.select(
      db.settings,
    )..where((s) => s.key.equals('onboarding_completed'))).getSingleOrNull();
    return row?.value == 'true';
  }

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

  Future<String> defaultCurrency() async {
    final row = await (db.select(
      db.settings,
    )..where((s) => s.key.equals('default_currency'))).getSingleOrNull();
    return row?.value ?? 'USD';
  }

  Future<void> setDefaultCurrency(String currency) => db
      .into(db.settings)
      .insertOnConflictUpdate(
        SettingsCompanion.insert(key: 'default_currency', value: currency),
      );

  Future<({String baseUrl, String legacyApiKey})> syncConfiguration() async {
    final rows =
        await (db.select(db.settings)..where(
              (setting) =>
                  setting.key.equals('sync_base_url') |
                  setting.key.equals('sync_api_key'),
            ))
            .get();
    final values = {for (final row in rows) row.key: row.value};
    return (
      baseUrl: values['sync_base_url'] ?? '',
      legacyApiKey: values['sync_api_key'] ?? '',
    );
  }

  Future<void> setSyncConfiguration({required String baseUrl}) => db
      .into(db.settings)
      .insertOnConflictUpdate(
        SettingsCompanion.insert(key: 'sync_base_url', value: baseUrl),
      );

  Future<void> clearLegacySyncApiKey() => (db.delete(
    db.settings,
  )..where((setting) => setting.key.equals('sync_api_key'))).go();

  Future<void> migrateLegacySyncApiKey(
    Future<void> Function(String apiKey) saveSecurely,
  ) async {
    final config = await syncConfiguration();
    if (config.legacyApiKey.isEmpty) return;
    await saveSecurely(config.legacyApiKey);
    await clearLegacySyncApiKey();
  }

  Future<SavingsGoal?> savingsGoal() async {
    final rows =
        await (db.select(db.settings)..where(
              (setting) =>
                  setting.key.equals('savings_goal_name') |
                  setting.key.equals('savings_goal_target') |
                  setting.key.equals('savings_goal_saved') |
                  setting.key.equals('savings_goal_currency'),
            ))
            .get();
    final values = {for (final row in rows) row.key: row.value};
    final name = values['savings_goal_name'];
    final target = double.tryParse(values['savings_goal_target'] ?? '');
    final saved = double.tryParse(values['savings_goal_saved'] ?? '') ?? 0;
    final currency = values['savings_goal_currency'];
    if (name == null ||
        name.trim().isEmpty ||
        target == null ||
        target <= 0 ||
        currency == null) {
      return null;
    }
    return SavingsGoal(
      name: name,
      targetAmount: target,
      savedAmount: saved.clamp(0, target).toDouble(),
      currency: currency,
    );
  }

  Future<void> setSavingsGoal(SavingsGoal goal) => db.transaction(() async {
    final values = {
      'savings_goal_name': goal.name.trim(),
      'savings_goal_target': goal.targetAmount.toStringAsFixed(2),
      'savings_goal_saved': goal.savedAmount.toStringAsFixed(2),
      'savings_goal_currency': goal.currency,
    };
    for (final entry in values.entries) {
      await db
          .into(db.settings)
          .insertOnConflictUpdate(
            SettingsCompanion.insert(key: entry.key, value: entry.value),
          );
    }
  });

  Future<void> clearSavingsGoal() => db.transaction(() async {
    for (final key in const [
      'savings_goal_name',
      'savings_goal_target',
      'savings_goal_saved',
      'savings_goal_currency',
    ]) {
      await (db.delete(
        db.settings,
      )..where((setting) => setting.key.equals(key))).go();
    }
  });

  Future<Map<String, String>> syncValues() async {
    final rows =
        await (db.select(db.settings)..where(
              (setting) =>
                  setting.key.equals('plan_cycle') |
                  setting.key.like('monthly_income_%') |
                  setting.key.like('plan_currency_%') |
                  setting.key.like('savings_goal_%'),
            ))
            .get();
    return {for (final row in rows) row.key: row.value};
  }

  Future<void> applySyncValues(Map<String, String> values) =>
      db.transaction(() async {
        for (final entry in values.entries) {
          final allowed =
              entry.key == 'plan_cycle' ||
              entry.key.startsWith('monthly_income_') ||
              entry.key.startsWith('plan_currency_') ||
              entry.key.startsWith('savings_goal_');
          if (!allowed) continue;
          await db
              .into(db.settings)
              .insertOnConflictUpdate(
                SettingsCompanion.insert(key: entry.key, value: entry.value),
              );
        }
      });

  Future<String> planCycle() async {
    final row = await (db.select(
      db.settings,
    )..where((s) => s.key.equals('plan_cycle'))).getSingleOrNull();
    return row?.value ?? 'monthly';
  }

  Future<void> setPlanCycle(String cycle) => db
      .into(db.settings)
      .insertOnConflictUpdate(
        SettingsCompanion.insert(key: 'plan_cycle', value: cycle),
      );

  Future<String?> planCurrency(String period) async {
    final row = await (db.select(
      db.settings,
    )..where((s) => s.key.equals('plan_currency_$period'))).getSingleOrNull();
    return row?.value;
  }

  Future<void> setPlanCurrency(String period, String currency) => db
      .into(db.settings)
      .insertOnConflictUpdate(
        SettingsCompanion.insert(key: 'plan_currency_$period', value: currency),
      );

  /// Income is deliberately stored per planning month: it is a private,
  /// user-declared planning input, not a claimed bank-account balance.
  Future<double?> monthlyIncome(String period) async {
    final row = await (db.select(
      db.settings,
    )..where((s) => s.key.equals('monthly_income_$period'))).getSingleOrNull();
    return row == null ? null : double.tryParse(row.value);
  }

  Future<void> setMonthlyIncome(String period, double income) => db
      .into(db.settings)
      .insertOnConflictUpdate(
        SettingsCompanion.insert(
          key: 'monthly_income_$period',
          value: income.toStringAsFixed(2),
        ),
      );

  Future<Set<String>> dismissedSubscriptionSuggestions() async {
    final row =
        await (db.select(
              db.settings,
            )..where((s) => s.key.equals('dismissed_subscription_suggestions')))
            .getSingleOrNull();
    if (row == null || row.value.isEmpty) return {};
    return row.value.split(',').toSet();
  }

  Future<void> dismissSubscriptionSuggestion(String merchant) async {
    final current = await dismissedSubscriptionSuggestions();
    final updated = {...current, merchant.trim().toLowerCase()};
    await db
        .into(db.settings)
        .insertOnConflictUpdate(
          SettingsCompanion.insert(
            key: 'dismissed_subscription_suggestions',
            value: updated.join(','),
          ),
        );
  }

  Future<void> completeOnboarding() => db
      .into(db.settings)
      .insertOnConflictUpdate(
        SettingsCompanion.insert(key: 'onboarding_completed', value: 'true'),
      );
}

@DriftDatabase(
  tables: [
    Transactions,
    Budgets,
    Categories,
    MentorMessages,
    AgentMemories,
    Settings,
    Subscriptions,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);
  AppDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 7;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      for (final name in defaultCategoryNames) {
        await into(categories).insert(
          CategoriesCompanion.insert(name: name, isDefault: const Value(true)),
        );
      }
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.addColumn(mentorMessages, mentorMessages.severity);
      }
      if (from < 3) {
        await m.createTable(categories);
        await m.addColumn(budgets, budgets.cycle);
        await m.addColumn(budgets, budgets.cycleDays);
        await m.addColumn(budgets, budgets.currency);
        await m.addColumn(budgets, budgets.enabled);
      }
      if (from < 4) {
        await categoriesDao.ensureDefaults();
      }
      if (from < 5) {
        await m.createTable(subscriptions);
      }
      if (from < 6) {
        await m.addColumn(mentorMessages, mentorMessages.kind);
        await m.addColumn(mentorMessages, mentorMessages.dataJson);
      }
      if (from >= 5 && from < 7) {
        await m.addColumn(subscriptions, subscriptions.isActive);
      }
    },
  );

  late final SettingsDao settingsDao = SettingsDao(this);
  late final TransactionsDao transactionsDao = TransactionsDao(this);
  late final BudgetsDao budgetsDao = BudgetsDao(this);
  late final CategoriesDao categoriesDao = CategoriesDao(this);
  late final MessagesDao messagesDao = MessagesDao(this);
  late final MemoriesDao memoriesDao = MemoriesDao(this);
  late final SubscriptionsDao subscriptionsDao = SubscriptionsDao(this);
}
