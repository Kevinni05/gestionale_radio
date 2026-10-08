import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestionale_radio/new_report_screen.dart';
import 'package:gestionale_radio/widgets/calendar_notes.dart';
import 'package:gestionale_radio/widgets/personal_badge.dart';
import 'package:gestionale_radio/widgets/radiotech_safe_area.dart';
import 'package:gestionale_radio/theme/radiotech_theme.dart';

Widget app(Widget screen) =>
    MaterialApp(theme: RadioTechTheme.dark, home: screen);
Uint8List png() {
  final header = BytesBuilder()..add([137, 80, 78, 71, 13, 10, 26, 10]);
  void chunk(String name, List<int> data) {
    final body = [...ascii.encode(name), ...data];
    int crc = 0xffffffff;
    for (final byte in body) {
      crc ^= byte;
      for (int i = 0; i < 8; i++) {
        crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xedb88320 : crc >> 1;
      }
    }
    final len = ByteData(4)..setUint32(0, data.length);
    final end = ByteData(4)..setUint32(0, crc ^ 0xffffffff);
    header
      ..add(len.buffer.asUint8List())
      ..add(body)
      ..add(end.buffer.asUint8List());
  }

  final ihdr = ByteData(13)
    ..setUint32(0, 1)
    ..setUint32(4, 1)
    ..setUint8(8, 8)
    ..setUint8(9, 6);
  chunk('IHDR', ihdr.buffer.asUint8List());
  chunk('IDAT', zlib.encode([0, 0, 0, 0, 255]));
  chunk('IEND', []);
  return header.toBytes();
}

void main() {
  testWidgets(
    'global safe area protects bottom buttons and dialog navigation',
    (tester) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 720),
              padding: EdgeInsets.only(bottom: 48),
              viewPadding: EdgeInsets.only(bottom: 48),
            ),
            child: RadioTechSafeArea(child: child!),
          ),
          home: Scaffold(
            body: const Text('Contenuto'),
            bottomNavigationBar: Builder(
              builder: (context) => FilledButton(
                key: const Key('bottom'),
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Dialogo'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Chiudi'),
                      ),
                    ],
                  ),
                ),
                child: const Text('Apri'),
              ),
            ),
          ),
        ),
      );
      expect(
        tester.getRect(find.byKey(const Key('bottom'))).bottom,
        lessThanOrEqualTo(672),
      );
      await tester.tap(find.byKey(const Key('bottom')));
      await tester.pumpAndSettle();
      expect(find.text('Dialogo'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('report selects a real antenna and merges its dynamic controls', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      app(
        NewReportScreen(
          loadAntennas: () async => [
            {
              'id': 'antenna-real',
              'name': 'Ponte Bari',
              'checklistTemplate': ['Verifica puntamento specifico'],
            },
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    final continueButton = find.byKey(const Key('reportContinue'));
    await tester.scrollUntilVisible(
      continueButton,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.widget<FilledButton>(continueButton).onPressed, isNull);
    final dropdown = find.byType(DropdownButtonFormField<String>).first;
    await tester.scrollUntilVisible(
      dropdown,
      -250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ponte Bari').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Verifica puntamento specifico'),
      150,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Verifica puntamento specifico'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<CheckboxListTile>(
            find.ancestor(
              of: find.text('Verifica puntamento specifico'),
              matching: find.byType(CheckboxListTile),
            ),
          )
          .value,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'calendar edits persist to the personal API and are shown after reload',
    (tester) async {
      final writes = <Map<String, dynamic>>[];
      var note = 'Nota originale';
      final today = DateTime.now();
      final day =
          '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      await tester.pumpWidget(
        app(
          Scaffold(
            body: SingleChildScrollView(
              child: CalendarNotes(
                request: (path, {method = 'GET', body}) async {
                  if (method == 'PUT') {
                    writes.add(body!);
                    note = body['note'];
                    return body;
                  }
                  return [
                    {'day': day, 'note': note},
                  ];
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Nota sincronizzata');
      await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'Salva nota'),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Salva nota'));
      await tester.pumpAndSettle();
      expect(writes.single['note'], 'Nota sincronizzata');
      expect(writes.single['reminderAt'], isNull);
      expect(find.text('Nota sincronizzata'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'personal badge refreshes after revision changes and password reset',
    (tester) async {
      final image = 'data:image/png;base64,${base64Encode(png())}';
      int reads = 0, resets = 0;
      await tester.pumpWidget(
        app(
          Scaffold(
            body: SingleChildScrollView(
              child: PersonalBadge(
                request: (path, {method = 'GET', body}) async {
                  if (method == 'POST') {
                    resets++;
                    return {'message': 'Email inviata e badge rigenerato.'};
                  }
                  reads++;
                  return {
                    'imageDataUrl': image,
                    'payload': 'token-$reads',
                    'expiresAt': null,
                    'revision': '$reads',
                  };
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Salva QR sul dispositivo'), findsOneWidget);
      final before = reads;
      await tester.pump(const Duration(seconds: 31));
      await tester.pump();
      expect(reads, greaterThan(before));
      await tester.ensureVisible(find.text('Reimposta password'));
      await tester.tap(find.text('Reimposta password'));
      await tester.pumpAndSettle();
      expect(resets, 1);
      expect(reads, greaterThan(before + 1));
      await tester.pumpWidget(const SizedBox());
    },
  );
}
