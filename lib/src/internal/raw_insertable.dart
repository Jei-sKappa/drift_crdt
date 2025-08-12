part of '../drift_crdt.dart';

/// Creates an [`Insertable`] wrapper that yields a custom columns map produced
/// by [toColumns].
_RawInsertable<D> _rawInsertable<D>(_ToColumns<D> toColumns) =>
    _RawInsertable<D>(toColumns);

/// Minimal insertable that delegates to a provided `toColumns` function.
class _RawInsertable<D> implements Insertable<D> {
  _RawInsertable(this._toColumns);

  final _ToColumns<D> _toColumns;

  @override
  Map<String, Expression<Object>> toColumns(bool nullToAbsent) =>
      _toColumns(nullToAbsent);
}

/// Signature of a function that converts a model into a columns map compatible
/// with Drift's `Insertable` API.
typedef _ToColumns<D> =
    // ignore_reason: copy the original api
    // ignore: avoid_positional_boolean_parameters
    Map<String, Expression<Object>> Function(bool nullToAbsent);
