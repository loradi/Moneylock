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
  TextColumn get cycle => text().withDefault(const Constant('monthly'))();
  IntColumn get cycleDays => integer().withDefault(const Constant(30))();
  TextColumn get currency => text().withDefault(const Constant('USD'))();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  @override
  List<Set<Column>> get uniqueKeys => [
    {category, period},
  ];
}

class Categories extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().unique()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  BoolColumn get isDefault => boolean().withDefault(const Constant(false))();
}

class MentorMessages extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get role => text()(); // 'user' | 'mentor'
  TextColumn get content => text()();
  DateTimeColumn get createdAt => dateTime()();
  TextColumn get severity => text().withDefault(const Constant('info'))();
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

class Subscriptions extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get brandKey => text().nullable()();
  RealColumn get amount => real()();
  TextColumn get currency => text().withDefault(const Constant('USD'))();
  TextColumn get cycle => text()(); // 'monthly' | 'yearly'
  DateTimeColumn get nextChargeDate => dateTime()();
  TextColumn get source => text().withDefault(const Constant('manual'))(); // 'manual' | 'suggested'
  DateTimeColumn get createdAt => dateTime()();
}
