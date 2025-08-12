import 'dart:async';

import 'package:crdt/crdt.dart';
import 'package:drift/drift.dart';

part 'internal/raw_insertable.dart';
part 'internal/drift_crdt_writer.dart';
part 'crdt_columns.dart';
part 'drift_crdt_reader.dart';
part 'utils/with_params_on_insertable_crdt_columns.dart';
part 'utils/where_clauses.dart';

/// Tuple of CRDT metadata fields required on each write.
///
/// - **hlc**: Hybrid Logical Clock timestamp for the write (as ISO string)
/// - **nodeId**: Node identifier embedded in the HLC
/// - **modified**: The effective modification timestamp (HLC string)
typedef CrdtParams = ({String hlc, String nodeId, String modified});

/// Filters used when performing unsafe writes to enforce CRDT ordering.
///
/// - **hlcFilter**: Expression enforcing that the incoming HLC is newer than
///   the stored one for a given table.
/// - **customHlcFilter**: Raw SQL fragment producer for ON CONFLICT clauses.
typedef CrdtFilters = ({
  Expression<bool> Function(CrdtColumns t) hlcFilter,
  String Function(String tableName) customHlcFilter,
});

/// CRDT-capable wrapper around a Drift [`GeneratedDatabase`].
///
/// This class coordinates HLC time, produces change sets, merges remote data
/// using last-writer-wins semantics, and provides helpers for safe and unsafe
/// write operations.
class DriftCrdt<T extends GeneratedDatabase> with Crdt, DriftCrdtReader {
  /// Creates a new CRDT helper bound to the provided Drift database.
  DriftCrdt(this.db);

  @override
  final T db;

  bool _isInitialized = false;

  /// Whether [`init`] has been called to seed the canonical HLC time.
  bool get isInitialized => _isInitialized;

  /// Initializes the CRDT state by seeding `canonicalTime`.
  ///
  /// If the database contains rows, the latest `modified` HLC is used.
  /// Otherwise a zero HLC is created using the provided [nodeId] or a
  /// generated one.
  Future<void> init([String? nodeId]) async {
    if (_isInitialized) return;

    final last = await _getLastModifiedNullable();
    // If empty, seed canonical time
    canonicalTime = last ?? Hlc.zero(nodeId ?? generateNodeId());
    _isInitialized = true;
  }

  /// Returns the maximum `modified` HLC across CRDT-enabled tables.
  ///
  /// Optionally restricts the search to rows written by [onlyNodeId] or to all
  /// rows except those written by [exceptNodeId].
  ///
  /// Both [onlyNodeId] and [exceptNodeId] cannot be used together.
  @override
  Future<Hlc> getLastModified({
    String? onlyNodeId,
    String? exceptNodeId,
  }) async {
    final last = await _getLastModifiedNullable(
      onlyNodeId: onlyNodeId,
      exceptNodeId: exceptNodeId,
    );
    return last ?? Hlc.zero(canonicalTime.nodeId);
  }

  /// Builds a changeset with all rows from CRDT-enabled tables, optionally
  /// filtered by table names, node id, or modification time windows.
  @override
  Future<CrdtChangeset> getChangeset({
    Iterable<String>? onlyTables,
    String? onlyNodeId,
    String? exceptNodeId,
    Hlc? modifiedOn,
    Hlc? modifiedAfter,
  }) async {
    assert(
      onlyNodeId == null || exceptNodeId == null,
      'onlyNodeId and exceptNodeId must not be used together',
    );
    assert(
      modifiedOn == null || modifiedAfter == null,
      'modifiedOn and modifiedAfter must not be used together',
    );

    modifiedOn = modifiedOn?.apply(nodeId: nodeId);
    modifiedAfter = modifiedAfter?.apply(nodeId: nodeId);

    final tables = db.allTables.toList();

    final selected = onlyTables == null
        ? tables
        : tables.where((t) => onlyTables.contains(t.actualTableName)).toList();

    final result = <String, List<Map<String, Object?>>>{};

    for (final table in selected) {
      if (table is! TableInfo<CrdtColumns, dynamic>) {
        continue;
      }

      final allColumns = table.$columns;

      final q = db.selectOnly(table)..addColumns(allColumns);
      if (onlyNodeId != null) {
        q.where(table.asDslTable.nodeId.equals(onlyNodeId));
      }
      if (exceptNodeId != null) {
        q.where(table.asDslTable.nodeId.equals(exceptNodeId).not());
      }
      if (modifiedOn != null) {
        q.where(table.asDslTable.modified.equals(modifiedOn.toString()));
      }
      if (modifiedAfter != null) {
        q.where(
          table.asDslTable.modified.isBiggerThanValue(modifiedAfter.toString()),
        );
      }
      final rows = await q.get();
      if (rows.isEmpty) continue;

      final tableChanges = <Map<String, Object?>>[];
      for (final row in rows) {
        final map = <String, Object?>{};
        for (final col in allColumns) {
          final value = row.read(col);
          // Convert HLC string back to Hlc object for CRDT compatibility
          if (col.$name == 'hlc' && value is String) {
            map[col.$name] = value.toHlc;
          } else {
            map[col.$name] = value;
          }
        }
        tableChanges.add(map);
      }
      if (tableChanges.isNotEmpty) {
        result[table.actualTableName] = tableChanges;
      }
    }

    return result;
  }

