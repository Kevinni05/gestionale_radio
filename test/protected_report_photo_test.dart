import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestionale_radio/features/reports/protected_report_photo.dart';

void main() {
  final png = File('assets/brand/radiotech-symbol-v1.png').readAsBytesSync();
  testWidgets(
    'preview waits for decrypted bytes and displays the decoded photo',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final read = Completer<Uint8List>();
      await tester.pumpWidget(
        MaterialApp(home: ProtectedReportPhoto(bytes: read.future)),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      read.complete(png);
      await tester.pumpAndSettle();
      final image = tester.widget<Image>(find.byType(Image));
      expect((image.image as MemoryImage).bytes, same(png));
      expect(find.bySemanticsLabel('Foto allegata'), findsOneWidget);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );
  testWidgets(
    'authentication failure shows a useful error and can recover with a new read',
    (tester) async {
      final read = Completer<Uint8List>();
      await tester.pumpWidget(
        MaterialApp(home: ProtectedReportPhoto(bytes: read.future)),
      );
      read.completeError(StateError('private archive details'));
      await tester.pumpAndSettle();
      expect(find.text('Foto non leggibile'), findsOneWidget);
      expect(find.textContaining('private archive'), findsNothing);
      await tester.pumpWidget(
        MaterialApp(home: ProtectedReportPhoto(bytes: Future.value(png))),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsOneWidget);
      expect(find.text('Foto non leggibile'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
