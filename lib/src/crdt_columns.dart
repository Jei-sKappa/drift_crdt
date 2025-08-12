part of 'drift_crdt.dart';

/// CRDT columns that must be present on all replicated tables.
///
/// - `isDeleted`: tombstone flag for logical deletes
/// - `hlc`: HLC of the write (ISO string with counter and node)
/// - `nodeId`: node id from the `hlc` for filtering/changesets
/// - `modified`: HLC string representing the last time this row was written
mixin CrdtColumns on Table {
  /// Tombstone flag for logical deletes
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  /// HLC of the write (ISO string with counter and node)
  TextColumn get hlc => text()();

  /// Node id from the `hlc` for filtering/changesets
  TextColumn get nodeId => text()();

  /// HLC string representing the last time this row was written
  TextColumn get modified => text()();
}
