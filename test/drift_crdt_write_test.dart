import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_crdt/drift_crdt.dart';
import 'package:test/test.dart';

import 'core/support/support.dart';

void main() {
  group('DriftCrdt.write', () {
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

    test('insert correctly inserts new row', () async {
      await userA.write((w) => w.insert(userA.db.todos, todo1));

      await expectInsertIsCorrect(userA.db, userA.nodeId);
    });

    test('insert fails if row already exists', () async {
      await userA.write((w) => w.insert(userA.db.todos, todo1));

      await expectLater(
        userA.write(
          (w) => w.insert(
            userA.db.todos,
            todo1.copyWith(title: const Value('something')),
          ),
        ),
        throwsA(isA<SqliteException>()),
      );
    });

    test('insertOnConflictUpdate correctly inserts new row', () async {
      await userA.write(
        (w) => w.insertOnConflictUpdate(userA.db.todos, todo1),
      );

      await expectInsertIsCorrect(userA.db, userA.nodeId);
    });

    test('insertOnConflictUpdate correctly updates existing row', () async {
      await userA.write((w) => w.insert(userA.db.todos, todo1));
      final row = await expectInsertIsCorrect(userA.db, userA.nodeId);

      await userA.write(
        (w) => w.insertOnConflictUpdate(userA.db.todos, todo1Updated),
      );

      await expectUpdateIsCorrect(userA.db, userA.nodeId, row);
    });

    test(
      'insertOnConflictUpdate correctly updates existing row inserted by other '
      'node',
      () async {
        await userA.write((w) => w.insert(userA.db.todos, todo1));
        final row = await expectInsertIsCorrect(userA.db, userA.nodeId);

        await userB.merge(await userA.getChangeset());

        await userB.write(
          (w) => w.insertOnConflictUpdate(userB.db.todos, todo1Updated),
        );

        await expectUpdateIsCorrect(userB.db, userB.nodeId, row);
      },
    );

    test('insertOnConflictUpdate fails if hlc is older', () async {
      final row = await insertAndExpectTodoFromRemoteFuture(userA.db, userA);

      await userA.write(
        (w) => w.insertOnConflictUpdate(userA.db.todos, todo1Updated),
      );

      await expectWriteFail(userA.db, row);
    });

    test('update correctly updates existing row', () async {
      await userA.write((w) => w.insert(userA.db.todos, todo1));
      final row = await expectInsertIsCorrect(userA.db, userA.nodeId);

      final rowsWritten = await userA.write(
        (w) => w.update(userA.db.todos, todo1Updated, where: whereTodo1Id),
      );
      expect(rowsWritten, 1);

      await expectUpdateIsCorrect(userA.db, userA.nodeId, row);
    });

    test(
      'update correctly updates existing row inserted by other node',
      () async {
        await userA.write((w) => w.insert(userA.db.todos, todo1));
        final row = await expectInsertIsCorrect(userA.db, userA.nodeId);

        await userB.merge(await userA.getChangeset());

        final rowsWritten = await userB.write(
          (w) => w.update(userB.db.todos, todo1Updated, where: whereTodo1Id),
        );
        expect(rowsWritten, 1);

        await expectUpdateIsCorrect(userB.db, userB.nodeId, row);
      },
    );

    test('update fails if row does not exist', () async {
      final rowsWritten = await userA.write(
        (w) => w.update(userA.db.todos, todo1Updated, where: whereTodo1Id),
      );
      expect(rowsWritten, 0);
    });

    test('update fails if hlc is older', () async {
      final row = await insertAndExpectTodoFromRemoteFuture(userA.db, userA);

      final rowsWritten = await userA.write(
        (w) => w.update(userA.db.todos, todo1Updated, where: whereTodo1Id),
      );
      expect(rowsWritten, 0);

      await expectWriteFail(userA.db, row);
    });

    test('delete marks row as deleted', () async {
      await userA.write((w) => w.insert(userA.db.todos, todo1));
      await expectInsertIsCorrect(userA.db, userA.nodeId);

      final rowsWritten = await userA.write(
        (w) => w.delete(userA.db.todos, where: whereTodo1Id),
      );
      expect(rowsWritten, 1);

      await expectDeleteIsCorrect(userA.db);
    });

    test('delete fails if row does not exist', () async {
      final rowsWritten = await userA.write(
        (w) => w.delete(userA.db.todos, where: whereTodo1Id),
      );
      expect(rowsWritten, 0);
    });

    test('delete update crdt columns if row is already deleted', () async {
      await userA.write((w) => w.insert(userA.db.todos, todo1));
      await expectInsertIsCorrect(userA.db, userA.nodeId);

      await userA.write((w) => w.delete(userA.db.todos, where: whereTodo1Id));

      final row = await expectDeleteIsCorrect(userA.db);

      final rowsWritten = await userA.write(
        (w) => w.delete(userA.db.todos, where: whereTodo1Id),
      );
      expect(rowsWritten, 1);

      await expectDeleteJustUpdateCrdtColumns(userA.db, userA.nodeId, row);
    });

    test('delete fails if hlc is older', () async {
      final row = await insertAndExpectTodoFromRemoteFuture(userA.db, userA);

      final rowsWritten = await userA.write(
        (w) => w.delete(userA.db.todos, where: whereTodo1Id),
      );
      expect(rowsWritten, 0);

      await expectWriteFail(userA.db, row);
    });
  });
}
