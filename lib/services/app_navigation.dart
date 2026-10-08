import 'package:flutter/material.dart';

abstract final class AppNavigation {
  static final navigatorKey = GlobalKey<NavigatorState>();
  static final requestedTask = ValueNotifier<String?>(null);
  static final tasksRevision = ValueNotifier<int>(0);
  static void refreshTasks() => tasksRevision.value++;
  static void openTask(String? id) {
    if (id != null && id.trim().isNotEmpty) requestedTask.value = id.trim();
  }
}
