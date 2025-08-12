part of '../drift_crdt.dart';

/// Adds helpers to stamp CRDT metadata into an [`Insertable`].
extension WithParams<D> on Insertable<D> {
  /// Returns an [`Insertable`] that includes the CRDT columns from [params].
  /// If [delete] is `true`, sets `is_deleted` to `true` to perform a logical
  /// delete.
  Insertable<D> withParams(CrdtParams params, {bool delete = false}) {
    return _rawInsertable<D>((nullToAbsent) {
      final map = toColumns(nullToAbsent);
      map['hlc'] = Variable<String>(params.hlc);
      map['node_id'] = Variable<String>(params.nodeId);
      map['modified'] = Variable<String>(params.modified);
      if (delete) {
        map['is_deleted'] = const Variable<bool>(true);
      }
      return map;
    });
  }
}
