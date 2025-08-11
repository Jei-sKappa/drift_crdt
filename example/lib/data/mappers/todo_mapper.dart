import 'package:drift/drift.dart';
import 'package:example/data/data.dart';
import 'package:example/domain/domain.dart';

extension TodoMapperExtension on Todo {
  TodosCompanion toInsertable() {
    return TodosCompanion(
      id: Value(id),
      title: Value(title),
      done: Value(done),
      isDeleted: const Value(false),
    );
  }
}

extension TodoEntityMapperExtension on TodoModel {
  Todo toEntity() {
    return Todo(id: id, title: title, done: done);
  }
}
