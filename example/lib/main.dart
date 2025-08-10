import 'package:drift_crdt/drift_crdt.dart';
import 'package:example/bootstrap.dart';
import 'package:example/data/data.dart';
import 'package:example/stub/database/database.dart';
import 'package:flutter/material.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize the SQLite database
  final sqliteDatabase = AppDatabase(createQueryExecutor());

  // Initialize the CRDT
  final crdt = DriftCrdt(sqliteDatabase);
  await crdt.init();

  // Initialize the todo repository
  // final todoRepository = SqliteCrdtTodoRepository(crdt);
  final todoRepository = UnsafeSqliteCrdtTodoRepository(crdt);

  bootstrap(todoRepository);
}
