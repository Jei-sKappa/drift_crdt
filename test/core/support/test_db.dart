import 'package:drift/drift.dart';
import 'package:drift_crdt/drift_crdt.dart';

part 'test_db.g.dart';

class Todos extends Table with CrdtColumns {
  TextColumn get id => text()();
  TextColumn get title => text()();
  BoolColumn get done => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [Todos])
class TestDatabase extends _$TestDatabase {
  TestDatabase(super.e);

  @override
  int get schemaVersion => 1;
}
