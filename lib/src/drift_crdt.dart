import 'dart:async';

import 'package:crdt/crdt.dart';
import 'package:drift/drift.dart';

part 'internal/raw_insertable.dart';
part 'internal/drift_crdt_writer.dart';
part 'crdt_columns.dart';
part 'drift_crdt_reader.dart';
part 'utils/with_params_on_insertable_crdt_columns.dart';
part 'utils/where_clauses.dart';

typedef CrdtParams = ({String hlc, String nodeId, String modified});

typedef CrdtFilters =
    ({
      Expression<bool> Function(CrdtColumns t) hlcFilter,
      String Function(String tableName) customHlcFilter,
    });

class DriftCrdt<T extends GeneratedDatabase> with Crdt, DriftCrdtReader {
  DriftCrdt(this.db);

  @override
  final T db;

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  Future<void> init([String? nodeId]) async {
    if (_isInitialized) return;

    final last = await _getLastModifiedNullable();
    // If empty, seed canonical time
    canonicalTime = last ?? Hlc.zero(nodeId ?? generateNodeId());
    _isInitialized = true;
  }

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

    final selected =
        onlyTables == null
            ? tables
            : tables
                .where((t) => onlyTables.contains(t.actualTableName))
                .toList();

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
          map[col.$name] = row.read(col);
        }
        tableChanges.add(map);
      }
      if (tableChanges.isNotEmpty) {
        result[table.actualTableName] = tableChanges;
      }
    }

    return result;
  }

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
          final recordHlcStr =
              (record['hlc'] is Hlc)
                  ? (record['hlc']! as Hlc).toString()
                  : record['hlc']! as String;
          final recordNodeId =
              (record['hlc'] is Hlc)
                  ? (record['hlc']! as Hlc).nodeId
                  : recordHlcStr.toHlc.nodeId;

          // Stamp CRDT fields; modified is set to hlcNew
          final rawInsertable = _rawInsertable<dynamic>((nullToAbsent) {
            // Start with an empty map
            final map = <String, Expression<Object>>{};

            record.forEach((key, value) {
              // Skip null values if nullToAbsent is true
              if (nullToAbsent && value == null) return;

              map[key] = Variable<Object>(value);
            });

            map['hlc'] = Variable<String>(recordHlcStr);
            map['node_id'] = Variable<String>(recordNodeId);
            map['modified'] = Variable<String>(hlcNew.toString());

            return map;
          });

          await _rawInsertOnConflictUpdate(db, table, rawInsertable, hlcNew);
        }
      }
    });

    onDatasetChanged(changeset.keys, hlcNew);
  }

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

  Future<R> writeUnsafe<R>(
    Future<({R result, Iterable<String>? affectedTables})> Function(
      T db,
      CrdtParams params,
      CrdtFilters filters,
    )
    action,
  ) async {
    final hlc = canonicalTime.increment();
    final hlcStr = hlc.toString();

    final (:result, :affectedTables) = await action(
      db,
      (hlc: hlcStr, nodeId: hlc.nodeId, modified: hlcStr),
      (
        hlcFilter: (t) => t.hlc.isSmallerThanValue(hlcStr),
        customHlcFilter: (table) => 'WHERE excluded.hlc > $table.hlc',
      ),
    );

    if (affectedTables?.isNotEmpty ?? false) {
      onDatasetChanged(affectedTables!, hlc);
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
