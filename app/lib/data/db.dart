import 'package:drift/drift.dart';

import 'budgets_dao.dart';
import 'categories_dao.dart';
import 'memories_dao.dart';
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

  Future<Set<String>> dismissedSubscriptionSuggestions() async {
    final row = await (db.select(
      db.settings,
    )..where((s) => s.key.equals('dismissed_subscription_suggestions'))).getSingleOrNull();
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

  Future<void> completeOnboarding({
    required String usedPlanner,
    required String shoppingHabits,
  }) async {
    await db.batch((batch) {
      batch.insert(
        db.settings,
        SettingsCompanion.insert(
          key: 'onboarding_used_planner',
          value: usedPlanner,
        ),
        mode: InsertMode.insertOrReplace,
      );
      batch.insert(
        db.settings,
        SettingsCompanion.insert(
          key: 'onboarding_shopping_habits',
          value: shoppingHabits,
        ),
        mode: InsertMode.insertOrReplace,
      );
      batch.insert(
        db.settings,
        SettingsCompanion.insert(key: 'onboarding_completed', value: 'true'),
        mode: InsertMode.insertOrReplace,
      );
    });
  }
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
  int get schemaVersion => 6;

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
