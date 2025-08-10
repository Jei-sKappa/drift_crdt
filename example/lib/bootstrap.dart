import 'package:example/domain/domain.dart';
import 'package:example/ui/app/app.dart';
import 'package:flutter/material.dart';

void bootstrap(TodoRepository todoRepository) {
  runApp(App(todoRepository: todoRepository));
}
