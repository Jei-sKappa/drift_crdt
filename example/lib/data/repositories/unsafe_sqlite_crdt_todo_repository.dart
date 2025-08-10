import 'package:drift/drift.dart';
import 'package:drift_crdt/drift_crdt.dart';
import 'package:example/core/utils/uuid.dart';
import 'package:example/data/data.dart';

class UnsafeSqliteCrdtTodoRepository extends SqliteCrdtTodoRepository {
  UnsafeSqliteCrdtTodoRepository(super.crdt);

  @override
  Future<void> add(String title) async {
    await crdt.writeUnsafe((db, params, _) async {
      final table = db.todos;

      final res = await db
          .into(table)
          .insertOnConflictUpdate(
            TodosCompanion(
              id: Value(uuid.v4()),
              title: Value(title),
            ).withParams(params),
          );

      return (result: res, affectedTables: [table.actualTableName]);
    });
  }

  @override
  Future<void> toggleDone(String id) async {
    await crdt.writeUnsafe((db, params, filters) async {
      final table = db.todos;

      return db.transaction(() async {
        final row =
            await (db.select(db.todos)
              ..where((t) => t.id.equals(id))).getSingleOrNull();

        if (row == null) return (result: null, affectedTables: null);

        final query =
            db.update(table)
              ..where((t) => t.id.equals(id))
              ..where(filters.hlcFilter);

        final res = await query.write(
          TodosCompanion(done: Value(!row.done)).withParams(params),
        );

        return (result: res, affectedTables: [table.actualTableName]);
      });
    });
  }

  @override
  Future<void> delete(String id) async {
    await crdt.writeUnsafe((db, params, filters) async {
      final table = db.todos;

      final query =
          db.update(table)
            ..where((t) => t.id.equals(id))
            ..where(filters.hlcFilter);

      final res = await query.write(
        const TodosCompanion(isDeleted: Value(true)).withParams(params),
      );

      return (result: res, affectedTables: [table.actualTableName]);
    });
  }
}
