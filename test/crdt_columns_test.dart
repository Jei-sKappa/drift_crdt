import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_crdt/drift_crdt.dart';
import 'package:test/test.dart';

import 'core/support/test_db.dart';

void main() {
  group('CrdtColumns', () {
    late DriftCrdt<TestDatabase> crdt;

    setUp(() async {
      crdt = DriftCrdt(TestDatabase(
        DatabaseConnection(
          NativeDatabase.memory(),
          closeStreamsSynchronously: true,
        ),
      ));
      await crdt.init();
    });

    tearDown(() async {
      await crdt.db.close();
    });

    test('columns exist with defaults and can insert/read', () async {
      final res = await crdt.write(
        (w) => w.insert(
          crdt.db.todos,
          const TodosCompanion(
            id: Value('x'),
            title: Value('t'),
            // done has default false
          ),
        ),
      );
      expect(res, isNonZero);

      final row = await crdt.selectSingle(crdt.db.todos,
          where: (t) => [t.id.equals('x')]);

      // Table has CRDT columns (backed by mixin) even without CRDT adapter
      expect(row.id, 'x');
      expect(row.title, 't');
      expect(row.done, isFalse);
      // Values will be null/empty as we didn't set them, but columns exist
      // Just ensure they are present and readable
      expect(() => row.hlc, returnsNormally);
      expect(() => row.nodeId, returnsNormally);
      expect(() => row.modified, returnsNormally);
      expect(() => row.isDeleted, returnsNormally);
    });
  });
}
