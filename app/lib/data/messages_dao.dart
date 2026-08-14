import 'package:drift/drift.dart';
import 'db.dart';

class MessagesDao {
  final AppDatabase db;
  MessagesDao(this.db);

  Future<void> add(String role, String content) =>
      db.into(db.mentorMessages).insert(MentorMessagesCompanion.insert(
          role: role, content: content, createdAt: DateTime.now()));

  Stream<List<MentorMessage>> watchAll() {
    final q = db.select(db.mentorMessages)
      ..orderBy([(m) => OrderingTerm.asc(m.createdAt)]);
    return q.watch();
  }
}