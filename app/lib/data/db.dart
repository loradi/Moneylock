import 'package:drift/drift.dart';
import 'tables.dart';

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
}
