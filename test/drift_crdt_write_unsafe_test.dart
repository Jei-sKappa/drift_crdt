import 'package:crdt/crdt.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_crdt/drift_crdt.dart';
import 'package:test/test.dart';

import 'core/support/support.dart';

void main() {
  group('DriftCrdt.writeUnsafe', () {
    late DriftCrdt<TestDatabase> userA;
    late DriftCrdt<TestDatabase> userB;

    setUp(() async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      userA = DriftCrdt<TestDatabase>(TestDatabase(
        DatabaseConnection(
          NativeDatabase.memory(),
          closeStreamsSynchronously: true,
        ),
      ));
      await userA.init('node-a');

      userB = DriftCrdt<TestDatabase>(TestDatabase(
        DatabaseConnection(
          NativeDatabase.memory(),
          closeStreamsSynchronously: true,
        ),
      ));
      await userB.init('node-b');

      // Fill the db with some todos to test the update and delete operations
      await fillDbWithSomeTodos(userA);
    });

    tearDown(() async {
      await userA.db.close();
      await userB.db.close();
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

    Future<int> unsafeRawUpsertWithCustomWhere(
      DriftCrdt<TestDatabase> crdt,
      Map<String, Object?> values,
    ) =>
        crdt.writeUnsafe((db, params, filters) async {
          final table = db.todos;

          // Build raw INSERT ... ON CONFLICT DO UPDATE using customHlcFilter
          final keys = values.keys.toList();
          final vals = values.values.toList();
          final placeholders =
              List.generate(vals.length, (i) => '?${i + 1}').join(', ');
          final columns = keys.join(', ');
          final updateClauses = keys
              .where((k) => k != 'id')
              .map((k) => '$k = excluded.$k')
              .join(', ');

          final sql = '''
INSERT INTO ${table.actualTableName} ($columns)
VALUES ($placeholders)
ON CONFLICT DO UPDATE SET $updateClauses WHERE ${filters.customHlcFilter(table.actualTableName)}
''';

          await db.customStatement(sql, vals);
          // customStatement returns void; return a dummy result for the API
          return (result: 0, affectedTables: [table.actualTableName]);
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

      await expectInsertIsCorrect(userA.db, userA.nodeId);
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

      await expectInsertIsCorrect(userA.db, userA.nodeId);
    });

    test('insertOnConflictUpdate correctly updates existing row', () async {
      await unsafeInsertTodo(userA, todo1);
      final row = await expectInsertIsCorrect(userA.db, userA.nodeId);

      await unsafeInsertOnConflictUpdateTodo(userA, todo1Updated);

      await expectUpdateIsCorrect(userA.db, userA.nodeId, row);
    });

    test(
      'insertOnConflictUpdate correctly updates existing row inserted by other '
      'node',
      () async {
        await unsafeInsertTodo(userA, todo1);
        final row = await expectInsertIsCorrect(userA.db, userA.nodeId);

        await userB.merge(await userA.getChangeset());

        await unsafeInsertOnConflictUpdateTodo(userB, todo1Updated);

        await expectUpdateIsCorrect(userB.db, userB.nodeId, row);
      },
    );

    test('insertOnConflictUpdate fails if hlc is older', () async {
      final row = await insertAndExpectTodoFromRemoteFuture(userA.db, userA);

      await unsafeInsertOnConflictUpdateTodo(userA, todo1Updated);

      await expectWriteFail(userA.db, row);
    });

    test('update correctly updates existing row', () async {
      await unsafeInsertTodo(userA, todo1);
      final row = await expectInsertIsCorrect(userA.db, userA.nodeId);

      final rowsWritten =
          await unsafeUpdateTodo(userA, todo1Updated.id.value, todo1Updated);
      expect(rowsWritten, 1);

      await expectUpdateIsCorrect(userA.db, userA.nodeId, row);
    });

    test(
      'update correctly updates existing row inserted by other node',
      () async {
        await unsafeInsertTodo(userA, todo1);
        final row = await expectInsertIsCorrect(userA.db, userA.nodeId);

        await userB.merge(await userA.getChangeset());

        final rowsWritten =
            await unsafeUpdateTodo(userB, todo1Updated.id.value, todo1Updated);
        expect(rowsWritten, 1);

        await expectUpdateIsCorrect(userB.db, userB.nodeId, row);
      },
    );

    test('update fails if row does not exist', () async {
      final rowsWritten =
          await unsafeUpdateTodo(userA, todo1Updated.id.value, todo1Updated);
      expect(rowsWritten, 0);
    });

    test('update fails if hlc is older', () async {
      final row = await insertAndExpectTodoFromRemoteFuture(userA.db, userA);

      final rowsWritten = await unsafeUpdateTodo(userA, row.id, todo1Updated);
      expect(rowsWritten, 0);

      await expectWriteFail(userA.db, row);
    });

    test('delete marks row as deleted', () async {
      await unsafeInsertTodo(userA, todo1);
      await expectInsertIsCorrect(userA.db, userA.nodeId);

      final rowsWritten = await unsafeDeleteTodo(userA, todo1.id.value);
      expect(rowsWritten, 1);

      await expectDeleteIsCorrect(userA.db);
    });

    test('delete fails if row does not exist', () async {
      final rowsWritten = await unsafeDeleteTodo(userA, todo1.id.value);
      expect(rowsWritten, 0);
    });

    test('delete update crdt columns if row is already deleted', () async {
      await unsafeInsertTodo(userA, todo1);
      await expectInsertIsCorrect(userA.db, userA.nodeId);

      await unsafeDeleteTodo(userA, todo1.id.value);

      final row = await expectDeleteIsCorrect(userA.db);

      final rowsWritten = await unsafeDeleteTodo(userA, todo1.id.value);
      expect(rowsWritten, 1);

      await expectDeleteJustUpdateCrdtColumns(userA.db, userA.nodeId, row);
    });

    test('delete fails if hlc is older', () async {
      final row = await insertAndExpectTodoFromRemoteFuture(userA.db, userA);

      final rowsWritten = await unsafeDeleteTodo(userA, row.id);
      expect(rowsWritten, 0);

      await expectWriteFail(userA.db, row);
    });

    test('customHlcFilter is used for raw upsert conflict clause', () async {
      // Seed a record
      await unsafeInsertTodo(userA, todo1);
      final existing = await expectInsertIsCorrect(userA.db, userA.nodeId);

      // Attempt to upsert with an older HLC using raw SQL path that relies on
      // customHlcFilter
      // First, create values map with older hlc than current canonical
      final older = Hlc(DateTime(1970), 0, 'old-node');
      final values = <String, Object?>{
        'id': existing.id,
        'title': 'older-title-ignored',
        'done': 1,
        'hlc': older.toString(),
        'node_id': older.nodeId,
        'modified': older.toString(),
        'is_deleted': 0,
      };

      await unsafeRawUpsertWithCustomWhere(userA, values);

      // Row should remain unchanged due to WHERE excluded.hlc > table.hlc
      final after = await (userA.db.select(userA.db.todos)
            ..where((t) => t.id.equals(existing.id)))
          .getSingle();
      expect(after.title, existing.title);
      expect(after.done, existing.done);
      expect(after.nodeId, existing.nodeId);
    });
  });
}
