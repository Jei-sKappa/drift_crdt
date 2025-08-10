import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_crdt/drift_crdt.dart';
import 'package:test/test.dart';

import 'core/support/support.dart';

void main() {
  group('DriftCrdt.writeUnsafe', () {
    late TestDatabase db;
    late DriftCrdt<TestDatabase> userA;
    late DriftCrdt<TestDatabase> userB;

    setUp(() async {
      db = TestDatabase(
        DatabaseConnection(
          NativeDatabase.memory(),
          closeStreamsSynchronously: true,
        ),
      );
      userA = DriftCrdt<TestDatabase>(db);
      await userA.init('node-a');

      userB = DriftCrdt<TestDatabase>(db);
      await userB.init('node-b');

      // Fill the db with some todos to test the update and delete operations
      await fillDbWithSomeTodos(userA);
    });

    tearDown(() async {
      await db.close();
    });

    Future<int> unsafeInsertTodo(
      DriftCrdt<TestDatabase> crdt,
      Insertable<Todo> todo,
    ) =>
        crdt.writeUnsafe((db, params, _) async {
          final table = db.todos;

          final res = await db.into(table).insert(todo.withParams(params));
          return (result: res, affectedTables: [table.actualTableName]);
        });

    Future<int> unsafeInsertOnConflictUpdateTodo(
      DriftCrdt<TestDatabase> crdt,
      Insertable<Todo> todo,
    ) =>
        crdt.writeUnsafe((db, params, filters) async {
          final table = db.todos;

          final todoWithParams = todo.withParams(params);

          final res = await db.into(table).insert(
                todoWithParams,
                onConflict: DoUpdate(
                  (_) => todoWithParams,
                  where: filters.hlcFilter,
                ),
              );
          return (result: res, affectedTables: [table.actualTableName]);
        });

    Future<int> unsafeUpdateTodo(
      DriftCrdt<TestDatabase> crdt,
      String id,
      Insertable<Todo> todo,
    ) =>
        crdt.writeUnsafe((db, params, filters) async {
          final table = db.todos;

          final todoWithParams = todo.withParams(params);

          final q = db.update(table)
            ..where((t) => t.id.equals(id))
            ..where(filters.hlcFilter);

          final res = await q.write(todoWithParams);

          return (result: res, affectedTables: [table.actualTableName]);
        });

    Future<int> unsafeDeleteTodo(
      DriftCrdt<TestDatabase> crdt,
      String id,
    ) =>
        crdt.writeUnsafe((db, params, filters) async {
          final table = db.todos;

          final q = db.update(table)
            ..where((t) => t.id.equals(id))
            ..where(filters.hlcFilter);

          final res = await q.write(
              const TodosCompanion(isDeleted: Value(true)).withParams(params));

          return (result: res, affectedTables: [table.actualTableName]);
        });

    test('insert correctly inserts new row', () async {
      await unsafeInsertTodo(userA, todo1);

      await expectInsertIsCorrect(db, userA.nodeId);
    });

    test('insert fails if row already exists', () async {
      await unsafeInsertTodo(userA, todo1);

      await expectLater(
        unsafeInsertTodo(
            userA, todo1.copyWith(title: const Value('something'))),
        throwsA(isA<SqliteException>()),
      );
    });

    test('insertOnConflictUpdate correctly inserts new row', () async {
      await unsafeInsertOnConflictUpdateTodo(userA, todo1);

      await expectInsertIsCorrect(db, userA.nodeId);
    });

    test('insertOnConflictUpdate correctly updates existing row', () async {
      await unsafeInsertTodo(userA, todo1);
      final row = await expectInsertIsCorrect(db, userA.nodeId);

      await unsafeInsertOnConflictUpdateTodo(userA, todo1Updated);

      await expectUpdateIsCorrect(db, userA.nodeId, row);
    });

    test(
      'insertOnConflictUpdate correctly updates existing row inserted by other '
      'node',
      () async {
        await unsafeInsertTodo(userA, todo1);
        final row = await expectInsertIsCorrect(db, userA.nodeId);

        await unsafeInsertOnConflictUpdateTodo(userB, todo1Updated);

        await expectUpdateIsCorrect(db, userB.nodeId, row);
      },
    );

    test('insertOnConflictUpdate fails if hlc is older', () async {
      final row = await insertAndExpectTodoFromRemoteFuture(db, userA);

      await unsafeInsertOnConflictUpdateTodo(userA, todo1Updated);

      await expectWriteFail(db, row);
    });

    test('update correctly updates existing row', () async {
      await unsafeInsertTodo(userA, todo1);
      final row = await expectInsertIsCorrect(db, userA.nodeId);

      final rowsWritten =
          await unsafeUpdateTodo(userA, todo1Updated.id.value, todo1Updated);
      expect(rowsWritten, 1);

      await expectUpdateIsCorrect(db, userA.nodeId, row);
    });

    test(
      'update correctly updates existing row inserted by other node',
      () async {
        await unsafeInsertTodo(userA, todo1);
        final row = await expectInsertIsCorrect(db, userA.nodeId);

        final rowsWritten =
            await unsafeUpdateTodo(userB, todo1Updated.id.value, todo1Updated);
        expect(rowsWritten, 1);

        await expectUpdateIsCorrect(db, userB.nodeId, row);
      },
    );

    test('update fails if row does not exist', () async {
      final rowsWritten =
          await unsafeUpdateTodo(userA, todo1Updated.id.value, todo1Updated);
      expect(rowsWritten, 0);
    });

    test('update fails if hlc is older', () async {
      final row = await insertAndExpectTodoFromRemoteFuture(db, userA);

      final rowsWritten = await unsafeUpdateTodo(userA, row.id, todo1Updated);
      expect(rowsWritten, 0);

      await expectWriteFail(db, row);
    });

    test('delete marks row as deleted', () async {
      await unsafeInsertTodo(userA, todo1);
      await expectInsertIsCorrect(db, userA.nodeId);

      final rowsWritten = await unsafeDeleteTodo(userA, todo1.id.value);
      expect(rowsWritten, 1);

      await expectDeleteIsCorrect(db);
    });

    test('delete fails if row does not exist', () async {
      final rowsWritten = await unsafeDeleteTodo(userA, todo1.id.value);
      expect(rowsWritten, 0);
    });

    test('delete update crdt columns if row is already deleted', () async {
      await unsafeInsertTodo(userA, todo1);
      await expectInsertIsCorrect(db, userA.nodeId);

      await unsafeDeleteTodo(userA, todo1.id.value);

      final row = await expectDeleteIsCorrect(db);

      final rowsWritten = await unsafeDeleteTodo(userA, todo1.id.value);
      expect(rowsWritten, 1);

      await expectDeleteJustUpdateCrdtColumns(db, userA.nodeId, row);
    });

    test('delete fails if hlc is older', () async {
      final row = await insertAndExpectTodoFromRemoteFuture(db, userA);

      final rowsWritten = await unsafeDeleteTodo(userA, row.id);
      expect(rowsWritten, 0);

      await expectWriteFail(db, row);
    });
  });
}
