import 'package:drift/drift.dart';

import 'budgets_dao.dart';
import 'categories_dao.dart';
import 'memories_dao.dart';
import 'messages_dao.dart';
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
}

@DriftDatabase(
  tables: [
    Transactions,
    Budgets,
    Categories,
    MentorMessages,
    AgentMemories,
    Settings,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);
  AppDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
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
    },
  );

  late final SettingsDao settingsDao = SettingsDao(this);
  late final TransactionsDao transactionsDao = TransactionsDao(this);
  late final BudgetsDao budgetsDao = BudgetsDao(this);
  late final CategoriesDao categoriesDao = CategoriesDao(this);
  late final MessagesDao messagesDao = MessagesDao(this);
  late final MemoriesDao memoriesDao = MemoriesDao(this);
}
