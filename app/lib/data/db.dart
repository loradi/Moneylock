import 'package:drift/drift.dart';
import 'budgets_dao.dart';
import 'memories_dao.dart';
import 'messages_dao.dart';
import 'tables.dart';
import 'transactions_dao.dart';

part 'db.g.dart';

class SettingsDao {
  final AppDatabase db;
  SettingsDao(this.db);

  Future<String> mentorTone() async {
    final row = await (db.select(db.settings)
          ..where((s) => s.key.equals('mentor_tone')))
        .getSingleOrNull();
    return row?.value ?? 'strict_ramsey';
  }

  Future<void> setMentorTone(String tone) => db.into(db.settings)
      .insertOnConflictUpdate(SettingsCompanion.insert(key: 'mentor_tone', value: tone));
}

@DriftDatabase(tables: [
  Transactions,
  Budgets,
  MentorMessages,
  AgentMemories,
  Settings,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);
  AppDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 1;

  late final SettingsDao settingsDao = SettingsDao(this);
  late final TransactionsDao transactionsDao = TransactionsDao(this);
  late final BudgetsDao budgetsDao = BudgetsDao(this);
  late final MessagesDao messagesDao = MessagesDao(this);
  late final MemoriesDao memoriesDao = MemoriesDao(this);
}