  /// Merges a [changeset] into the local database using last-writer-wins
  /// based on the `hlc` column. Notifies listeners via [`onDatasetChanged`].
  @override
  Future<void> merge(CrdtChangeset changeset) async {
    if (changeset.recordCount == 0) return;
    final hlcNew = validateChangeset(changeset);

    await db.transaction(() async {
      for (final entry in changeset.entries) {
        final tableName = entry.key;
        final table = db.allTables.firstWhere(
          (t) => t.actualTableName == tableName,
        );

        if (table is! TableInfo<CrdtColumns, dynamic>) {
          continue;
        }

        for (final record in entry.value) {
          final recordHlcStr = (record['hlc'] is Hlc)
              ? (record['hlc']! as Hlc).toString()
              : record['hlc']! as String;
          final recordNodeId = (record['hlc'] is Hlc)
              ? (record['hlc']! as Hlc).nodeId
              : recordHlcStr.toHlc.nodeId;

          // Use raw SQL to avoid type issues with dynamic tables
          final columnsAndValues = <String, Object?>{};
          record.forEach((key, value) {
            if (value != null) {
              columnsAndValues[key] = value;
            }
          });

          // Override CRDT fields
          columnsAndValues['hlc'] = recordHlcStr;
          columnsAndValues['node_id'] = recordNodeId;
          columnsAndValues['modified'] = hlcNew.toString();

          // Build column and value lists for SQL
          final columns = columnsAndValues.keys.toList();
          final values = columnsAndValues.values.toList();
          final placeholders =
              List.generate(values.length, (i) => '?${i + 1}').join(', ');
          final columnList = columns.join(', ');

          // Build update clause for conflict resolution
          final updateClauses = columns
              .where((col) => col != 'id') // Don't update primary key
              .map((col) => '$col = excluded.$col')
              .join(', ');

          await db.customStatement('''
            INSERT INTO ${table.actualTableName} ($columnList)
            VALUES ($placeholders)
            ON CONFLICT DO UPDATE SET $updateClauses
            WHERE excluded.hlc > ${table.actualTableName}.hlc
          ''', values);
        }
      }
    });

    onDatasetChanged(changeset.keys, hlcNew);
  }

  /// Runs a sequence of CRDT-safe write operations in a transaction.
  ///
  /// The provided [action] receives a [`DriftCrdtWriter`] that automatically
  /// stamps rows with CRDT fields and enforces HLC ordering.
  ///
  /// If you think that the helper methods provided by this api are not enough
  /// for your use case, consider
  /// [filing an issue](https://github.com/Jei-sKappa/drift_crdt/issues/new)
  /// to discuss it.
  ///
  /// See also:
  /// * [DriftCrdt.writeUnsafe] for a more flexible alternative that allows
  ///   even custom SQL statements.
  Future<R> write<R>(Future<R> Function(DriftCrdtWriter s) action) async {
    late final R result;
    await db.transaction(() async {
      final session = DriftCrdtWriter._(db, canonicalTime.increment());
      result = await action(session);
      if (session._affectedTables.isNotEmpty) {
        onDatasetChanged(session._affectedTables, session._hlc);
      }
    });
    return result;
  }

  /// Helper function to handle raw database operations.
  ///
  /// This is useful when higher control is required or when you need to execute
  /// raw SQL.
  ///
  /// If possible always prefer the [write] method, as it is safer and easier
  /// to use.
  ///
  /// If you are forced to use this method consider
  /// [filing an issue](https://github.com/Jei-sKappa/drift_crdt/issues/new)
  /// to discuss your use case.
  ///
  /// See also:
  /// * [DriftCrdt.write] for a safer alternative that automatically handles
  ///   CRDT columns and ordering.
  Future<R> writeUnsafe<R>(
    Future<({R result, Set<TableInfo<dynamic, dynamic>>? affectedTables})>
        Function(
      T db,
      CrdtParams params,
      CrdtFilters filters,
    ) action,
  ) async {
    final hlc = canonicalTime.increment();
    final hlcStr = hlc.toString();

    final (:result, :affectedTables) = await action(
      db,
      (hlc: hlcStr, nodeId: hlc.nodeId, modified: hlcStr),
      (
        hlcFilter: (t) => t.hlc.isSmallerThanValue(hlcStr),
        customHlcFilter: (table) => 'excluded.hlc > $table.hlc',
      ),
    );

    if (affectedTables?.isNotEmpty ?? false) {
      onDatasetChanged(affectedTables!.map((t) => t.actualTableName), hlc);
    }

    return result;
  }

  Future<Hlc?> _getLastModifiedNullable({
    String? onlyNodeId,
    String? exceptNodeId,
  }) async {
    assert(
      onlyNodeId == null || exceptNodeId == null,
      'onlyNodeId and exceptNodeId must not be used together',
    );

    Hlc? maxHlc;
    for (final table in db.allTables) {
      if (table is! TableInfo<CrdtColumns, dynamic>) {
        continue;
      }

      final q = db.selectOnly(table)
        ..addColumns([table.asDslTable.modified.max()]);
      if (onlyNodeId != null) {
        q.where(table.asDslTable.nodeId.equals(onlyNodeId));
      } else if (exceptNodeId != null) {
        q.where(table.asDslTable.nodeId.equals(exceptNodeId).not());
      }
      final row = await q.getSingleOrNull();
      final modifiedStr = row?.read(table.asDslTable.modified.max());
      if (modifiedStr is String) {
        final hlc = modifiedStr.toHlc;
        if (maxHlc == null || hlc > maxHlc) maxHlc = hlc;
      }
    }
    return maxHlc;
  }
}
