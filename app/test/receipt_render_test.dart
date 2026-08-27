import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:karots_trade/core.dart';
import 'package:karots_trade/db.dart';
import 'package:karots_trade/files.dart';
import 'package:karots_trade/store.dart' as s;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Batch;

/// Writes one of every receipt to disk so the layout can be eyeballed, and
/// checks the contact line really is on all of them.
/// PDF text is emitted one word per string literal, so pull the literals back
/// out and re-join them to read the page as a person would.
String pdfText(List<int> bytes) => RegExp(r'\((?:[^()\\]|\\.)*\)')
    .allMatches(latin1.decode(bytes, allowInvalid: true))
    .map((m) => m.group(0)!)
    .map((tok) => tok.substring(1, tok.length - 1))
    .join(' ');

void main() {
  setUp(() async {
    await openDb(path: inMemoryDatabasePath);
    await s.loadSettings();
    await s.setSetting('business_name', 'Karots Traders');
    await s.setSetting('business_phone', '077 123 4567');
  });
  tearDown(closeDb);

  final samples = <String, Receipt>{
    'sale': const Receipt(
      kind: 'Sale',
      no: 7,
      date: 1755930000000,
      customer: 'ABC Shop',
      customerPhone: '0712345678',
      lines: [
        ('Coca-Cola 1L', 10, 18000),
        ('Sprite 1L', 6, 17500),
        ('Milk Powder 400g', 3, 121000),
      ],
      totals: [
        ('Total', 648000),
        ('Paid now', 200000),
        ('From advance', 100000),
        ('Balance due', 348000),
      ],
    ),
    'payment': const Receipt(
      kind: 'Payment',
      no: 12,
      date: 1755930000000,
      customer: 'ABC Shop',
      customerPhone: '0712345678',
      totals: [('Payment received', 50000), ('Still owing', 298000)],
      footnote: 'Received with thanks.',
    ),
    'discounted': const Receipt(
      kind: 'Sale',
      no: 8,
      date: 1755930000000,
      customer: 'ABC Shop',
      customerPhone: '0712345678',
      lines: [
        ('Coca-Cola 1L\nWas Rs. 900 each  -  saved Rs. 100', 4, 87500),
      ],
      totals: [
        ('Total', 350000),
        ('You saved', 10000),
        ('Paid', 0),
        ('Balance due', 350000),
      ],
      footnote: 'Please settle Rs. 3,500 by 30 Aug 2026 (within 7 days).',
    ),
    'cheque': const Receipt(
      kind: 'Cheque',
      no: 2,
      date: 1755930000000,
      customer: 'ABC Shop',
      customerPhone: '0712345678',
      reference: 'Cheque 400123  ·  Sampath  ·  dated 30 Aug 2026',
      totals: [('Cheque amount', 40000), ('Account balance', 70000)],
      footnote:
          'Received as a cheque. The account is credited only once the bank pays it.',
    ),
    'return': const Receipt(
      kind: 'Return',
      no: 3,
      date: 1755930000000,
      customer: 'ABC Shop',
      customerPhone: '0712345678',
      reference: 'Against Sale #7',
      lines: [('Coca-Cola 1L', 2, 18000)],
      totals: [('Returned value', 36000), ('Credited to account', 36000)],
      footnote: 'Stock taken back and the customer account credited.',
    ),
  };

  test('every receipt carries the business header and the contact line',
      () async {
    final out = Directory('${Directory.systemTemp.path}/karots-receipts')
      ..createSync(recursive: true);

    for (final e in samples.entries) {
      File('${out.path}/${e.key}.pdf')
          .writeAsBytesSync(await buildReceipt(e.value));

      final text = pdfText(await buildReceipt(e.value, compress: false));

      expect(text, contains('Karots Traders'), reason: '${e.key}: seller name');
      expect(text, contains('077 123 4567'), reason: '${e.key}: seller phone');
      expect(text, contains('App made by Adhnan'), reason: '${e.key}: credit');
      expect(text, contains('adhnanmsa@gmail.com'), reason: '${e.key}: email');
      expect(text, contains('0769626396'), reason: '${e.key}: phone');
      expect(text, contains('ABC Shop'), reason: '${e.key}: customer');
    }
    stdout.writeln('receipts written to ${out.path}');
  });

  test('the file name is the same shape for every kind', () async {
    expect(samples['sale']!.fileName, 'Sale-0007');
    expect(samples['payment']!.fileName, 'Payment-0012');
    expect(samples['return']!.fileName, 'Return-0003');
    expect(samples['cheque']!.fileName, 'Cheque-0002');
  });

  test('a discounted bill shows what was knocked off, and when to pay',
      () async {
    final text = pdfText(await buildReceipt(samples['discounted']!, compress: false));

    expect(text, contains('Was Rs. 900'), reason: 'the price before the discount');
    expect(text, contains('You saved'));
    expect(text, contains('by 30 Aug 2026'), reason: 'a real date, not "a week"');
  });

  test('a cheque receipt says the money has not arrived yet', () async {
    final text = pdfText(await buildReceipt(samples['cheque']!, compress: false));

    expect(text, contains('400123'), reason: 'which cheque this is');
    expect(text, contains('dated 30 Aug 2026'), reason: 'when it can be banked');
    expect(text, contains('only once the bank pays it'));
  });

  test('the settle-by date is exactly a week after the sale', () {
    final sold = DateTime(2026, 8, 23, 16, 30).millisecondsSinceEpoch;
    expect(onDay(payBy(sold)), '30 Aug 2026');
    expect(creditDays, 7);
  });
}
