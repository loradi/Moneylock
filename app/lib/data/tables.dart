import 'package:drift/drift.dart';

class Transactions extends Table {
  IntColumn get id => integer().autoIncrement()();
  RealColumn get amount => real()();
  TextColumn get currency => text().withDefault(const Constant('USD'))();
  TextColumn get merchant => text().withDefault(const Constant(''))();
  TextColumn get category => text().withDefault(const Constant('Other'))();
  TextColumn get source => text()();
  TextColumn get rawText => text()();
  DateTimeColumn get timestamp => dateTime()();
  TextColumn get dedupHash => text().unique()();
}

class Budgets extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get category => text()();
  RealColumn get monthlyLimit => real()();
  TextColumn get period => text()(); // 'YYYY-MM'
  @override
  List<Set<Column>> get uniqueKeys => [{category, period}];
}

class MentorMessages extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get role => text()(); // 'user' | 'mentor'
  TextColumn get content => text()();
  DateTimeColumn get createdAt => dateTime()();
}

class AgentMemories extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get fact => text()();
  TextColumn get kind => text()();
  RealColumn get confidence => real()();
  DateTimeColumn get createdAt => dateTime()();
}

class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  @override
  Set<Column> get primaryKey => {key};
}
