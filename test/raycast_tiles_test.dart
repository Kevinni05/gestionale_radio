import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestionale_radio/widgets/radiotech_action_tile.dart';
import 'package:gestionale_radio/theme/radiotech_theme.dart';

void main() {
  for (final scale in [1.0, 1.8]) {
    testWidgets(
      'action tiles keep equal dimensions, fit text and respond at scale $scale',
      (tester) async {
        tester.view.physicalSize = const Size(430, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var taps = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: RadioTechTheme.dark,
            home: MediaQuery(
              data: MediaQueryData(
                textScaler: TextScaler.linear(scale),
                disableAnimations: true,
              ),
              child: Scaffold(
                body: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: RadioTechActionTile(
                        title: 'Incarichi',
                        subtitle: 'Avvia e completa',
                        icon: Icons.assignment_outlined,
                        onTap: () => taps++,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: RadioTechActionTile(
                        title: 'Agenda interventi',
                        subtitle: 'Scadenze e pianificazione',
                        icon: Icons.calendar_month_outlined,
                        onTap: () => taps++,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester.getSize(find.byType(RadioTechActionTile).first),
          tester.getSize(find.byType(RadioTechActionTile).last),
        );
        await tester.tap(find.text('Incarichi'));
        await tester.pumpAndSettle();
        expect(taps, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
