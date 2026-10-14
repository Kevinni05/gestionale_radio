import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestionale_radio/notifications_screen.dart';
import 'package:gestionale_radio/theme/radiotech_theme.dart';
import 'package:gestionale_radio/services/app_navigation.dart';

void main() {
  testWidgets(
    'an open inbox reloads on a received notice and highlights the cold-start destination',
    (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: NotificationsScreen(
            highlightNotificationId: 'new',
            loadNotifications: () async {
              calls++;
              return [
                {
                  'id': 'old',
                  'title': 'Messaggio precedente',
                  'message': 'Vecchio avviso',
                },
                if (calls > 1)
                  {
                    'id': 'new',
                    'title': 'Nuovo avviso',
                    'message': 'Da leggere',
                  },
              ];
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Nuovo avviso'), findsNothing);
      AppNavigation.refreshNotifications();
      await tester.pumpAndSettle();
      expect(find.text('Nuovo avviso'), findsOneWidget);
      expect(calls, 2);
      expect(
        tester.getTopLeft(find.text('Nuovo avviso')).dy,
        lessThan(tester.getTopLeft(find.text('Messaggio precedente')).dy),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      AppNavigation.refreshNotifications();
      expect(tester.takeException(), isNull);
      expect(calls, 2);
    },
  );
  testWidgets(
    'messages refresh and linked notifications open the correct assignment',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var calls = 0;
      String? opened;
      await tester.pumpWidget(
        MaterialApp(
          theme: RadioTechTheme.dark,
          home: NotificationsScreen(
            loadNotifications: () async {
              calls++;
              return [
                {
                  'id': 'notice',
                  'title': 'Comunicazione dalla centrale',
                  'message': 'Verificare la disponibilità della squadra.',
                  'createdAt': '2026-10-05T12:00:00Z',
                  if (calls > 1) 'taskId': 'task-42',
                },
              ];
            },
            onOpenTask: (id) => opened = id,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Comunicazione dalla centrale'), findsOneWidget);
      expect(
        find.text('Verificare la disponibilità della squadra.'),
        findsOneWidget,
      );
      expect(find.text('Apri incarico'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Aggiorna notifiche'));
      await tester.pumpAndSettle();
      expect(calls, 2);
      await tester.tap(find.text('Apri incarico'));
      expect(opened, 'task-42');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('failed requests can be retried and empty history is explicit', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: NotificationsScreen(
          loadNotifications: () async {
            calls++;
            if (calls == 1) throw Exception('Centrale non raggiungibile');
            return [];
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Impossibile caricare le notifiche.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Riprova'));
    await tester.pumpAndSettle();
    expect(find.text('Nessuna notifica al momento.'), findsOneWidget);
    expect(calls, 2);
  });
}
