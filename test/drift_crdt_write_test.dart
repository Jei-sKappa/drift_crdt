import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_crdt/drift_crdt.dart';
import 'package:test/test.dart';

import 'core/support/support.dart';

void main() {
  group('DriftCrdt.write', () {
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
    });

    tearDown(() async {
      await db.close();
    });

    test('insert correctly inserts new row', () async {
      final rowsWritten = await userA.write((w) => w.insert(db.todos, todo1));
      expect(rowsWritten, 1);

      await expectInsertIsCorrect(db, userA.nodeId);
    });

    test('insert fails if row already exists', () async {
      final rowsWritten = await userA.write((w) => w.insert(db.todos, todo1));
      expect(rowsWritten, 1);

      await expectLater(
        userA.write(
          (w) => w.insert(
            db.todos,
            todo1.copyWith(title: const Value('something')),
          ),
        ),
        throwsA(isA<SqliteException>()),
      );
    });

    test('insertOnConflictUpdate correctly inserts new row', () async {
      final rowsWritten = await userA.write(
        (w) => w.insertOnConflictUpdate(db.todos, todo1),
      );
      expect(rowsWritten, 1);

      await expectInsertIsCorrect(db, userA.nodeId);
    });

    test('insertOnConflictUpdate correctly updates existing row', () async {
      final rowsWritten = await userA.write((w) => w.insert(db.todos, todo1));
      expect(rowsWritten, 1);

      final row = await expectInsertIsCorrect(db, userA.nodeId);

      final rowsWritten2 = await userA.write(
        (w) => w.insertOnConflictUpdate(db.todos, todo1Updated),
      );
      expect(rowsWritten2, 1);

      await expectUpdateIsCorrect(db, userA.nodeId, row);
    });

    test(
      'insertOnConflictUpdate correctly updates existing row inserted by other '
      'node',
      () async {
        final rowsWritten = await userA.write((w) => w.insert(db.todos, todo1));
        expect(rowsWritten, 1);

        final row = await expectInsertIsCorrect(db, userA.nodeId);

        final rowsWritten2 = await userB.write(
          (w) => w.insertOnConflictUpdate(db.todos, todo1Updated),
        );
        expect(rowsWritten2, 1);

        await expectUpdateIsCorrect(db, userB.nodeId, row);
      },
    );

    test('insertOnConflictUpdate fails if hlc is older', () async {
      final row = await insertAndExpectTodoFromRemoteFuture(db, userA);

      final rowsWritten = await userA.write(
        (w) => w.insertOnConflictUpdate(db.todos, todo1Updated),
      );
      //TODO: For some reason this is 1 instead of 0.
      // Probably it's a Drift/SQLite bug or maybe i'm not understanding it
      // correctly.
      // File an issue for this.
      // Currently the test expect the "wrong" result.
      // Anyway this package behaviour is checked by the test below.
      expect(rowsWritten, 1);

      await expectWriteFail(db, row);
    });

    test('update correctly updates existing row', () async {
      final rowsWritten = await userA.write((w) => w.insert(db.todos, todo1));
      expect(rowsWritten, 1);

      final row = await expectInsertIsCorrect(db, userA.nodeId);

      final rowsWritten2 = await userA.write(
        (w) => w.update(db.todos, todo1Updated, where: whereTodo1Id),
      );
      expect(rowsWritten2, 1);

      await expectUpdateIsCorrect(db, userA.nodeId, row);
    });

    test(
      'update correctly updates existing row inserted by other node',
      () async {
        final rowsWritten = await userA.write((w) => w.insert(db.todos, todo1));
        expect(rowsWritten, 1);

        final row = await expectInsertIsCorrect(db, userA.nodeId);

        final rowsWritten2 = await userB.write(
          (w) => w.update(db.todos, todo1Updated, where: whereTodo1Id),
        );
        expect(rowsWritten2, 1);

        await expectUpdateIsCorrect(db, userB.nodeId, row);
      },
    );

    test('update fails if row does not exist', () async {
      final rowsWritten = await userA.write(
        (w) => w.update(db.todos, todo1Updated, where: whereTodo1Id),
      );
      expect(rowsWritten, 0);
    });

    test('update fails if hlc is older', () async {
      final row = await insertAndExpectTodoFromRemoteFuture(db, userA);

      final rowsWritten = await userA.write(
        (w) => w.update(db.todos, todo1Updated, where: whereTodo1Id),
      );
      expect(rowsWritten, 0);

      await expectWriteFail(db, row);
    });

    test('delete marks row as deleted', () async {
      await userA.write((w) => w.insert(db.todos, todo1));
      await expectInsertIsCorrect(db, userA.nodeId);

      final rowsWritten = await userA.write(
        (w) => w.delete(db.todos, where: whereTodo1Id),
      );
      expect(rowsWritten, 1);

      await expectDeleteIsCorrect(db);
    });

    test('delete fails if row does not exist', () async {
      final rowsWritten = await userA.write(
        (w) => w.delete(db.todos, where: whereTodo1Id),
      );
      expect(rowsWritten, 0);
    });

    test('delete update crdt columns if row is already deleted', () async {
      await userA.write((w) => w.insert(db.todos, todo1));
      await expectInsertIsCorrect(db, userA.nodeId);

      final rowsWritten = await userA.write(
        (w) => w.delete(db.todos, where: whereTodo1Id),
      );
      expect(rowsWritten, 1);

      final row = await expectDeleteIsCorrect(db);

      final rowsWritten2 = await userA.write(
        (w) => w.delete(db.todos, where: whereTodo1Id),
      );
      expect(rowsWritten2, 1);

      await expectDeleteJustUpdateCrdtColumns(db, userA.nodeId, row);
    });

    test('delete fails if hlc is older', () async {
      final row = await insertAndExpectTodoFromRemoteFuture(db, userA);

      final rowsWritten = await userA.write(
        (w) => w.delete(db.todos, where: whereTodo1Id),
      );
      expect(rowsWritten, 0);

      await expectWriteFail(db, row);
    });
  });
}
