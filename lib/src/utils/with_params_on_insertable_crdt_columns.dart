part of '../drift_crdt.dart';

extension WithParams<D> on Insertable<D> {
  Insertable<D> withParams(CrdtParams params) {
    return _rawInsertable<D>((nullToAbsent) {
      final map = toColumns(nullToAbsent);
      map['hlc'] = Variable<String>(params.hlc);
      map['node_id'] = Variable<String>(params.nodeId);
      map['modified'] = Variable<String>(params.modified);
      return map;
    });
  }
}
