import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'core.dart';
import 'db.dart';
import 'store.dart' as s;

// ============================================================ receipts

/// Everything the app can hand to a customer on paper. One shape, so every
/// receipt looks the same and is named the same way.
class Receipt {
  /// Sale, Quotation, Purchase, Return or Payment — also the file name prefix.
  final String kind;
  final int no, date;
  final String? customer, customerPhone, reference, footnote;
  final List<(String name, int qty, int price)> lines;
  final List<(String label, int amount)> totals;

  const Receipt({
    required this.kind,
    required this.no,
    required this.date,
    this.customer,
    this.customerPhone,
    this.reference,
    this.footnote,
    this.lines = const [],
    this.totals = const [],
  });

  /// Sale-0007.pdf, Payment-0012.pdf — same rule for every document.
  String get fileName => '$kind-${no.toString().padLeft(4, '0')}';
  String get number => '${kind[0]}${no.toString().padLeft(4, '0')}';
}

Future<Uint8List> buildReceipt(Receipt r) async {
  final doc = pw.Document(title: r.fileName);
  const grey = PdfColor.fromInt(0xFF6B7280);
  const rule = PdfColor.fromInt(0xFFD1D5DB);
  final business = s.businessName.isEmpty ? 'My Business' : s.businessName;

  pw.Widget label(String v) => pw.Text(v.toUpperCase(),
      style: pw.TextStyle(fontSize: 7, letterSpacing: 1.4, color: grey));

  doc.addPage(pw.Page(
    pageFormat: PdfPageFormat.a5,
    margin: const pw.EdgeInsets.fromLTRB(28, 28, 28, 24),
    build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      // Header: who this is from, and what the document is.
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(business,
                style: pw.TextStyle(fontSize: 17, fontWeight: pw.FontWeight.bold)),
            if (s.businessPhone.isNotEmpty)
              pw.Text(s.businessPhone,
                  style: const pw.TextStyle(fontSize: 9, color: grey)),
          ]),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            label(r.kind),
            pw.Text(r.number,
                style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
            pw.Text(when(r.date), style: const pw.TextStyle(fontSize: 8, color: grey)),
          ]),
        ],
      ),
      pw.SizedBox(height: 10),
      pw.Divider(height: 1, thickness: 1, color: rule),
      pw.SizedBox(height: 10),

      if (r.customer != null) ...[
        label('To'),
        pw.SizedBox(height: 2),
        pw.Text(r.customer!,
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
        if ((r.customerPhone ?? '').isNotEmpty)
          pw.Text(r.customerPhone!, style: const pw.TextStyle(fontSize: 9, color: grey)),
        pw.SizedBox(height: 10),
      ],
      if (r.reference != null) ...[
        pw.Text(r.reference!, style: const pw.TextStyle(fontSize: 9, color: grey)),
        pw.SizedBox(height: 10),
      ],

      if (r.lines.isNotEmpty)
        pw.TableHelper.fromTextArray(
          headers: ['Item', 'Qty', 'Price', 'Amount'],
          headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
          headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF3F4F6)),
          cellStyle: const pw.TextStyle(fontSize: 9),
          cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          border: const pw.TableBorder(
              horizontalInside: pw.BorderSide(color: rule, width: 0.5)),
          columnWidths: {
            0: const pw.FlexColumnWidth(5),
            1: const pw.FlexColumnWidth(1.2),
            2: const pw.FlexColumnWidth(2),
            3: const pw.FlexColumnWidth(2.2),
          },
          cellAlignments: {
            0: pw.Alignment.centerLeft,
            1: pw.Alignment.centerRight,
            2: pw.Alignment.centerRight,
            3: pw.Alignment.centerRight,
          },
          data: [
            for (final (name, qty, price) in r.lines)
              [name, '$qty', money(price), money(qty * price)]
          ],
        ),

      pw.SizedBox(height: 12),
      pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.SizedBox(
          width: 190,
          child: pw.Column(children: [
            for (final (i, (text, amount)) in r.totals.indexed) ...[
              if (i == r.totals.length - 1 && r.totals.length > 1)
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 4),
                  child: pw.Divider(height: 1, thickness: 1, color: rule),
                ),
              pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                pw.Text(text,
                    style: pw.TextStyle(
                        fontSize: i == 0 ? 11 : 10,
                        fontWeight:
                            i == 0 ? pw.FontWeight.bold : pw.FontWeight.normal)),
                pw.Text(money(amount),
                    style: pw.TextStyle(
                        fontSize: i == 0 ? 13 : 10,
                        fontWeight:
                            i == 0 ? pw.FontWeight.bold : pw.FontWeight.normal)),
              ]),
              pw.SizedBox(height: 3),
            ],
          ]),
        ),
      ),

      pw.Spacer(),
      pw.Divider(height: 1, thickness: 0.5, color: rule),
      pw.SizedBox(height: 6),
      pw.Text(r.footnote ?? 'Thank you',
          style: const pw.TextStyle(fontSize: 8, color: grey)),
      pw.SizedBox(height: 3),
      pw.Text(credit, style: const pw.TextStyle(fontSize: 6.5, color: grey)),
    ]),
  ));
  return doc.save();
}

