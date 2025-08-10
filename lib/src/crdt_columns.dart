part of 'drift_crdt.dart';

/// CRDT columns that must be present on all replicated tables.
///
/// - `isDeleted`: tombstone flag for logical deletes
/// - `hlc`: HLC of the write (ISO string with counter and node)
/// - `nodeId`: node id from the `hlc` for filtering/changesets
/// - `modified`: HLC string representing the last time this row was written
mixin CrdtColumns on Table {
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  TextColumn get hlc => text()();
  TextColumn get nodeId => text()();
  TextColumn get modified => text()();
}
