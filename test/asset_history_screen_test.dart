import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestionale_radio/asset_history_screen.dart';

void main() {
  testWidgets('renders the selected asset history records', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AssetHistoryScreen(
          assetId: 'asset-1',
          assetName: 'Settore Nord',
          loadHistory: (assetId) async {
            expect(assetId, 'asset-1');
            return [
              {
                'recordType': 'REPORT',
                'reviewStatus': 'APPROVED',
                'timestamp': '2026-09-30T12:30:00Z',
                'operatorName': 'Tecnico 1',
                'taskId': 'task-1',
              },
            ];
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Rapporto di manutenzione'), findsOneWidget);
    expect(find.text('REPORT'), findsOneWidget);
    expect(find.text('Approvato'), findsOneWidget);
    expect(find.text('Tecnico 1'), findsOneWidget);
    expect(find.text('task-1'), findsOneWidget);
  });

  testWidgets('shows an explicit error and retry action when loading fails', (
    tester,
  ) async {
    var attempts = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: AssetHistoryScreen(
          assetId: 'asset-1',
          assetName: 'Settore Nord',
          loadHistory: (assetId) async {
            attempts++;
            if (attempts == 1) {
              throw StateError('offline');
            }
            return [];
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Impossibile caricare la storia dell’asset.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Riprova'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(
      find.text('Nessuna attività registrata per Settore Nord.'),
      findsOneWidget,
    );
  });
}
