part of 'drift_crdt.dart';

/// Read helpers for CRDT-enabled tables that automatically filter out
/// logically-deleted rows (`isDeleted = false`).
mixin DriftCrdtReader {
  /// The database instance.
  GeneratedDatabase get db;

  /// Selects multiple rows from [table], combining optional [where] predicates
  /// and excluding tombstoned rows.
  ///
  /// See also:
  /// * [SimpleSelectStatement.get] for more details.
  Future<List<D>> select<TableDsl extends CrdtColumns, D>(
    TableInfo<TableDsl, D> table, {
    WhereClauses<TableDsl>? where,
  }) =>
      _selectBuilder(table, where).get();

  /// Selects a single row from [table]. Throws if none or multiple rows match.
  ///
  /// See also:
  /// * [SimpleSelectStatement.getSingle] for more details.
  Future<D> selectSingle<TableDsl extends CrdtColumns, D>(
    TableInfo<TableDsl, D> table, {
    WhereClauses<TableDsl>? where,
  }) =>
      _selectBuilder(table, where).getSingle();

  /// Selects a single row from [table] or returns `null` if none match.
  ///
  /// See also:
  /// * [SimpleSelectStatement.getSingleOrNull] for more details.
  Future<D?> selectSingleOrNull<TableDsl extends CrdtColumns, D>(
    TableInfo<TableDsl, D> table, {
    WhereClauses<TableDsl>? where,
  }) =>
      _selectBuilder(table, where).getSingleOrNull();

  /// Watches multiple rows from [table] as a stream, excluding tombstoned
  /// rows.
  ///
  /// See also:
  /// * [SimpleSelectStatement.watch] for more details.
  Stream<List<D>> watch<TableDsl extends CrdtColumns, D>(
    TableInfo<TableDsl, D> table, {
    WhereClauses<TableDsl>? where,
  }) =>
      _selectBuilder(table, where).watch();

  /// Watches a single row from [table] as a stream. Errors on zero or multiple
  /// matches.
  ///
  /// See also:
  /// * [SimpleSelectStatement.watchSingle] for more details.
  Stream<D> watchSingle<TableDsl extends CrdtColumns, D>(
    TableInfo<TableDsl, D> table, {
    WhereClauses<TableDsl>? where,
  }) =>
      _selectBuilder(table, where).watchSingle();

  /// Watches a single row from [table] as a stream, or emits `null` when no
  /// row matches.
  ///
  /// See also:
  /// * [SimpleSelectStatement.watchSingleOrNull] for more details.
  Stream<D?> watchSingleOrNull<TableDsl extends CrdtColumns, D>(
    TableInfo<TableDsl, D> table, {
    WhereClauses<TableDsl>? where,
  }) =>
      _selectBuilder(table, where).watchSingleOrNull();

  SimpleSelectStatement<TableDsl, D>
      _selectBuilder<TableDsl extends CrdtColumns, D>(
          TableInfo<TableDsl, D> table, WhereClauses<TableDsl>? where) {
    final q = db.select(table);
    if (where != null) {
      q.where((tbl) => _combineWhereClauses(tbl, where));
    }
    // Hide logically-deleted rows by default.
    q.where((t) => t.isDeleted.equals(false));

    return q;
  }
}
