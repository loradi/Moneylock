import 'db.dart';

class MemoriesDao {
  final AppDatabase db;
  MemoriesDao(this.db);

  Future<void> add(String fact, String kind, double confidence) =>
      db.into(db.agentMemories).insert(AgentMemoriesCompanion.insert(
          fact: fact, kind: kind, confidence: confidence, createdAt: DateTime.now()));
}