/// Shows the finished receipt first. Nothing leaves the app until the person
/// taps share or print in the preview.
Future<void> showReceipt(BuildContext context, Receipt r) => Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ReceiptScreen(r)),
    );

class ReceiptScreen extends StatelessWidget {
  final Receipt receipt;
  const ReceiptScreen(this.receipt, {super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFF2B2E3B),
        appBar: AppBar(
          backgroundColor: const Color(0xFF2B2E3B),
          title: Text('${t(receipt.kind)} ${receipt.number}'),
        ),
        body: PdfPreview(
          build: (_) => buildReceipt(receipt),
          pdfFileName: '${receipt.fileName}.pdf',
          canChangePageFormat: false,
          canChangeOrientation: false,
          canDebug: false,
          useActions: true,
          allowPrinting: true,
          allowSharing: true,
          initialPageFormat: PdfPageFormat.a5,
          padding: const EdgeInsets.all(12),
          loadingWidget: const Center(child: CircularProgressIndicator()),
        ),
      );
}

// ============================================================ backup

/// Everything, including product photos (base64) — a backup that restores
/// products without their images is not a backup.
Future<Uint8List> exportBackup() async {
  final data = <String, Object?>{'version': 2, 'at': DateTime.now().toIso8601String()};
  for (final table in tables) {
    data[table] = (await db.query(table))
        .map((r) => r.map((k, v) => MapEntry(k, v is Uint8List ? {'b64': base64Encode(v)} : v)))
        .toList();
  }
  return Uint8List.fromList(utf8.encode(jsonEncode(data)));
}

/// Opens the system "save as" dialog (SAF on Android) so the user picks where
/// the backup lands — Downloads, Drive, an SD card, whatever they trust.
Future<bool> saveBackup() async {
  final bytes = await exportBackup();
  final name = 'karots-backup-${DateTime.now().toIso8601String().substring(0, 10)}.json';
  final uri = await FilePicker.saveFile(
      fileName: name, bytes: bytes, mimeType: 'application/json');
  return uri != null;
}

/// Replaces all existing data with the backup contents, in one transaction:
/// a failed import leaves the current database untouched.
Future<void> importBackup(Uint8List bytes) async {
  final Object? parsed = jsonDecode(utf8.decode(bytes));
  if (parsed is! Map || parsed['products'] == null) {
    throw Exception('This file is not a valid backup');
  }
  await db.transaction((tx) async {
    await wipe(tx);
    for (final table in tables) {
      for (final row in (parsed[table] as List? ?? const [])) {
        await tx.insert(
            table,
            (row as Map).map((k, v) => MapEntry(
                k as String,
                v is Map && v['b64'] != null
                    ? base64Decode(v['b64'] as String)
                    : v as Object?)));
      }
    }
  });
}

Future<Uint8List?> pickBackupFile() async {
  final f = await FilePicker.pickFile();
  return f == null ? null : await f.readAsBytes();
}
