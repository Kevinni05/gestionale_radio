import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gestionale_radio/login_screen.dart';
import 'package:gestionale_radio/services/api_service.dart';

void main() {
  testWidgets('backend button opens and saves configuration on a small phone', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
    await tester.pumpAndSettle();
    final button = find.byKey(const ValueKey('configure-backend'));
    expect(button, findsOneWidget);
    expect(find.text('Configura Server Backend'), findsOneWidget);
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('Server Backend API'), findsOneWidget);
    final address = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(address, 'http://192.168.1.227:8080');
    await tester.tap(find.text('Salva'));
    await tester.pumpAndSettle();
    expect(ApiService.baseUrl, 'http://192.168.1.227:8080');
    expect(find.text('Centrale: http://192.168.1.227:8080'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('api_base_url'), 'http://192.168.1.227:8080');
  });
}
