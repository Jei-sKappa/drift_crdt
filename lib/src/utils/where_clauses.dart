part of '../drift_crdt.dart';

typedef WhereClauses<TableDsl extends CrdtColumns> = Iterable<Expression<bool>>
    Function(TableDsl);

Expression<bool> _combineWhereClauses<TableDsl extends CrdtColumns>(
  TableDsl table,
  WhereClauses<TableDsl>? where,
) {
  if (where == null) return const Constant(true);

  final predicates = where(table);
  Expression<bool>? combined;
  for (final p in predicates) {
    combined = combined == null ? p : (combined & p);
  }

  return combined ?? const Constant(true);
}
