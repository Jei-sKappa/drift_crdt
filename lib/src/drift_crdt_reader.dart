part of 'drift_crdt.dart';

mixin DriftCrdtReader {
  GeneratedDatabase get db;

  Future<List<D>> select<TableDsl extends CrdtColumns, D>(
    TableInfo<TableDsl, D> table, {
    WhereClauses<TableDsl>? where,
  }) => _selectBuilder(table, where).get();

  Future<D> selectSingle<TableDsl extends CrdtColumns, D>(
    TableInfo<TableDsl, D> table, {
    WhereClauses<TableDsl>? where,
  }) => _selectBuilder(table, where).getSingle();

  Future<D?> selectSingleOrNull<TableDsl extends CrdtColumns, D>(
    TableInfo<TableDsl, D> table, {
    WhereClauses<TableDsl>? where,
  }) => _selectBuilder(table, where).getSingleOrNull();

  Stream<List<D>> watch<TableDsl extends CrdtColumns, D>(
    TableInfo<TableDsl, D> table, {
    WhereClauses<TableDsl>? where,
  }) => _selectBuilder(table, where).watch();

  Stream<D> watchSingle<TableDsl extends CrdtColumns, D>(
    TableInfo<TableDsl, D> table, {
    WhereClauses<TableDsl>? where,
  }) => _selectBuilder(table, where).watchSingle();

  Stream<D?> watchSingleOrNull<TableDsl extends CrdtColumns, D>(
    TableInfo<TableDsl, D> table, {
    WhereClauses<TableDsl>? where,
  }) => _selectBuilder(table, where).watchSingleOrNull();

  SimpleSelectStatement<TableDsl, D> _selectBuilder<
    TableDsl extends CrdtColumns,
    D
  >(TableInfo<TableDsl, D> table, WhereClauses<TableDsl>? where) {
    final q = db.select(table);
    if (where != null) {
      q.where((tbl) => _combineWhereClauses(tbl, where));
    }
    q.where((t) => t.isDeleted.equals(false));

    return q;
  }
}
