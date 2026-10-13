import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gestionale_radio/report_closure_screen.dart';
import 'package:gestionale_radio/services/report_draft_store.dart';

class NavigationDraftStore extends ReportDraftStore {
  Map<String, dynamic>? saved;
  bool fail = false;
  Future<Map<String, dynamic>?>? restoration;
  @override
  Future<Map<String, dynamic>?> load(String key) async =>
      restoration == null ? saved : await restoration;
  @override
  Future<void> save(String key, Map<String, dynamic> draft) async {
    if (fail) throw StateError('Disk unavailable');
    saved = draft;
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  Future<void> open(WidgetTester tester, NavigationDraftStore store) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ReportClosureScreen(
                    antennaId: 'GENERICO',
                    checklistResults: {'Controllo': false},
                    draftKey: 'report_draft_navigation',
                    draftStore: store,
                    loadInventory: () async => [],
                    loadIdentity: () async => {
                      'antennaName': 'QA',
                      'operatorName': 'QA',
                    },
                  ),
                ),
              ),
              child: const Text('Apri report'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Apri report'));
    await tester.pumpAndSettle();
  }

  Future<void> typeNotes(WidgetTester tester) async {
    final notes = find.byKey(const ValueKey('report-notes'));
    await tester.scrollUntilVisible(
      notes,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(notes, 'Lavoro sul campo da conservare');
  }

  testWidgets(
    'back within the debounce window saves the latest notes before leaving',
    (tester) async {
      final store = NavigationDraftStore();
      await open(tester, store);
      await typeNotes(tester);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Apri report'), findsOneWidget);
      expect(store.saved?['notes'], 'Lavoro sul campo da conservare');
      expect(store.saved?['savedAt'], isNotNull);
    },
  );
  testWidgets(
    'failed persistence blocks interactive exit and keeps the form editable',
    (tester) async {
      final store = NavigationDraftStore()..fail = true;
      await open(tester, store);
      await typeNotes(tester);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.byType(ReportClosureScreen), findsOneWidget);
      expect(find.textContaining('Uscita sospesa'), findsOneWidget);
      store.fail = false;
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(store.saved?['notes'], 'Lavoro sul campo da conservare');
      expect(find.text('Apri report'), findsOneWidget);
    },
  );
  testWidgets(
    'slow draft restoration prevents edits from being overwritten by hydration',
    (tester) async {
      final restored = Completer<Map<String, dynamic>?>();
      final store = NavigationDraftStore()..restoration = restored.future;
      await open(tester, store);
      expect(find.text('Recupero della bozza…'), findsOneWidget);
      final absorption = tester.widget<AbsorbPointer>(
        find.byKey(const ValueKey('report-form-editable')),
      );
      expect(absorption.absorbing, isTrue);
      restored.complete({
        'notes': 'Bozza precedente',
        'checklist': {'Controllo': true},
      });
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('report-notes')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('report-notes')))
            .controller
            ?.text,
        'Bozza precedente',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    },
  );
}
