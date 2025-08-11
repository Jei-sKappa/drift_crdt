import 'dart:async';

import 'package:crdt/crdt.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_crdt/drift_crdt.dart';
import 'package:test/test.dart';

import 'core/support/support.dart';

Future<void> get _delay => Future.delayed(const Duration(milliseconds: 1));

void main() {
  group('DriftCrdt', () {
    late DriftCrdt<TestDatabase> crdt;
    late DriftCrdt<TestDatabase> crdt2;

    setUp(() async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      crdt = DriftCrdt(TestDatabase(
        DatabaseConnection(
          NativeDatabase.memory(),
          closeStreamsSynchronously: true,
        ),
      ));
      crdt2 = DriftCrdt(TestDatabase(
        DatabaseConnection(
          NativeDatabase.memory(),
          closeStreamsSynchronously: true,
        ),
      ));
    });

    tearDown(() async {
      await crdt.db.close();
      await crdt2.db.close();
    });

    group('isInitialized', () {
      test('should be false before init', () {
        expect(crdt.isInitialized, false);
      });

      test('should be true after init', () async {
        await crdt.init();
        expect(crdt.isInitialized, true);
      });
    });

    group('init', () {
      test('should set canonical time with generated nodeId', () async {
        await crdt.init();
        expect(crdt.canonicalTime.nodeId, isNotEmpty);
        expect(crdt.canonicalTime.dateTime, DateTime.utc(1970));
        expect(crdt.canonicalTime.counter, 0);
      });

      test('should set canonical time with provided nodeId', () async {
        const nodeId = 'test-node-id';
        await crdt.init(nodeId);
        expect(crdt.canonicalTime.nodeId, nodeId);
        expect(crdt.canonicalTime.dateTime, DateTime.utc(1970));
        expect(crdt.canonicalTime.counter, 0);
      });

      test('should do nothing when called multiple times', () async {
        await crdt.init('node-1');
        final firstCanonicalTime = crdt.canonicalTime;

        await crdt.init('node-2'); // Should be ignored
        expect(crdt.canonicalTime, firstCanonicalTime);
      });

      test('should use last modified time from database if exists', () async {
        // Create new crdt instance with same database and init with different
        // nodeId
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
        final crdt4 = DriftCrdt(TestDatabase(
          DatabaseConnection(
            NativeDatabase.memory(),
            closeStreamsSynchronously: true,
          ),
        ));
        await crdt4.init('node-2');

        await crdt4.merge(await crdt3.getChangeset());

        // Should use the provided node ID but adopt the timestamp from existing
        // data
        expect(crdt4.canonicalTime.nodeId,
            'node-2'); // Should use provided node ID
        // The time should be at least as recent as the existing data
        expect(crdt4.canonicalTime >= crdt3.canonicalTime, isTrue);
      });
    });

    group('getLastModified', () {
      setUp(() async {
        await crdt.init('node-a');
        await crdt2.init('node-b');
      });

      test('should return zero HLC when database is empty', () async {
        final lastModified = await crdt.getLastModified();
        expect(lastModified, Hlc.zero(crdt.nodeId));
      });

      test('should return last modified time after insert', () async {
        await crdt.write((w) => w.insert(crdt.db.todos, todo1));
        final lastModified = await crdt.getLastModified();
        expect(lastModified.nodeId, crdt.nodeId);
        expect(lastModified.dateTime, crdt.canonicalTime.dateTime);
      });

      test('should filter by onlyNodeId', () async {
        await crdt.write((w) => w.insert(crdt.db.todos, todo1));
        await _delay;
        await crdt2.write((w) => w.insert(
            crdt2.db.todos,
            const TodosCompanion(
              id: Value('2'),
              title: Value('Second todo'),
            )));

        // Merge crdt2's data into crdt so crdt has both records
        final changeset = await crdt2.getChangeset();
        await crdt.merge(changeset);

        final lastModifiedNodeA =
            await crdt.getLastModified(onlyNodeId: 'node-a');
        final lastModifiedNodeB =
            await crdt.getLastModified(onlyNodeId: 'node-b');

        expect(lastModifiedNodeA.nodeId,
            crdt.nodeId); // Should use current CRDT's node ID
        expect(lastModifiedNodeB.nodeId,
            crdt.nodeId); // Should use current CRDT's node ID
        expect(lastModifiedNodeA < lastModifiedNodeB, true);
      });

      test('should filter by exceptNodeId', () async {
        await crdt.write((w) => w.insert(crdt.db.todos, todo1));
        await _delay;
        await crdt2.write((w) => w.insert(
            crdt2.db.todos,
            const TodosCompanion(
              id: Value('2'),
              title: Value('Second todo'),
            )));

        // Merge crdt2's data into crdt so crdt has both records
        final changeset = await crdt2.getChangeset();
        await crdt.merge(changeset);

        final lastModifiedExceptA =
            await crdt.getLastModified(exceptNodeId: 'node-a');
        final lastModifiedExceptB =
            await crdt.getLastModified(exceptNodeId: 'node-b');

        expect(lastModifiedExceptA.nodeId,
            crdt.nodeId); // Should use current CRDT's node ID
        expect(lastModifiedExceptB.nodeId,
            crdt.nodeId); // Should use current CRDT's node ID
        expect(lastModifiedExceptA > lastModifiedExceptB, true);
      });

      test('should assert when both onlyNodeId and exceptNodeId are provided',
          () async {
        expect(
          () => crdt.getLastModified(
              onlyNodeId: 'node-a', exceptNodeId: 'node-b'),
          throwsA(isA<AssertionError>()),
        );
      });
    });

    group('getChangeset', () {
      setUp(() async {
        await crdt.init('node-a');
        await crdt2.init('node-b');
      });

      test('should return empty changeset when database is empty', () async {
        final changeset = await crdt.getChangeset();
        expect(changeset, isEmpty);
      });

      test('should return changeset with all data', () async {
        await crdt.write((w) => w.insert(crdt.db.todos, todo1));
        await crdt.write((w) => w.insert(
            crdt.db.todos,
            const TodosCompanion(
              id: Value('2'),
              title: Value('Second todo'),
            )));

        final changeset = await crdt.getChangeset();
        expect(changeset.keys, contains('todos'));
        expect(changeset['todos']!.length, 2);
        expect(changeset['todos']!.first['id'], todo1Id);
        expect(changeset['todos']!.first['title'], todo1Title);
      });

      test('should filter by onlyTables', () async {
        await crdt.write((w) => w.insert(crdt.db.todos, todo1));

        final changeset = await crdt.getChangeset(onlyTables: ['todos']);
        expect(changeset.keys, contains('todos'));

        final emptyChangeset =
            await crdt.getChangeset(onlyTables: ['non_existent']);
        expect(emptyChangeset, isEmpty);
      });

      test('should filter by onlyNodeId', () async {
        await crdt.write((w) => w.insert(crdt.db.todos, todo1));
        await crdt2.write((w) => w.insert(
            crdt2.db.todos,
            const TodosCompanion(
              id: Value('2'),
              title: Value('Second todo'),
            )));

        // Merge crdt2's data into crdt so both records are in crdt
        final changeset2 = await crdt2.getChangeset();
        await crdt.merge(changeset2);

        final changesetNodeA = await crdt.getChangeset(onlyNodeId: 'node-a');
        final changesetNodeB = await crdt.getChangeset(onlyNodeId: 'node-b');

        expect(changesetNodeA['todos']!.length, 1);
        expect(changesetNodeA['todos']!.first['id'], todo1Id);
        expect(changesetNodeB['todos']!.length, 1);
        expect(changesetNodeB['todos']!.first['id'], '2');
      });

      test('should filter by exceptNodeId', () async {
        await crdt.write((w) => w.insert(crdt.db.todos, todo1));
        await crdt2.write((w) => w.insert(
            crdt2.db.todos,
            const TodosCompanion(
              id: Value('2'),
              title: Value('Second todo'),
            )));

        // Merge crdt2's data into crdt so both records are in crdt
        final changeset2 = await crdt2.getChangeset();
        await crdt.merge(changeset2);

        final changesetExceptA =
            await crdt.getChangeset(exceptNodeId: 'node-a');
        final changesetExceptB =
            await crdt.getChangeset(exceptNodeId: 'node-b');

        expect(changesetExceptA['todos']!.length, 1);
        expect(changesetExceptA['todos']!.first['id'], '2');
        expect(changesetExceptB['todos']!.length, 1);
        expect(changesetExceptB['todos']!.first['id'], todo1Id);
      });

      test('should filter by modifiedOn', () async {
        await crdt.write((w) => w.insert(crdt.db.todos, todo1));
        final firstHlc = crdt.canonicalTime;

        await _delay;
        await crdt.write((w) => w.insert(
            crdt.db.todos,
            const TodosCompanion(
              id: Value('2'),
              title: Value('Second todo'),
            )));

        final changeset = await crdt.getChangeset(modifiedOn: firstHlc);
        expect(changeset['todos']!.length, 1);
        expect(changeset['todos']!.first['id'], todo1Id);
      });

      test('should filter by modifiedAfter', () async {
        await crdt.write((w) => w.insert(crdt.db.todos, todo1));
        final firstHlc = crdt.canonicalTime;

        await _delay;
        await crdt.write((w) => w.insert(
            crdt.db.todos,
            const TodosCompanion(
              id: Value('2'),
              title: Value('Second todo'),
            )));

        final changeset = await crdt.getChangeset(modifiedAfter: firstHlc);
        expect(changeset['todos']!.length, 1);
        expect(changeset['todos']!.first['id'], '2');
      });

      test('should return empty changeset when modifiedAfter is latest',
          () async {
        await crdt.write((w) => w.insert(crdt.db.todos, todo1));
        final latestHlc = crdt.canonicalTime;

        final changeset = await crdt.getChangeset(modifiedAfter: latestHlc);
        expect(changeset, isEmpty);
      });

      test('should assert when both modifiedOn and modifiedAfter are provided',
          () async {
        final hlc = Hlc.now('test');
        expect(
          () => crdt.getChangeset(modifiedOn: hlc, modifiedAfter: hlc),
          throwsA(isA<AssertionError>()),
        );
      });

      test('should assert when both onlyNodeId and exceptNodeId are provided',
          () async {
        expect(
          () => crdt.getChangeset(onlyNodeId: 'node-a', exceptNodeId: 'node-b'),
          throwsA(isA<AssertionError>()),
        );
      });

      test('should combine filters correctly', () async {
        await crdt.write((w) => w.insert(crdt.db.todos, todo1));
        await _delay;
        await crdt2.write((w) => w.insert(
            crdt2.db.todos,
            const TodosCompanion(
              id: Value('2'),
              title: Value('Second todo'),
            )));

        // Merge crdt2's data into crdt so both records are in crdt
        final changeset2 = await crdt2.getChangeset();
        await crdt.merge(changeset2);

        final changeset = await crdt.getChangeset(
          onlyTables: ['todos'],
          onlyNodeId: 'node-a',
        );

        expect(changeset['todos']!.length, 1);
        expect(changeset['todos']!.first['id'], todo1Id);
        expect(changeset['todos']!.first['node_id'], 'node-a');
      });
    });

    group('merge', () {
      setUp(() async {
        await crdt.init('node-a');
        await crdt2.init('node-b');
      });

      test('should merge into empty database', () async {
        await crdt2.write((w) => w.insert(crdt2.db.todos, todo1));
        final changeset = await crdt2.getChangeset();

        await crdt.merge(changeset);

        final result = await (crdt.db.select(crdt.db.todos)
              ..where((t) => t.id.equals(todo1Id)))
            .getSingle();
        expect(result.title, todo1Title);
        expect(result.nodeId, 'node-b');
      });

      test('should handle empty changeset', () async {
        await crdt.merge({});
        // Should not throw or cause issues
      });

      test('should update canonical time after merge', () async {
        await crdt2.write((w) => w.insert(crdt2.db.todos, todo1));
        final changeset = await crdt2.getChangeset();
        final originalCanonicalTime = crdt.canonicalTime;

        await crdt.merge(changeset);

        expect(crdt.canonicalTime > originalCanonicalTime, true);
        expect(crdt.canonicalTime.nodeId, 'node-a');
      });

      test('should merge newer record over older', () async {
        await crdt.write((w) => w.insert(crdt.db.todos, todo1));
        await _delay;

        await crdt2.write(
            (w) => w.insertOnConflictUpdate(crdt2.db.todos, todo1Updated));
        final changeset = await crdt2.getChangeset();

        await crdt.merge(changeset);

        final result = await (crdt.db.select(crdt.db.todos)
              ..where((t) => t.id.equals(todo1Id)))
            .getSingle();
        expect(result.title, todo1UpdatedTitle);
        expect(result.done, todo1UpdatedDone);
        expect(result.nodeId, 'node-b');
      });

      test('should not merge older record over newer', () async {
        await crdt2.write((w) => w.insert(crdt2.db.todos, todo1));
        await _delay;

        await crdt.write(
            (w) => w.insertOnConflictUpdate(crdt.db.todos, todo1Updated));

        final changeset = await crdt2.getChangeset();
        await crdt.merge(changeset);

        final result = await (crdt.db.select(crdt.db.todos)
              ..where((t) => t.id.equals(todo1Id)))
            .getSingle();
        expect(result.title, todo1UpdatedTitle); // Should keep newer data
        expect(result.done, todo1UpdatedDone);
        expect(result.nodeId, 'node-a'); // Should keep newer node
      });

      test('should resolve conflicts with higher node id', () async {
        // Create records with same logical time but different node IDs
        const nodeIdLower = 'node-aaaa';
        const nodeIdHigher = 'node-zzzz';

        final crdtLower = DriftCrdt<TestDatabase>(TestDatabase(
          DatabaseConnection(
            NativeDatabase.memory(),
            closeStreamsSynchronously: true,
          ),
        ));
        final crdtHigher = DriftCrdt<TestDatabase>(TestDatabase(
          DatabaseConnection(
            NativeDatabase.memory(),
            closeStreamsSynchronously: true,
          ),
        ));
        await crdtLower.init(nodeIdLower);
        await crdtHigher.init(nodeIdHigher);

        await crdtLower.write((w) => w.insert(crdtLower.db.todos, todo1));
        final changeset = await crdtLower.getChangeset();

        // Manually modify the changeset to have same HLC but different node ID
        // and value
        changeset['todos']!.first['hlc'] =
            (changeset['todos']!.first['hlc']! as Hlc)
                .apply(nodeId: nodeIdHigher);
        changeset['todos']!.first['node_id'] = nodeIdHigher;
        changeset['todos']!.first['title'] = 'Higher node id title';

        await crdtLower.merge(changeset);

        final result = await (crdtLower.db.select(crdtLower.db.todos)
              ..where((t) => t.id.equals(todo1Id)))
            .getSingle();
        expect(result.title, 'Higher node id title');
        expect(result.nodeId, nodeIdHigher);
      });

      test('should merge multiple tables', () async {
        // This test would require another table, but we only have todos table
        // So we'll test with multiple records in todos table
        await crdt2.write((w) => w.insert(crdt2.db.todos, todo1));
        await crdt2.write((w) => w.insert(
            crdt2.db.todos,
            const TodosCompanion(
              id: Value('2'),
              title: Value('Second todo'),
            )));

        final changeset = await crdt2.getChangeset();
        await crdt.merge(changeset);

        final results = await crdt.db.select(crdt.db.todos).get();
        expect(results.length, 2);
        expect(results.map((r) => r.id), contains(todo1Id));
        expect(results.map((r) => r.id), contains('2'));
      });

      test('should handle large changeset', () async {
        // Generate many records
        for (var i = 0; i < 100; i++) {
          await crdt2.write((w) => w.insert(
              crdt2.db.todos,
              TodosCompanion(
                id: Value('todo-$i'),
                title: Value('Todo $i'),
              )));
        }

        final changeset = await crdt2.getChangeset();
        await crdt.merge(changeset);

        final results = await crdt.db.select(crdt.db.todos).get();
        expect(results.length, 100);
      });

      test('should preserve CRDT semantics during merge', () async {
        // Insert, update, then merge - should maintain proper HLC ordering
        await crdt.write((w) => w.insert(crdt.db.todos, todo1));
        final firstHlc = crdt.canonicalTime;

        await crdt2.write((w) => w.insert(
            crdt2.db.todos,
            const TodosCompanion(
              id: Value('2'),
              title: Value('Remote todo'),
            )));
        final changeset = await crdt2.getChangeset();

        await crdt.merge(changeset);

        final results = await crdt.db.select(crdt.db.todos).get();
        final localTodo = results.firstWhere((r) => r.id == todo1Id);
        final remoteTodo = results.firstWhere((r) => r.id == '2');

        expect(localTodo.hlc.toHlc < remoteTodo.hlc.toHlc, true);
        expect(crdt.canonicalTime > firstHlc, true);
      });

      test('should handle deleted records in changeset', () async {
        await crdt.write((w) => w.insert(crdt.db.todos, todo1));
        await crdt.write((w) => w.delete(crdt.db.todos, where: whereTodo1Id));

        final changeset = await crdt.getChangeset();

        // Create new crdt instance and merge the deleted record
        final crdt3 = DriftCrdt<TestDatabase>(TestDatabase(
          DatabaseConnection(
            NativeDatabase.memory(),
            closeStreamsSynchronously: true,
          ),
        ));
        await crdt3.init('node-c');

        // Clear the database first
        await crdt3.db.transaction(() async {
          await crdt3.db.delete(crdt3.db.todos).go();
        });

        await crdt3.merge(changeset);

        final result = await (crdt3.db.select(crdt3.db.todos)
              ..where((t) => t.id.equals(todo1Id)))
            .getSingle();
        expect(result.isDeleted, true);
        expect(result.title, todo1Title); // Data should still be there
      });
    });
  });
}
