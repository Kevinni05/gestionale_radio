import 'app_branding.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../widgets/radiotech_clock.dart';

class ReportPhoto {
  const ReportPhoto(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
}

/// Uses bundled branding and fonts, so document generation works offline.
class MaintenanceReportPdf {
  static Future<Uint8List> build({
    required String antennaId,
    required String antennaName,
    required String operatorName,
    required DateTime submittedAt,
    required String notes,
    String? taskId,
    String findings = '',
    Map<String, bool> checklist = const {},
    Map<String, double> measurements = const {},
    List<Map<String, dynamic>> materials = const [],
    List<ReportPhoto> photos = const [],
    Uint8List? signature,
  }) async {
    final font = pw.Font.ttf(
      await rootBundle.load('assets/fonts/InterVariable.ttf'),
    );
    final logo = pw.MemoryImage(
      (await rootBundle.load(
        'assets/brand/radiotech-symbol-v1.png',
      )).buffer.asUint8List(),
    );
    final document = pw.Document(
      title: 'Rapporto di manutenzione - $antennaName',
      author: operatorName,
      creator: AppBranding.pdfBrand,
    );
    const ink = PdfColor.fromInt(0xff182333);
    const muted = PdfColor.fromInt(0xff596575);
    const line = PdfColor.fromInt(0xffd9e0e8);
    final local = submittedAt.toLocal();
    final timestamp =
        '${ItalianDate.day(local)} - ${ItalianDate.time(local)} (UTC${local.timeZoneOffset.isNegative ? '-' : '+'}${local.timeZoneOffset.inMinutes.abs() ~/ 60}:${(local.timeZoneOffset.inMinutes.abs() % 60).toString().padLeft(2, '0')})';
    pw.Widget section(String title) => pw.Padding(
      padding: const pw.EdgeInsets.only(top: 20, bottom: 9),
      child: pw.Text(
        title.toUpperCase(),
        style: pw.TextStyle(
          fontSize: 10,
          fontWeight: pw.FontWeight.bold,
          color: ink,
          letterSpacing: 1,
        ),
      ),
    );
    pw.Widget table(List<List<String>> rows) => pw.TableHelper.fromTextArray(
      context: null,
      data: rows,
      headerCount: 0,
      border: pw.TableBorder.all(color: line, width: .5),
      cellPadding: const pw.EdgeInsets.all(8),
      cellStyle: const pw.TextStyle(fontSize: 10),
      columnWidths: {
        0: const pw.FlexColumnWidth(2),
        1: const pw.FlexColumnWidth(3),
      },
    );
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(40, 35, 40, 40),
        maxPages: 200,
        theme: pw.ThemeData.withFont(base: font, bold: font),
        header: (context) => pw.Container(
          padding: const pw.EdgeInsets.only(bottom: 12),
          decoration: const pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: line)),
          ),
          child: pw.Row(
            children: [
              pw.Container(
                width: 42,
                height: 42,
                padding: const pw.EdgeInsets.all(5),
                decoration: const pw.BoxDecoration(color: ink),
                child: pw.Image(logo),
              ),
              pw.SizedBox(width: 12),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      AppBranding.upperName,
                      style: pw.TextStyle(
                        fontSize: 19,
                        fontWeight: pw.FontWeight.bold,
                        color: ink,
                      ),
                    ),
                    pw.Text(
                      'Operations Suite | Rapporto tecnico',
                      style: const pw.TextStyle(fontSize: 9, color: muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        footer: (context) => pw.Container(
          padding: const pw.EdgeInsets.only(top: 10),
          decoration: const pw.BoxDecoration(
            border: pw.Border(top: pw.BorderSide(color: line)),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                '${AppBranding.name} | Documentazione intervento',
                style: const pw.TextStyle(fontSize: 8, color: muted),
              ),
              pw.Text(
                'Pagina ${context.pageNumber} di ${context.pagesCount}',
                style: const pw.TextStyle(fontSize: 8, color: muted),
              ),
            ],
          ),
        ),
        build: (_) => [
          pw.SizedBox(height: 20),
          pw.Text(
            'Rapporto di manutenzione',
            style: pw.TextStyle(
              fontSize: 23,
              fontWeight: pw.FontWeight.bold,
              color: ink,
            ),
          ),
          pw.SizedBox(height: 14),
          table([
            ['Antenna / impianto', antennaName],
            ['Codice asset', antennaId],
            ['Operatore', operatorName],
            ['Data e ora invio dal dispositivo', timestamp],
            if (taskId != null) ['Incarico', taskId],
          ]),
          section('Lavoro eseguito e note operative'),
          pw.Text(
            notes.isEmpty ? 'Non indicato.' : notes,
            style: const pw.TextStyle(fontSize: 11, lineSpacing: 4),
          ),
          section('Controlli eseguiti'),
          if (checklist.isEmpty)
            pw.Text('Nessuna checklist registrata.')
          else
            table(
              checklist.entries
                  .map(
                    (e) => [e.key, e.value ? 'VERIFICATO' : 'NON VERIFICATO'],
                  )
                  .toList(),
            ),
          section('Misure tecniche'),
          if (measurements.isEmpty)
            pw.Text('Nessuna misura registrata.')
          else
            table(
              measurements.entries
                  .map((e) => [e.key, e.value.toString()])
                  .toList(),
            ),
          section('Materiali e ricambi utilizzati'),
          if (materials.isEmpty)
            pw.Text('Nessun materiale sostituito.')
          else
            table(
              materials
                  .map(
                    (m) => [m['name'].toString(), 'Quantità: ${m['quantity']}'],
                  )
                  .toList(),
            ),
          if (findings.isNotEmpty) ...[
            section('Segnalazione alla centrale'),
            pw.Text(findings),
          ],
          section('Firma dell’operatore'),
          pw.Text(operatorName, style: const pw.TextStyle(fontSize: 11)),
          pw.SizedBox(height: 8),
          if (signature != null && signature.isNotEmpty)
            pw.Container(
              height: 80,
              width: 240,
              alignment: pw.Alignment.centerLeft,
              child: pw.Image(
                pw.MemoryImage(signature),
                fit: pw.BoxFit.contain,
              ),
            )
          else
            pw.Text(
              'Nessuna firma acquisita.',
              style: const pw.TextStyle(fontSize: 10, color: muted),
            ),
          pw.SizedBox(height: 8),
          pw.Text(
            'Invio dal dispositivo: $timestamp',
            style: const pw.TextStyle(fontSize: 9, color: muted),
          ),
          if (photos.isEmpty) ...[
            section('Documentazione fotografica'),
            pw.Text('Nessuna fotografia allegata.'),
          ],
          for (var i = 0; i < photos.length; i++) ...[
            pw.NewPage(),
            section(
              'Documentazione fotografica - ${i + 1} di ${photos.length}',
            ),
            pw.Text(
              photos[i].name,
              style: const pw.TextStyle(fontSize: 10, color: muted),
            ),
            pw.SizedBox(height: 14),
            pw.Container(
              height: 460,
              alignment: pw.Alignment.center,
              child: pw.Image(
                pw.MemoryImage(photos[i].bytes),
                fit: pw.BoxFit.contain,
              ),
            ),
            pw.SizedBox(height: 12),
            pw.Text(
              '$antennaName | $operatorName',
              style: const pw.TextStyle(fontSize: 10, color: muted),
            ),
          ],
        ],
      ),
    );
    return document.save();
  }
}
