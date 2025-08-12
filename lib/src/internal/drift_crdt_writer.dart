part of '../drift_crdt.dart';

/// Helper used inside [`DriftCrdt.write`] transactions to perform CRDT-safe
/// inserts, updates, and logical deletes while stamping rows with the proper
/// HLC fields and enforcing last-writer-wins.
class DriftCrdtWriter {
  DriftCrdtWriter._(this._db, this._hlc);

  final GeneratedDatabase _db;
  final Hlc _hlc;
  final Set<String> _affectedTables = {};

  /// Fills `entity` with the fields needed to update the CRDT columns and calls
  /// `database.into(table).insert(entity)`.
  ///
  /// Returns the `rowid` of the inserted row.
  ///
  /// See also:
  /// * [InsertStatement.insert] for more details about the `rowid` returned.
  Future<int> insert<TableDsl extends CrdtColumns, D>(
    TableInfo<TableDsl, D> table,
    Insertable<D> entity,
  ) async {
    final hlcStr = _hlc.toString();

    final rawInsertable = _rawInsertable<D>((nullToAbsent) {
      // Start with the entity's columns
      final map = entity.toColumns(nullToAbsent);

      // Add the fields we need to update
      map['hlc'] = Variable<String>(hlcStr);
      map['node_id'] = Variable<String>(_hlc.nodeId);
      map['modified'] = Variable<String>(hlcStr);
      map.putIfAbsent('is_deleted', () => const Variable<bool>(false));
      return map;
    });

    final res = await _db.into(table).insert(rawInsertable);

    _affectedTables.add(table.actualTableName);

    return res;
  }

  /// Fills `entity` with the fields needed to update the CRDT columns and calls
  /// `database.into(table).insert(entity, onConflict: DoUpdate((_) => entity))`
  /// while making sure to ignore the update if the there is already a more
  /// recent row in the database.
  ///
  /// Returns the `rowid` of the inserted row.
  ///
  /// See also:
  /// * [InsertStatement.insert] for more details about the `rowid` returned.
  Future<int> insertOnConflictUpdate<TableDsl extends CrdtColumns, D>(
    TableInfo<TableDsl, D> table,
    Insertable<D> entity,
  ) async {
    final hlcStr = _hlc.toString();

    final rawInsertable = _rawInsertable<D>((nullToAbsent) {
      // Start with the entity's columns
      final map = entity.toColumns(nullToAbsent);

      // Add the fields we need to update
      map['hlc'] = Variable<String>(hlcStr);
      map['node_id'] = Variable<String>(_hlc.nodeId);
      map['modified'] = Variable<String>(hlcStr);
      map.putIfAbsent('is_deleted', () => const Variable<bool>(false));
      return map;
    });

    final res = await _db.into(table).insert(
          rawInsertable,
          onConflict: DoUpdate(
            (_) => rawInsertable,
            where: (t) => t.hlc.isSmallerThanValue(hlcStr),
          ),
        );

    _affectedTables.add(table.actualTableName);

    return res;
  }

  /// Fills `entity` with the fields needed to update the CRDT columns and calls
  /// `database.update(table)..where(...).write(entity)`.
  ///
  /// Returns the amount of rows that have been affected by this operation.
  ///
  /// See also:
  /// * [UpdateStatement.write] for more details about the number of rows
  /// updated.
  Future<int> update<TableDsl extends CrdtColumns, D>(
    TableInfo<TableDsl, D> table,
    Insertable<D> entity, {
    WhereClauses<TableDsl>? where,
  }) async {
    final hlcStr = _hlc.toString();

    final rawInsertable = _rawInsertable<D>((nullToAbsent) {
      // Start with the entity's columns
      final map = entity.toColumns(nullToAbsent);

      // Add the fields we need to update
      map['hlc'] = Variable<String>(hlcStr);
      map['node_id'] = Variable<String>(_hlc.nodeId);
      map['modified'] = Variable<String>(hlcStr);

      // Check if the entity has an is_deleted column.
      // Theoretically, this should never happen, but we'll be defensive.
      map.putIfAbsent('is_deleted', () => const Variable<bool>(false));
      return map;
    });

    final q = _db.update(table);
    if (where != null) {
      q.where((tbl) => _combineWhereClauses(tbl, where));
    }
    q.where((t) => t.hlc.isSmallerThanValue(hlcStr));

    final res = await q.write(rawInsertable);

    _affectedTables.add(table.actualTableName);

    return res;
  }

  /// Fills `entity` with the fields needed to update the CRDT columns and calls
  /// `database.update(table)..where(...).write(entity)`.
  ///
  /// The `entity` is filled with the fields needed to update the crdt columns
  /// and the `is_deleted` column is set to `true`.
  ///
  /// Returns the amount of rows that have been affected by this operation.
  ///
  /// See also:
  /// * [UpdateStatement.write] for more details about the number of rows
  /// updated.
  Future<int> delete<TableDsl extends CrdtColumns, D>(
    TableInfo<TableDsl, D> table, {
    WhereClauses<TableDsl>? where,
  }) async {
    final hlcStr = _hlc.toString();

    final rawInsertable = _rawInsertable<D>((nullToAbsent) {
      // Start with an empty map
      final map = <String, Expression<Object>>{};

      // Add the fields we need to update
      map['hlc'] = Variable<String>(hlcStr);
      map['node_id'] = Variable<String>(_hlc.nodeId);
      map['modified'] = Variable<String>(hlcStr);
      map['is_deleted'] = const Variable<bool>(true);
      return map;
    });

    final q = _db.update(table);
    if (where != null) {
      q.where((tbl) => _combineWhereClauses(tbl, where));
    }
    q.where((t) => t.hlc.isSmallerThanValue(hlcStr));

    final res = await q.write(rawInsertable);

    _affectedTables.add(table.actualTableName);

    return res;
  }
}
