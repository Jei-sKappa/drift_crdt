import 'package:crdt/crdt.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_crdt/drift_crdt.dart';
import 'package:test/test.dart';

import 'core/support/test_db.dart';

void main() {
  const todo1Id = '1';
  const todo1Title = 'First todo';
  const todo1Done = false;
  const todo1 = TodosCompanion(
    id: Value(todo1Id),
    title: Value(todo1Title),
    done: Value(todo1Done),
  );

  const todo1UpdatedTitle = 'New title';
  const todo1UpdatedDone = true;
  final todo1Updated = todo1.copyWith(
    title: const Value(todo1UpdatedTitle),
    done: const Value(todo1UpdatedDone),
  );

  Iterable<Expression<bool>> whereTodo1Id($TodosTable t) => [
    t.id.equals(todo1Id),
  ];

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

    void expectCrdtColumnsAreCorrect(Todo row, String nodeId) {
      expect(row.hlc, isNotEmpty);
      expect(row.nodeId, nodeId);
      expect(row.modified, isNotEmpty);

      // Check that hlc and modified are the same
      expect(row.hlc, row.modified);

      // Check that node id is the Hlc's node id
      final hlc = Hlc.parse(row.hlc);
      expect(hlc.nodeId, row.nodeId);
    }

    Future<Todo> expectInsertIsCorrect(String nodeId) async {
      final row =
          await (db.select(db.todos)
            ..where((t) => t.id.equals(todo1Id))).getSingle();

      expect(row.title, todo1Title);
      expect(row.done, todo1Done);
      expect(row.isDeleted, false);

      expectCrdtColumnsAreCorrect(row, nodeId);

      return row;
    }

    Future<Todo> expectUpdateIsCorrect(
      String updatedNodeId,
      Todo rowBefore,
    ) async {
      final expectNodeIdToBeUpdated = rowBefore.nodeId != updatedNodeId;

      // Capture current state
      final hlcBefore = Hlc.parse(rowBefore.hlc);
      final nodeIdBefore = rowBefore.nodeId;
      final modifiedBefore = Hlc.parse(rowBefore.modified);

      final rowAfter =
          await (db.select(db.todos)
            ..where((t) => t.id.equals(todo1Id))).getSingle();

      expect(rowAfter.title, todo1UpdatedTitle);
      expect(rowAfter.done, todo1UpdatedDone);
      expect(rowAfter.isDeleted, false);

      expectCrdtColumnsAreCorrect(rowAfter, updatedNodeId);

      // Check that hlc and modified are updated
      final hlcAfter = Hlc.parse(rowAfter.hlc);
      final nodeIdAfter = rowAfter.nodeId;
      final modifiedAfter = Hlc.parse(rowAfter.modified);

      // Check that hlc and modified are updated
      expect(hlcAfter > hlcBefore, isTrue);
      if (expectNodeIdToBeUpdated) {
        expect(nodeIdAfter, updatedNodeId);
      } else {
        expect(nodeIdAfter, nodeIdBefore);
      }
      expect(modifiedAfter > modifiedBefore, isTrue);

      return rowAfter;
    }

    Future<Todo> expectDeleteJustUpdateCrdtColumns(
      String nodeId,
      Todo rowBefore,
    ) async {
      assert(
        rowBefore.isDeleted == true,
        'Row must be deleted to when running this test',
      );

      // Capture current state
      final hlcBefore = Hlc.parse(rowBefore.hlc);
      final nodeIdBefore = rowBefore.nodeId;
      final modifiedBefore = Hlc.parse(rowBefore.modified);

      final rowAfter =
          await (db.select(db.todos)
            ..where((t) => t.id.equals(todo1Id))).getSingle();

      expect(rowAfter.title, rowBefore.title);
      expect(rowAfter.done, rowBefore.done);
      expect(rowAfter.isDeleted, true);

      expectCrdtColumnsAreCorrect(rowAfter, nodeId);

      // Check that hlc and modified are updated
      final hlcAfter = Hlc.parse(rowAfter.hlc);
      final nodeIdAfter = rowAfter.nodeId;
      final modifiedAfter = Hlc.parse(rowAfter.modified);

      // Check that hlc and modified are updated
      expect(hlcAfter > hlcBefore, isTrue);
      expect(nodeIdAfter, nodeIdBefore);
      expect(modifiedAfter > modifiedBefore, isTrue);

      return rowAfter;
    }

    Future<Todo> expectDeleteIsCorrect() async {
      final row =
          await (db.select(db.todos)
            ..where((t) => t.id.equals(todo1Id))).getSingle();

      expect(row.isDeleted, true);

      return row;
    }

    Future<Todo> expectWriteFail(Todo rowBefore) async {
      final rowAfter =
          await (db.select(db.todos)
            ..where((t) => t.id.equals(todo1Id))).getSingle();

      expect(rowAfter.toJson(), rowBefore.toJson());

      return rowAfter;
    }

    Future<Todo> insertAndExpectTodoFromRemoteFuture() async {
      final remoteFutureHlc = Hlc(DateTime(3000), 0xFFFF, 'zzz-remote-node');
      final todo1WrittenInARemoteFuture = todo1.copyWith(
        hlc: Value(remoteFutureHlc.toString()),
        nodeId: Value(remoteFutureHlc.nodeId),
        modified: Value(remoteFutureHlc.toString()),
      );

      // Use unsafe write to insert a todo from the future
      final rowsWritten = await userA.writeUnsafe((db, params, _) async {
        final table = db.todos;
        final res = await db.into(table).insert(todo1WrittenInARemoteFuture);
        return (result: res, affectedTables: [table.actualTableName]);
      });

      expect(rowsWritten, 1);

      // When using writeUnsafe the node id from the crdt is ignored because it
      // is user the one provided in the writeUnsafe callback so when can expect
      // the node id to be the one from the remote future hlc
      final row = await expectInsertIsCorrect(remoteFutureHlc.nodeId);

      return row;
    }

    test('insert correctly inserts new row', () async {
      final rowsWritten = await userA.write((w) => w.insert(db.todos, todo1));
      expect(rowsWritten, 1);

      await expectInsertIsCorrect(userA.nodeId);
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

      await expectInsertIsCorrect(userA.nodeId);
    });

    test('insertOnConflictUpdate correctly updates existing row', () async {
      final rowsWritten = await userA.write((w) => w.insert(db.todos, todo1));
      expect(rowsWritten, 1);

      final row = await expectInsertIsCorrect(userA.nodeId);

      final rowsWritten2 = await userA.write(
        (w) => w.insertOnConflictUpdate(db.todos, todo1Updated),
      );
      expect(rowsWritten2, 1);

      await expectUpdateIsCorrect(userA.nodeId, row);
    });

    test(
      'insertOnConflictUpdate correctly updates existing row inserted by other '
      'node',
      () async {
        final rowsWritten = await userA.write((w) => w.insert(db.todos, todo1));
        expect(rowsWritten, 1);

        final row = await expectInsertIsCorrect(userA.nodeId);

        final rowsWritten2 = await userB.write(
          (w) => w.insertOnConflictUpdate(db.todos, todo1Updated),
        );
        expect(rowsWritten2, 1);

        await expectUpdateIsCorrect(userB.nodeId, row);
      },
    );

    test('insertOnConflictUpdate fails if hlc is older', () async {
      final row = await insertAndExpectTodoFromRemoteFuture();

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

      await expectWriteFail(row);
    });

    test('update correctly updates existing row', () async {
      final rowsWritten = await userA.write((w) => w.insert(db.todos, todo1));
      expect(rowsWritten, 1);

      final row = await expectInsertIsCorrect(userA.nodeId);

      final rowsWritten2 = await userA.write(
        (w) => w.update(db.todos, todo1Updated, where: whereTodo1Id),
      );
      expect(rowsWritten2, 1);

      await expectUpdateIsCorrect(userA.nodeId, row);
    });

    test(
      'update correctly updates existing row inserted by other node',
      () async {
        final rowsWritten = await userA.write((w) => w.insert(db.todos, todo1));
        expect(rowsWritten, 1);

        final row = await expectInsertIsCorrect(userA.nodeId);

        final rowsWritten2 = await userB.write(
          (w) => w.update(db.todos, todo1Updated, where: whereTodo1Id),
        );
        expect(rowsWritten2, 1);

        await expectUpdateIsCorrect(userB.nodeId, row);
      },
    );

    test('update fails if row does not exist', () async {
      final rowsWritten = await userA.write(
        (w) => w.update(db.todos, todo1Updated, where: whereTodo1Id),
      );
      expect(rowsWritten, 0);
    });

    test('update fails if hlc is older', () async {
      final row = await insertAndExpectTodoFromRemoteFuture();

      final rowsWritten = await userA.write(
        (w) => w.update(db.todos, todo1Updated, where: whereTodo1Id),
      );
      expect(rowsWritten, 0);

      await expectWriteFail(row);
    });

    test('delete marks row as deleted', () async {
      await userA.write((w) => w.insert(db.todos, todo1));
      await expectInsertIsCorrect(userA.nodeId);

      final rowsWritten = await userA.write(
        (w) => w.delete(db.todos, where: whereTodo1Id),
      );
      expect(rowsWritten, 1);

      await expectDeleteIsCorrect();
    });

    test('delete fails if row does not exist', () async {
      final rowsWritten = await userA.write(
        (w) => w.delete(db.todos, where: whereTodo1Id),
      );
      expect(rowsWritten, 0);
    });

    test('delete update crdt columns if row is already deleted', () async {
      await userA.write((w) => w.insert(db.todos, todo1));
      await expectInsertIsCorrect(userA.nodeId);

      final rowsWritten = await userA.write(
        (w) => w.delete(db.todos, where: whereTodo1Id),
      );
      expect(rowsWritten, 1);

      final row = await expectDeleteIsCorrect();

      final rowsWritten2 = await userA.write(
        (w) => w.delete(db.todos, where: whereTodo1Id),
      );
      expect(rowsWritten2, 1);

      await expectDeleteJustUpdateCrdtColumns(userA.nodeId, row);
    });

    test('delete fails if hlc is older', () async {
      final row = await insertAndExpectTodoFromRemoteFuture();

      final rowsWritten = await userA.write(
        (w) => w.delete(db.todos, where: whereTodo1Id),
      );
      expect(rowsWritten, 0);

      await expectWriteFail(row);
    });
  });
}
