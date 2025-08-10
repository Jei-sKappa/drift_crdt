import 'package:crdt/crdt.dart';
import 'package:drift/drift.dart';
import 'package:drift_crdt/drift_crdt.dart';
import 'package:test/test.dart';

import 'test_db.dart';

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
final TodosCompanion todo1Updated = todo1.copyWith(
  title: const Value(todo1UpdatedTitle),
  done: const Value(todo1UpdatedDone),
);

Iterable<Expression<bool>> whereTodo1Id($TodosTable t) => [
      t.id.equals(todo1Id),
    ];

void expectCrdtColumnsAreCorrect(TestDatabase db, Todo row, String nodeId) {
  expect(row.hlc, isNotEmpty);
  expect(row.nodeId, nodeId);
  expect(row.modified, isNotEmpty);

  // Check that hlc and modified are the same
  expect(row.hlc, row.modified);

  // Check that node id is the Hlc's node id
  final hlc = Hlc.parse(row.hlc);
  expect(hlc.nodeId, row.nodeId);
}

Future<Todo> expectInsertIsCorrect(TestDatabase db, String nodeId) async {
  final row = await (db.select(db.todos)..where((t) => t.id.equals(todo1Id)))
      .getSingle();

  expect(row.title, todo1Title);
  expect(row.done, todo1Done);
  expect(row.isDeleted, false);

  expectCrdtColumnsAreCorrect(db, row, nodeId);

  return row;
}

Future<Todo> expectUpdateIsCorrect(
  TestDatabase db,
  String updatedNodeId,
  Todo rowBefore,
) async {
  final expectNodeIdToBeUpdated = rowBefore.nodeId != updatedNodeId;

  // Capture current state
  final hlcBefore = Hlc.parse(rowBefore.hlc);
  final nodeIdBefore = rowBefore.nodeId;
  final modifiedBefore = Hlc.parse(rowBefore.modified);

  final rowAfter = await (db.select(db.todos)
        ..where((t) => t.id.equals(todo1Id)))
      .getSingle();

  expect(rowAfter.title, todo1UpdatedTitle);
  expect(rowAfter.done, todo1UpdatedDone);
  expect(rowAfter.isDeleted, false);

  expectCrdtColumnsAreCorrect(db, rowAfter, updatedNodeId);

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
  TestDatabase db,
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

  final rowAfter = await (db.select(db.todos)
        ..where((t) => t.id.equals(todo1Id)))
      .getSingle();

  expect(rowAfter.title, rowBefore.title);
  expect(rowAfter.done, rowBefore.done);
  expect(rowAfter.isDeleted, true);

  expectCrdtColumnsAreCorrect(db, rowAfter, nodeId);

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

Future<Todo> expectDeleteIsCorrect(TestDatabase db) async {
  final row = await (db.select(db.todos)..where((t) => t.id.equals(todo1Id)))
      .getSingle();

  expect(row.isDeleted, true);

  return row;
}

Future<Todo> expectWriteFail(TestDatabase db, Todo rowBefore) async {
  final rowAfter = await (db.select(db.todos)
        ..where((t) => t.id.equals(todo1Id)))
      .getSingle();

  expect(rowAfter.toJson(), rowBefore.toJson());

  return rowAfter;
}

Future<Todo> insertAndExpectTodoFromRemoteFuture(
    TestDatabase db, DriftCrdt<TestDatabase> crdt) async {
  final remoteFutureHlc = Hlc(DateTime(3000), 0xFFFF, 'zzz-remote-node');
  final todo1WrittenInARemoteFuture = todo1.copyWith(
    hlc: Value(remoteFutureHlc.toString()),
    nodeId: Value(remoteFutureHlc.nodeId),
    modified: Value(remoteFutureHlc.toString()),
  );

  // Use unsafe write to insert a todo from the future
  final rowsWritten = await crdt.writeUnsafe((db, params, _) async {
    final table = db.todos;
    final res = await db.into(table).insert(todo1WrittenInARemoteFuture);
    return (result: res, affectedTables: [table.actualTableName]);
  });

  expect(rowsWritten, 1);

  // When using writeUnsafe the node id from the crdt is ignored because it
  // is user the one provided in the writeUnsafe callback so when can expect
  // the node id to be the one from the remote future hlc
  final row = await expectInsertIsCorrect(db, remoteFutureHlc.nodeId);

  return row;
}
