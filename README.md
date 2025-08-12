## Drift CRDT

[![Drift CRDT CI](https://github.com/Jei-sKappa/drift_crdt/actions/workflows/dart_package.yml/badge.svg)](https://github.com/Jei-sKappa/drift_crdt/actions/workflows/dart_package.yml)
[![codecov](https://codecov.io/github/Jei-sKappa/drift_crdt/graph/badge.svg?token=I6VTDONJ6Y)](https://codecov.io/github/Jei-sKappa/drift_crdt)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)

Lightweight CRDT utilities for [Drift](https://pub.dev/packages/drift) that add conflict-free replication to your local SQLite database. It provides:

- **CRDT columns** (`isDeleted`, `hlc`, `nodeId`, `modified`) via a `mixin` for Drift tables
- **Safe writes** that automatically set CRDT metadata and resolve conflicts using Hybrid Logical Clocks (HLC)
- **Read helpers** that transparently filter tombstoned rows
- **Export/import** of changesets to sync multiple nodes/devices

An end-to-end example is available in `example/`.

### Motivation

Many apps need offline-first storage and conflict resolution across devices. This package composes with Drift to add minimal, explicit primitives built on HLCs so you can:

- Write data normally while embedding CRDT metadata
- Observe tables without deleted rows
- Compute and merge changesets between nodes

## Installation

```bash
dart pub add drift drift_crdt
```

## Quick start

### 1) Add the `CrdtColumns` mixin to your tables

Add the `CrdtColumns` mixin to any table that should be replicated. Include your app-specific columns as usual.

```dart
class Todos extends Table with CrdtColumns {
  @override
  Set<Column> get primaryKey => {}; // remember to add your primary key
}
```

CRDT columns added by the mixin:

- `isDeleted` (bool): tombstone flag for logical deletes
- `hlc` (text): write HLC
- `nodeId` (text): node id extracted from the HLC
- `modified` (text): last write HLC

### 2) Wrap it with `DriftCrdt` and initialize

```dart
import 'package:drift_crdt/drift_crdt.dart';

final crdt = DriftCrdt<AppDatabase>(db);
await crdt.init(); // optionally pass a UNIQUE node id (a user id, for example)
```

## Reading

Use the included reader helpers. They automatically filter out tombstoned rows (`isDeleted = true`).

### Select
```dart
final rows = await crdt.select(crdt.db.todos);

// This is equivalent to:
final rows = await (db.select(db.todos)..where((t) => t.isDeleted.equals(false))).get();
```

### Watch
```dart
final stream = crdt.watch(crdt.db.todos);

// This is equivalent to:
final stream = (db.select(db.todos)..where((t) => t.isDeleted.equals(false))).watch();
```

### Add your own where clauses (note the slightly different syntax from Drift)
```dart
final stream = crdt.watch(
  crdt.db.todos,
  where: (t) => [
    t.title.equals('Learn Flutter'),
    t.done.equals(false),
  ],
);

// This is equivalent to:
final stream =
    await (db.select(db.todos)
          ..where((t) => t.title.equals('Learn Flutter'))
          ..where((t) => t.done.equals(false))
          ..where((t) => t.isDeleted.equals(false)))
        .get();
```

This uses directly the Drift API, it just filters out tombstoned rows.

## Writing

Use `write` to perform inserts/updates/deletes. CRDT columns (`hlc`, `nodeId`, `modified`, `isDeleted`) are filled automatically and conflicts are resolved by HLC ordering.

### Insert

```dart
await crdt.write((w) async {
  await w.insert(
    crdt.db.todos,
    TodosCompanion(id: 'id-1', title: 'Learn Dart'),
  );
});
```

### Insert with upsert semantics

```dart
await crdt.write((w) async {
  await w.insertOnConflictUpdate(
    crdt.db.todos,
    TodosCompanion(id: 'id-1', title: 'Learn Dart'),
  );
});
```

### Update

```dart
await crdt.write((w) async {
  await w.update(
    crdt.db.todos,
    TodosCompanion(done: Value(true)),
  );
});
```

### Delete (soft-delete with tombstone)

```dart
await crdt.write((w) async {
  await w.delete(
    crdt.db.todos,
    where: (t) => [t.id.equals('id-1')],
  );
});
```

### Transactions

By default, all writes are performed in a transaction so you can write something like this:

```dart
await crdt.write((w) async {
  final q = crdt.db.select(crdt.db.todos)
    ..where((t) => t.id.equals('id-1'));

  final row = await q.getSingle();

  await w.update(
    crdt.db.todos,
    TodosCompanion(done: Value(!row.done)),
    where: (t) => [t.id.equals('id-1')],
  );
});
```
### Limitations

Because of how Drift works you can't use the `<MyTable>Companion.insert` constructor because it forces you to provide also the required CRDTs columns.

For the same reason you also can't use the generated `<MyClass>` `DataClass` class.

Note that you can still use the `<MyTable>Companion` default constructor and and if you forget to provide some of columns that are marked as required by your table, you will get a runtime error.

## Writing (advanced, unsafe)

If you need full control over Drift APIs (e.g. raw queries), you can use `writeUnsafe` function.
It requires a callback function that will provide you with some helpful parameters:
- `db`: the database instance
- `params`: a record that contains the CRDT params that you can use to fill your own columns
- `filters`: a record that contains the WHERE clauses that you need to apply to your query to prevent conflicts. It contains the same filters just in a different format:
  - `filters.hlcFilter` is a filter that you can use in `where` when su you the Drift's query builder
  - `filters.customHlcFilter` is a filter that you can use when you use `db.custom*` methods.

### Params usage

You **must** use the `params` record to fill your own columns.

```dart
await crdt.writeUnsafe((db, params, filters) async {
  final query = db.update(db.todos)..where(filters.hlcFilter);

  await query.write(
    TodosCompanion(
      isDeleted: const Value(true),
      hlc: Value(params.hlc),
      nodeId: Value(params.nodeId),
      modified: Value(params.modified),
    ),
  );

  return (result: null, affectedTables: {db.todos});
});
```

#### Tip

Manually setting the CRDT columns everytime is a bit verbose, so you can use the `withParams` extension method to fill the CRDT columns.

```dart
await crdt.writeUnsafe((db, params, filters) async {
  final query = db.update(db.todos)..where(filters.hlcFilter);

  await query.write(
    const TodosCompanion(isDeleted: Value(true)).withParams(params),
  );

  return (result: null, affectedTables: {db.todos});
});
```

### Filters usage

You **must** use the `filters` record to apply the WHERE clauses to your query.

#### Drift's query builder

You **must** use the `filters.hlcFilter` filter to apply the WHERE clauses to your query.

```dart
await crdt.writeUnsafe((db, params, filters) async {
  final query = db.update(db.todos)..where(filters.hlcFilter);

  /* ... */
});
```

#### Custom queries

You **must** use the `filters.customHlcFilter` filter to apply the WHERE clauses to your query.


```dart
await crdt.writeUnsafe((db, params, filters) async {
  final sql = '''
UPDATE ${db.todos.actualTableName} SET isDeleted = 1
WHERE ${filters.customHlcFilter(db.todos.actualTableName)}
''';

  await db.customUpdate(
    sql,
    updates: {db.todos},
    updateKind: UpdateKind.update,
  );

  return (result: null, affectedTables: {db.todos});
});
```

### Deletes

You **must not** use `writeUnsafe` to perform native delete operation otherwise you will break the CRDT logic.
Instead you **must** update the `isDeleted` column to `true`.

**BAD** ❌
```dart
await crdt.writeUnsafe((db, params, filters) async {
  final query = db.delete(db.todos)..where(filters.hlcFilter);

  await query.go();

  return (result: null, affectedTables: {db.todos});
});
```

**GOOD** ✅ Good:
```dart
await crdt.writeUnsafe((db, params, filters) async {
  final query = db.update(db.todos)..where(filters.hlcFilter);

  await query.write(
    const TodosCompanion(isDeleted: Value(true)).withParams(params),
  );

  return (result: null, affectedTables: {db.todos});
});
```

#### Tip

You can use the `withParams` extension method with the `delete` parameter set to `true` to automatically set the `isDeleted` column to `true`.

```dart
await crdt.writeUnsafe((db, params, filters) async {
  final query = db.update(db.todos)..where(filters.hlcFilter);

  await query.write(
    const TodosCompanion().withParams(params, delete: true),
  );

  return (result: null, affectedTables: {db.todos});
});
```

## Sync between nodes

Export a changeset from one node and merge it into another. The package uses HLCs to ensure deterministic conflict resolution.

```dart
// On node A`
final changeset = await crdtA.getChangeset();

// Send `changeset` to node B via your transport of choice

// On node B
await crdtB.merge(changeset);
```

You can scope changesets:

```dart
// Only specific tables
await crdt.getChangeset(onlyTables: ['todos']);

// Filter by node id
await crdt.getChangeset(onlyNodeId: 'node-A');
await crdt.getChangeset(exceptNodeId: 'node-A');

// Time-based filters using HLCs
await crdt.getChangeset(modifiedOn: someHlc);
await crdt.getChangeset(modifiedAfter: someHlc);
```

## Example

See `example/lib/data/` for the complete setup (tables, mappers, repositories, and database class).

## API overview

- **`CrdtColumns`**: mixin with required CRDT columns
- **`DriftCrdt<T extends GeneratedDatabase>`**:
  - `init([nodeId])`
  - Reads: `select`, `selectSingle(OrNull)`, `watch`, `watchSingle(OrNull)`
  - Writes: `write((w) => w.insert|insertOnConflictUpdate|update|delete(...))`
  - Advanced: `writeUnsafe((db, params, filters) => ...)`
  - Sync: `getChangeset(...)`, `merge(changeset)`, `getLastModified(...)`

## Notes

- Deletions are logical (tombstone). Reads exclude rows where `isDeleted == true`.
- You control transport of changesets between nodes; this package only serializes and merges.

## License

MIT
