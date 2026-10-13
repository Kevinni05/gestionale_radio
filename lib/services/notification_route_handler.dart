import 'package:flutter/material.dart';

import '../notifications_screen.dart';
import 'app_navigation.dart';

/// Mount only after access is approved. Cold-start requests wait here until
/// the authenticated navigator has completed its first frame.
class NotificationRouteHandler extends StatefulWidget {
  const NotificationRouteHandler({super.key, required this.child});
  final Widget child;

  @override
  State<NotificationRouteHandler> createState() =>
      _NotificationRouteHandlerState();
}

class _NotificationRouteHandlerState extends State<NotificationRouteHandler> {
  bool _scheduled = false;

  @override
  void initState() {
    super.initState();
    AppNavigation.requestedNotification.addListener(_schedule);
    _schedule();
  }

  void _schedule() {
    if (_scheduled || AppNavigation.requestedNotification.value == null) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted) return;
      final id = AppNavigation.requestedNotification.value;
      if (id == null) return;
      AppNavigation.requestedNotification.value = null;
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => NotificationsScreen(highlightNotificationId: id),
        ),
      );
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void dispose() {
    AppNavigation.requestedNotification.removeListener(_schedule);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
