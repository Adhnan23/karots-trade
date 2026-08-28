import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
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

  /// A running account, printed instead of item lines: every entry with the
  /// balance as it stood right after it. A figure on its own invites an
  /// argument; the same figure with the dates that built it does not.
  final List<(String date, String detail, int amount, int balance)> statement;

  /// Plain sentences under the totals — where a statement spells out the
  /// cheques it has already credited but the bank has not reached yet.
  final List<String> notes;

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
    this.statement = const [],
    this.notes = const [],
  });

  /// Sale-0007.pdf, Payment-0012.pdf — same rule for every document.
  ///
  /// A statement is the one thing here with no number of its own: it is not a
  /// document that was issued once, it is the account as it stands today.
  String get fileName => no == 0
      ? '$kind-${DateTime.fromMillisecondsSinceEpoch(date).toIso8601String().substring(0, 10)}'
      : '$kind-${no.toString().padLeft(4, '0')}';
  String get number => no == 0 ? '' : '${kind[0]}${no.toString().padLeft(4, '0')}';
}

/// [compress] is only turned off by tests, so they can read the text back out
/// of the produced bytes.
Future<Uint8List> buildReceipt(Receipt r, {bool compress = true}) async {
  final doc = pw.Document(title: r.fileName, compress: compress);
  const grey = PdfColor.fromInt(0xFF6B7280);
  const rule = PdfColor.fromInt(0xFFD1D5DB);
  final business = s.businessName.isEmpty ? 'My Business' : s.businessName;

  pw.Widget label(String v) => pw.Text(v.toUpperCase(),
      style: pw.TextStyle(fontSize: 7, letterSpacing: 1.4, color: grey));

  // A logo the PDF library cannot decode must not cost the seller a receipt,
  // so a bad one simply does not print.
  pw.ImageProvider? logo;
  final logoBytes = s.businessLogo;
  if (logoBytes != null) {
    try {
      logo = pw.MemoryImage(logoBytes);
    } catch (_) {
      logo = null;
    }
  }

  final head = <pw.Widget>[
    // Header: who this is from, and what the document is.
    pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          if (logo != null) ...[
            pw.SizedBox(
                width: 40,
                height: 40,
                child: pw.Image(logo, fit: pw.BoxFit.contain)),
            pw.SizedBox(width: 10),
          ],
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(business,
                style: pw.TextStyle(fontSize: 17, fontWeight: pw.FontWeight.bold)),
            if (s.businessPhone.isNotEmpty)
              pw.Text(s.businessPhone,
                  style: const pw.TextStyle(fontSize: 9, color: grey)),
          ]),
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
  ];

  final body = <pw.Widget>[
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

      if (r.statement.isNotEmpty)
        pw.TableHelper.fromTextArray(
          headers: const ['Date', 'Detail', 'Amount', 'Balance'],
          headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
          headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF3F4F6)),
          cellStyle: const pw.TextStyle(fontSize: 8.5),
          cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
          border: const pw.TableBorder(
              horizontalInside: pw.BorderSide(color: rule, width: 0.5)),
          columnWidths: {
            0: const pw.FlexColumnWidth(2.4),
            1: const pw.FlexColumnWidth(4.2),
            2: const pw.FlexColumnWidth(2.2),
            3: const pw.FlexColumnWidth(2.2),
          },
          cellAlignments: {
            0: pw.Alignment.centerLeft,
            1: pw.Alignment.centerLeft,
            2: pw.Alignment.centerRight,
            3: pw.Alignment.centerRight,
          },
          data: [
            for (final (date, detail, amount, balance) in r.statement)
              [
                date,
                detail,
                // Signed, so the customer can read which way each line moved
                // the account without a legend.
                '${amount < 0 ? '-' : ''}${money(amount.abs())}',
                money(balance),
              ]
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

      if (r.notes.isNotEmpty) ...[
        pw.SizedBox(height: 10),
        for (final n in r.notes) ...[
          // A dash, not a bullet: the built-in PDF font has no glyph for one
          // and silently drops it.
          pw.Text('-  $n', style: const pw.TextStyle(fontSize: 8.5)),
          pw.SizedBox(height: 2),
        ],
      ],
  ];

  final tail = <pw.Widget>[
    pw.Divider(height: 1, thickness: 0.5, color: rule),
    pw.SizedBox(height: 6),
    pw.Text(r.footnote ?? 'Thank you',
        style: const pw.TextStyle(fontSize: 8, color: grey)),
    pw.SizedBox(height: 3),
    pw.Text(credit, style: const pw.TextStyle(fontSize: 6.5, color: grey)),
  ];

  const format = PdfPageFormat.a5;
  const margin = pw.EdgeInsets.fromLTRB(28, 28, 28, 24);

  if (r.statement.isEmpty) {
    // One page, with the footnote pushed to the bottom of it.
    doc.addPage(pw.Page(
      pageFormat: format,
      margin: margin,
      build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [...head, ...body, pw.Spacer(), ...tail]),
    ));
  } else {
    // An account with a year on it does not fit a page, and cutting it off is
    // the one thing a statement must not do.
    doc.addPage(pw.MultiPage(
      pageFormat: format,
      margin: margin,
      build: (_) => [...head, ...body],
      footer: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          mainAxisSize: pw.MainAxisSize.min,
          children: tail),
    ));
  }
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
          title: Text('${t(receipt.kind)} ${receipt.number}'.trim()),
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

// ---------------------------------------------------------------- undo import

/// Importing replaces everything. One wrong file should not be the end of the
/// books, so the app keeps its own copy of what was there just before — inside
/// its own storage, where it can hand it straight back.
Future<File> _rollbackFile() async =>
    File(p.join((await getApplicationDocumentsDirectory()).path,
        'karots-before-import.json'));

/// Takes the safety copy first, then imports. If the import throws, the
/// database is untouched and the copy is simply a spare.
Future<void> importBackupSafely(Uint8List bytes) async {
  await (await _rollbackFile()).writeAsBytes(await exportBackup(), flush: true);
  await importBackup(bytes);
}

/// When the app last replaced everything, or null if it never has.
Future<DateTime?> lastImportUndoPoint() async {
  final f = await _rollbackFile();
  return await f.exists() ? f.lastModified() : null;
}

/// Puts back whatever was there before the last import.
Future<void> undoLastImport() async {
  final f = await _rollbackFile();
  if (!await f.exists()) throw Exception('There is nothing to undo');
  await importBackup(await f.readAsBytes());
}
