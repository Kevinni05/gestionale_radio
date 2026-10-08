import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestionale_radio/theme/radiotech_backdrop.dart';
import 'package:gestionale_radio/theme/radiotech_theme.dart';
import 'package:gestionale_radio/login_screen.dart';

void main() {
  for (final size in [
    const Size(320, 640),
    const Size(740, 360),
    const Size(1024, 768),
  ]) {
    testWidgets('branded login remains scrollable with large text at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: RadioTechTheme.dark,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: true,
              textScaler: const TextScaler.linear(1.6),
            ),
            child: RadioTechBackdrop(child: child!),
          ),
          home: const LoginScreen(),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.bySemanticsLabel('Logo RadioTech'), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const ValueKey('configure-backend')),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('configure-backend')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Server Backend API'), findsOneWidget);
    });
  }
}
