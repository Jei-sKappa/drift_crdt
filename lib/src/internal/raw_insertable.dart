part of '../drift_crdt.dart';

_RawInsertable<D> _rawInsertable<D>(_ToColumns<D> toColumns) =>
    _RawInsertable<D>(toColumns);

class _RawInsertable<D> implements Insertable<D> {
  _RawInsertable(this._toColumns);

  final _ToColumns<D> _toColumns;

  @override
  Map<String, Expression<Object>> toColumns(bool nullToAbsent) =>
      _toColumns(nullToAbsent);
}

typedef _ToColumns<D> =
    // ignore_reason: copy the original api
    // ignore: avoid_positional_boolean_parameters
    Map<String, Expression<Object>> Function(bool nullToAbsent);
