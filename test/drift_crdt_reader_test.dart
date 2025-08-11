import 'package:crdt/crdt.dart';
import 'package:drift/drift.dart' show DatabaseConnection, Value;
import 'package:drift/native.dart';
import 'package:drift_crdt/drift_crdt.dart';
import 'package:test/test.dart';

import 'core/support/support.dart';

void main() {
  group('DriftCrdtReader', () {
    late TestDatabase db;
    late DriftCrdt<TestDatabase> crdt;

    setUp(() async {
      db = TestDatabase(
        DatabaseConnection(
          NativeDatabase.memory(),
          closeStreamsSynchronously: true,
        ),
      );
      crdt = DriftCrdt(db);
      await crdt.init('reader-node');

      await fillDbWithSomeTodos(crdt);
    });

    tearDown(() async {
      await db.close();
    });

    test('select works correctly', () async {
      await crdt.write((w) => w.insert(crdt.db.todos, todo1));

      final rows = await crdt.select(crdt.db.todos);
      expect(rows.length, 11);

      final todo1Row = rows.firstWhere((r) => r.id == todo1.id.value);
      expect(todo1Row.title, todo1.title.value);
      expect(todo1Row.done, todo1.done.value);
      expect(todo1Row.hlc, todo1Row.hlc);
      expect(Hlc.parse(todo1Row.hlc).nodeId, todo1Row.nodeId);
      expect(todo1Row.isDeleted, false);
    });

    test('select correcly returns one row using where', () async {
      await crdt.write((w) => w.insert(crdt.db.todos, todo1));

      final rows = await crdt.select(crdt.db.todos,
          where: (t) => [t.id.equals(todo1.id.value)]);
      expect(rows.length, 1);

      final todo1Row = rows.first;
      expect(todo1Row.title, todo1.title.value);
      expect(todo1Row.done, todo1.done.value);
      expect(todo1Row.hlc, todo1Row.hlc);
      expect(Hlc.parse(todo1Row.hlc).nodeId, todo1Row.nodeId);
      expect(todo1Row.isDeleted, false);
    });

    test('selectSingle works correctly', () async {
      await crdt.write((w) => w.insert(crdt.db.todos, todo1));

      final row = await crdt.selectSingle(crdt.db.todos,
          where: (t) => [t.id.equals(todo1.id.value)]);

      expect(row.title, todo1.title.value);
      expect(row.done, todo1.done.value);
      expect(row.hlc, row.hlc);
      expect(Hlc.parse(row.hlc).nodeId, row.nodeId);
      expect(row.isDeleted, false);
    });

    test('selectSingleOrNull works correctly', () async {
      await crdt.write((w) => w.insert(crdt.db.todos, todo1));

      final row = await crdt.selectSingleOrNull(crdt.db.todos,
          where: (t) => [t.id.equals(todo1.id.value)]);

      expect(row, isNot(null));

      row!;

      expect(row.title, todo1.title.value);
      expect(row.done, todo1.done.value);
      expect(row.hlc, row.hlc);
      expect(Hlc.parse(row.hlc).nodeId, row.nodeId);
      expect(row.isDeleted, false);
    });

    test('selectSingleOrNull works correctly when no row is found', () async {
      final row = await crdt.selectSingleOrNull(crdt.db.todos,
          where: (t) => [t.id.equals(todo1.id.value)]);

      expect(row, isNull);
    });

    test('watch works correctly', () async {
      await crdt.write((w) => w.insert(crdt.db.todos, todo1));

      final stream = crdt.watch(crdt.db.todos);

      // Listen to the first emission
      final initialRows = await stream.first;
      expect(initialRows.length, 11); // 10 from fillDbWithSomeTodos + 1 new

      final todo1Row = initialRows.firstWhere((r) => r.id == todo1.id.value);
      expect(todo1Row.title, todo1.title.value);
      expect(todo1Row.done, todo1.done.value);
      expect(todo1Row.isDeleted, false);
    });

    test('watch correctly returns filtered rows using where', () async {
      await crdt.write((w) => w.insert(crdt.db.todos, todo1));

      final stream = crdt.watch(crdt.db.todos,
          where: (t) => [t.id.equals(todo1.id.value)]);

      final rows = await stream.first;
      expect(rows.length, 1);

      final todo1Row = rows.first;
      expect(todo1Row.title, todo1.title.value);
      expect(todo1Row.done, todo1.done.value);
      expect(todo1Row.isDeleted, false);
    });

    test('watch stream updates when data changes', () async {
      await crdt.write((w) => w.insert(crdt.db.todos, todo1));

      final stream = crdt.watch(crdt.db.todos,
          where: (t) => [t.id.equals(todo1.id.value)]);

      // Collect stream emissions
      final emissions = <List<Todo>>[];
      final subscription = stream.listen(emissions.add);

      // Wait for initial emission
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(emissions.length, 1);
      expect(emissions[0].length, 1);
      expect(emissions[0][0].title, todo1.title.value);

      // Update the todo
      const updatedTitle = 'Updated title';
      await crdt.write((w) => w.update(
          crdt.db.todos, todo1.copyWith(title: const Value(updatedTitle)),
          where: whereTodo1Id));

      // Wait for update emission
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(emissions.length, 2);
      expect(emissions[1].length, 1);
      expect(emissions[1][0].title, updatedTitle);

      await subscription.cancel();
    });

    test('watchSingle works correctly', () async {
      await crdt.write((w) => w.insert(crdt.db.todos, todo1));

      final stream = crdt.watchSingle(crdt.db.todos,
          where: (t) => [t.id.equals(todo1.id.value)]);

      final row = await stream.first;
      expect(row.title, todo1.title.value);
      expect(row.done, todo1.done.value);
      expect(row.isDeleted, false);
    });

    test('watchSingle stream updates when data changes', () async {
      await crdt.write((w) => w.insert(crdt.db.todos, todo1));

      final stream = crdt.watchSingle(crdt.db.todos,
          where: (t) => [t.id.equals(todo1.id.value)]);

      // Collect stream emissions
      final emissions = <Todo>[];
      final subscription = stream.listen(emissions.add);

      // Wait for initial emission
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(emissions.length, 1);
      expect(emissions[0].title, todo1.title.value);

      // Update the todo
      const updatedTitle = 'Updated title';
      await crdt.write((w) => w.update(
          crdt.db.todos, todo1.copyWith(title: const Value(updatedTitle)),
          where: whereTodo1Id));

      // Wait for update emission
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(emissions.length, 2);
      expect(emissions[1].title, updatedTitle);

      await subscription.cancel();
    });

    test('watchSingleOrNull works correctly', () async {
      await crdt.write((w) => w.insert(crdt.db.todos, todo1));

      final stream = crdt.watchSingleOrNull(crdt.db.todos,
          where: (t) => [t.id.equals(todo1.id.value)]);

      final row = await stream.first;
      expect(row, isNot(null));

      row!;
      expect(row.title, todo1.title.value);
      expect(row.done, todo1.done.value);
      expect(row.isDeleted, false);
    });

    test('watchSingleOrNull works correctly when no row is found', () async {
      final stream = crdt.watchSingleOrNull(crdt.db.todos,
          where: (t) => [t.id.equals(todo1.id.value)]);

      final row = await stream.first;
      expect(row, isNull);
    });

    test('watchSingleOrNull stream updates when data changes', () async {
      await crdt.write((w) => w.insert(crdt.db.todos, todo1));

      final stream = crdt.watchSingleOrNull(crdt.db.todos,
          where: (t) => [t.id.equals(todo1.id.value)]);

      // Collect stream emissions
      final emissions = <Todo?>[];
      final subscription = stream.listen(emissions.add);

      // Wait for initial emission
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(emissions.length, 1);
      expect(emissions[0], isNot(null));
      expect(emissions[0]!.title, todo1.title.value);

      // Update the todo
      const updatedTitle = 'Updated title';
      await crdt.write((w) => w.update(
          crdt.db.todos, todo1.copyWith(title: const Value(updatedTitle)),
          where: whereTodo1Id));

      // Wait for update emission
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(emissions.length, 2);
      expect(emissions[1], isNot(null));
      expect(emissions[1]!.title, updatedTitle);

      await subscription.cancel();
    });

    test('watchSingleOrNull stream emits null when row is deleted', () async {
      await crdt.write((w) => w.insert(crdt.db.todos, todo1));

      final stream = crdt.watchSingleOrNull(crdt.db.todos,
          where: (t) => [t.id.equals(todo1.id.value)]);

      // Collect stream emissions
      final emissions = <Todo?>[];
      final subscription = stream.listen(emissions.add);

      // Wait for initial emission
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(emissions.length, 1);
      expect(emissions[0], isNot(null));

      // Delete the todo
      await crdt.write((w) => w.delete(crdt.db.todos, where: whereTodo1Id));

      // Wait for deletion emission
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(emissions.length, 2);
      expect(emissions[1], isNull);

      await subscription.cancel();
    });
  });
}
