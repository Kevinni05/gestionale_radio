import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestionale_radio/notifications_screen.dart';
import 'package:gestionale_radio/services/app_navigation.dart';
import 'package:gestionale_radio/services/notification_route_handler.dart';

void main() {
  setUp(AppNavigation.clearRequests);
  tearDown(AppNavigation.clearRequests);

  testWidgets(
    'cold-start general notification waits for an approved host and opens the matching inbox',
    (tester) async {
      AppNavigation.openNotification('cold-notice');
      await tester.pumpWidget(
        const MaterialApp(
          home: NotificationRouteHandler(
            child: Scaffold(body: Text('Home autorizzata')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final screen = tester.widget<NotificationsScreen>(
        find.byType(NotificationsScreen),
      );
      expect(screen.highlightNotificationId, 'cold-notice');
      expect(AppNavigation.requestedNotification.value, isNull);
      expect(find.text('Notifiche e avvisi'), findsOneWidget);
    },
  );

  testWidgets(
    'identity reset before the next frame cancels a queued navigation',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: NotificationRouteHandler(
            child: Scaffold(body: Text('Home autorizzata')),
          ),
        ),
      );
      AppNavigation.openNotification('old-account');
      AppNavigation.clearRequests();
      await tester.pumpAndSettle();
      expect(find.byType(NotificationsScreen), findsNothing);
      expect(find.text('Home autorizzata'), findsOneWidget);
    },
  );
}
