import 'package:drift/drift.dart';
import 'db.dart';

class MessagesDao {
  final AppDatabase db;
  MessagesDao(this.db);

  Future<void> add(
    String role,
    String content, {
    String severity = 'info',
    String kind = 'text',
    String? dataJson,
  }) =>
      db.into(db.mentorMessages).insert(MentorMessagesCompanion.insert(
          role: role,
          content: content,
          createdAt: DateTime.now(),
          severity: Value(severity),
          kind: Value(kind),
          dataJson: Value(dataJson),
      ));

  Stream<List<MentorMessage>> watchAll() {
    final q = db.select(db.mentorMessages)
      ..orderBy([(m) => OrderingTerm.asc(m.createdAt)]);
    return q.watch();
  }

  Future<List<MentorMessage>> recent(int limit) async {
    final rows = await (db.select(db.mentorMessages)
          ..orderBy([
            (m) => OrderingTerm.desc(m.createdAt),
            (m) => OrderingTerm.desc(m.id),
          ])
          ..limit(limit))
        .get();
    return rows.reversed.toList();
  }
}
