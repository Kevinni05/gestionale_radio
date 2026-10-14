import 'package:flutter/material.dart';

abstract final class AppNavigation {
  static final navigatorKey = GlobalKey<NavigatorState>();
  static final requestedTask = ValueNotifier<String?>(null);
  static final requestedNotification = ValueNotifier<String?>(null);
  static final tasksRevision = ValueNotifier<int>(0);
  static final notificationsRevision = ValueNotifier<int>(0);
  static void refreshTasks() => tasksRevision.value++;
  static void refreshNotifications() => notificationsRevision.value++;
  static void openNotification(String id) {
    if (id.trim().isNotEmpty) requestedNotification.value = id.trim();
  }

  static void clearRequests() {
    requestedTask.value = null;
    requestedNotification.value = null;
  }

  static void openTask(String? id) {
    if (id != null && id.trim().isNotEmpty) requestedTask.value = id.trim();
  }
}
