part of '../drift_crdt.dart';

/// Builder for composing multiple Drift `Expression<bool>` predicates for a
/// given table.
typedef WhereClauses<TableDsl extends CrdtColumns> = Iterable<Expression<bool>>
    Function(TableDsl);

/// Combines the expressions returned by [where] into a single predicate using
/// logical AND. If [where] is `null` or yields no expressions, returns `true`.
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
