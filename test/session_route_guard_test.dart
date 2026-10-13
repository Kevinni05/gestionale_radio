import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestionale_radio/services/app_navigation.dart';
import 'package:gestionale_radio/services/session_route_guard.dart';

void main() {
  testWidgets('tenant or role change closes private routes for the same uid', (
    tester,
  ) async {
    final identities = StreamController<String?>.broadcast();
    final scopes = StreamController<String?>.broadcast();
    final navigator = GlobalKey<NavigatorState>();
    var invalidations = 0;
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: SessionRouteGuard(
          identities: identities.stream,
          initialIdentity: 'same-user',
          scopes: scopes.stream,
          onScopeChanged: () => invalidations++,
          child: const Scaffold(body: Text('Home')),
        ),
      ),
    );
    AppNavigation.openNotification('cold-start');
    scopes.add('same-user/tenant-a/OPERATOR');
    await tester.pumpAndSettle();
    expect(AppNavigation.requestedNotification.value, 'cold-start');
    unawaited(
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Private')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    scopes.add('same-user/tenant-b/VIEWER');
    await tester.pumpAndSettle();
    expect(find.text('Private'), findsNothing);
    expect(find.text('Home'), findsOneWidget);
    expect(invalidations, 1);
    expect(AppNavigation.requestedNotification.value, isNull);
    await tester.pumpWidget(const SizedBox());
    await identities.close();
    await scopes.close();
  });
}
