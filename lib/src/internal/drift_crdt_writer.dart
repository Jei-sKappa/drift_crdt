part of '../drift_crdt.dart';

class DriftCrdtWriter {
  DriftCrdtWriter._(this._db, this._hlc);

  final GeneratedDatabase _db;
  final Hlc _hlc;
  final Set<String> _affectedTables = {};

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

    final res = await _rawInsertOnConflictUpdate(
      _db,
      table,
      rawInsertable,
      _hlc,
    );

    _affectedTables.add(table.actualTableName);

    return res;
  }

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
