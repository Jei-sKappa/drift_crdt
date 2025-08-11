//
// ignore_for_file: avoid_print

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_crdt/drift_crdt.dart';

import 'test/core/support/support.dart';

void main() async {
  final db1 = TestDatabase(
    DatabaseConnection(
      NativeDatabase.memory(),
      closeStreamsSynchronously: true,
    ),
  );
  final db2 = TestDatabase(
    DatabaseConnection(
      NativeDatabase.memory(),
      closeStreamsSynchronously: true,
    ),
  );
  final crdt = DriftCrdt(db1);
  await crdt.init('88e042d1-60c2-4e6a-a540-7bcef7dda869');
  final crdt1 = DriftCrdt(db2);
  await crdt1.init('6a0c03c7-fe9e-49b2-be71-28a51774b1df');

  // Add data to both CRDTs
  await crdt.write((w) => w.insert(
      crdt.db.todos, const TodosCompanion(id: Value('x'), title: Value('1'))));
  await Future<void>.delayed(const Duration(milliseconds: 1));
  await crdt1.write((w) => w.insert(
      crdt1.db.todos, const TodosCompanion(id: Value('y'), title: Value('1'))));

  // Merge crdt1s changes into crdt
  await crdt.merge(await crdt1.getChangeset());

  print('crdt.nodeId: ${crdt.nodeId}');
  print('crdt1.nodeId: ${crdt1.nodeId}');
  print('crdt1.canonicalTime: ${crdt1.canonicalTime}');
  print('crdt1.canonicalTime.apply(nodeId: crdt.nodeId): '
      '${crdt1.canonicalTime.apply(nodeId: crdt.nodeId)}');

  final lastModified = await crdt.getLastModified(onlyNodeId: crdt1.nodeId);
  print('crdt.getLastModified(onlyNodeId: crdt1.nodeId): $lastModified');

  print('Are they equal? '
      '${lastModified == crdt1.canonicalTime.apply(nodeId: crdt.nodeId)}');

  //
  // Create new crdt instance with same database and init with different nodeId
  final crdt3 = DriftCrdt(TestDatabase(
    DatabaseConnection(
      NativeDatabase.memory(),
      closeStreamsSynchronously: true,
    ),
  ));

  // Add the same data to crdt3's database to simulate existing data
  await crdt3.init('node-1');
  await crdt3.write((w) => w.insert(crdt3.db.todos, todo1));

  // Now create crdt4 and init with different nodeId - should use provided
  // nodeId
  // final crdt4 = DriftCrdt(crdt3.db);
  // await crdt4.init('node-2');
  final crdt4 = DriftCrdt(TestDatabase(
    DatabaseConnection(
      NativeDatabase.memory(),
      closeStreamsSynchronously: true,
    ),
  ));
  await crdt4.init('node-2');
  await crdt4.merge(await crdt3.getChangeset());

  // Should use the provided node ID but adopt the timestamp from existing data
  // expect(crdt4.canonicalTime.nodeId, 'node-2'); // Should use provided node ID
  print('crdt3.canonicalTime: ${crdt3.canonicalTime}');
  print('crdt4.canonicalTime: ${crdt4.canonicalTime}');

  print('Is crdt4.canonicalTime.nodeId == node-2? '
      '${crdt4.canonicalTime.nodeId == 'node-2'}');
  // The time should be at least as recent as the existing data
  // expect(crdt4.canonicalTime >= crdt3.canonicalTime, isTrue);
  print('Is crdt4.canonicalTime >= crdt3.canonicalTime? '
      '${crdt4.canonicalTime >= crdt3.canonicalTime}');
}
