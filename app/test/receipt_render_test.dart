import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:karots_trade/core.dart';
import 'package:karots_trade/db.dart';
import 'package:karots_trade/files.dart';
import 'package:karots_trade/models.dart';
import 'package:karots_trade/screens/history.dart';
import 'package:karots_trade/store.dart' as s;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Batch;

/// Writes one of every receipt to disk so the layout can be eyeballed, and
/// checks the contact line really is on all of them.
/// PDF text is emitted one word per string literal, so pull the literals back
/// out and re-join them to read the page as a person would.
int rs(num v) => (v * 100).round();

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
          'The account has been credited. Bankable from 30 Aug 2026; if it is '
          'returned unpaid the amount goes back on.',
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
    'outstanding': const Receipt(
      kind: 'Outstanding',
      no: 0,
      date: 1755930000000,
      customer: 'ABC Shop',
      customerPhone: '0712345678',
      reference: 'Amounts still to be paid as on 23 Aug 2026',
      statement: [
        ('12 Jul 2026', 'Balance brought forward', 200000, 200000),
        ('2 Aug 2026', 'Sale #9  ·  due 9 Aug 2026  (overdue)', 400000, 600000),
        ('4 Aug 2026', 'Payment received', -100000, 500000),
        ('9 Aug 2026', 'Cheque 400123', -40000, 460000),
        ('20 Aug 2026', 'Sale #14  ·  due 27 Aug 2026', 180000, 640000),
      ],
      totals: [('Total to pay', 640000), ('Of that, overdue', 300000)],
      notes: [
        'Cheque 400123 (Sampath) for Rs. 400 is listed above and has already '
            'been taken off this total. It can be banked on 30 Aug 2026, '
            '7 days from now.',
        'If a cheque is returned unpaid, its amount comes back onto this total.',
      ],
      footnote: 'Bills settled before the first line above are not listed. '
          'Ask for a full statement to see every payment on the account.',
    ),
    'statement': const Receipt(
      kind: 'Statement',
      no: 0,
      date: 1755930000000,
      customer: 'ABC Shop',
      customerPhone: '0712345678',
      reference: 'Account as it stands on 23 Aug 2026',
      statement: [
        ('1 Jun 2026', 'Balance brought forward', 200000, 200000),
        ('12 Jul 2026', 'Sale #7', 648000, 848000),
        ('12 Jul 2026', 'Payment received', -200000, 648000),
        ('20 Jul 2026', 'Goods returned #3', -36000, 612000),
        ('2 Aug 2026', 'Cheque 400123', -40000, 572000),
      ],
      totals: [
        ('Balance due', 572000),
        ('Total billed', 848000),
        ('Total paid', 276000),
      ],
      notes: [
        'Cheque 400123 (Sampath) for Rs. 400 is already taken off this balance. '
            'It can be banked on 30 Aug 2026, 7 days from now.',
        'If a cheque is returned unpaid, its amount goes back onto the balance.',
      ],
      footnote: 'This statement lists every entry on the account to date.',
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
    // A statement is the account as it stands today, not a numbered document.
    expect(samples['statement']!.fileName, 'Statement-2025-08-23');
    expect(samples['statement']!.number, '');
    expect(samples['outstanding']!.fileName, 'Outstanding-2025-08-23');
  });

  test('an outstanding report shows only open bills and the money in between',
      () async {
    final text =
        pdfText(await buildReceipt(samples['outstanding']!, compress: false));

    expect(text, contains('Balance brought forward'),
        reason: 'everything settled before the first open bill, in one line');
    expect(text, contains('Sale #9'), reason: 'an unfinished bill');
    expect(text, contains('overdue'), reason: 'and that it is late');
    expect(text, contains('Payment received'),
        reason: 'the payments that landed in between');
    expect(text, contains('Cheque 400123'),
        reason: 'a cheque not yet at the bank is still on the document');
    expect(text, contains('-Rs. 400'), reason: 'and shown subtracted');
    expect(text, contains('Total to pay'));
    expect(text, contains('Of that, overdue'));
  });

  test('a statement shows every entry, the running balance and the cheques',
      () async {
    final text =
        pdfText(await buildReceipt(samples['statement']!, compress: false));

    expect(text, contains('Balance brought forward'),
        reason: 'what was owed before any of this');
    expect(text, contains('Sale #7'), reason: 'the reference, not just a figure');
    expect(text, contains('12 Jul 2026'), reason: 'when it was owed');
    expect(text, contains('-Rs. 2,000'), reason: 'credits read as credits');
    expect(text, contains('Rs. 6,120'), reason: 'the balance after each line');
    expect(text, contains('Total billed'));
    expect(text, contains('Total paid'));
    expect(text, contains('already taken off this balance'),
        reason: 'the cheque is deducted and says so');
    expect(text, contains('7 days from now'), reason: 'how long it has left');
  });

  test('a discounted bill shows what was knocked off, and when to pay',
      () async {
    final text = pdfText(await buildReceipt(samples['discounted']!, compress: false));

    expect(text, contains('Was Rs. 900'), reason: 'the price before the discount');
    expect(text, contains('You saved'));
    expect(text, contains('by 30 Aug 2026'), reason: 'a real date, not "a week"');
  });

  test('a cheque receipt says the account is already credited', () async {
    final text = pdfText(await buildReceipt(samples['cheque']!, compress: false));

    expect(text, contains('400123'), reason: 'which cheque this is');
    expect(text, contains('dated 30 Aug 2026'), reason: 'when it can be banked');
    expect(text, contains('has been credited'),
        reason: 'the money comes off the balance the day the cheque arrives');
  });

  test('a new bill shows the old debt and one figure to pay', () async {
    await s.savePurchase(
        [BuyLine(name: 'Soap', cost: rs(50), price: rs(70), qty: 100)]);
    final soap = (await s.products()).single;
    final batch = (await s.batches(soap.id)).single;
    final cid = await s.saveCustomer(name: 'ABC Shop', phone: '0712345678');

    // An older bill left unpaid, then a new one written today.
    await s.saveDoc(customerId: cid, quote: false, lines: [
      SellLine(
          productId: soap.id, batchId: batch.id, name: 'Soap',
          price: rs(70), qty: 10)
    ]);
    final now = await s.saveDoc(customerId: cid, quote: false, lines: [
      SellLine(
          productId: soap.id, batchId: batch.id, name: 'Soap',
          price: rs(70), qty: 4)
    ]);

    final d = (await s.doc(now))!;
    final r = saleReceipt(d, await s.docItems(now), await s.balance(cid));
    final text = pdfText(await buildReceipt(r, compress: false));

    expect(text, contains('Earlier dues'), reason: 'the old bill is on this one');
    expect(text, contains('Rs. 700'), reason: 'what was already owed');
    expect(text, contains('Total to pay'));
    expect(text, contains('Rs. 980'), reason: 'Rs. 700 owed plus this Rs. 280');
  });

  test('a bill for a customer who owes nothing else stays plain', () async {
    await s.savePurchase(
        [BuyLine(name: 'Soap', cost: rs(50), price: rs(70), qty: 100)]);
    final soap = (await s.products()).single;
    final batch = (await s.batches(soap.id)).single;
    final cid = await s.saveCustomer(name: 'ABC Shop');
    final only = await s.saveDoc(customerId: cid, quote: false, lines: [
      SellLine(
          productId: soap.id, batchId: batch.id, name: 'Soap',
          price: rs(70), qty: 4)
    ]);

    final d = (await s.doc(only))!;
    final r = saleReceipt(d, await s.docItems(only), await s.balance(cid));

    expect(r.totals.map((t) => t.$1), isNot(contains('Earlier dues')),
        reason: 'no old debt, no extra line to explain');
  });

  test('the settle-by date is exactly a week after the sale', () {
    final sold = DateTime(2026, 8, 23, 16, 30).millisecondsSinceEpoch;
    expect(onDay(payBy(sold)), '30 Aug 2026');
    expect(creditDays, 7);
  });
}
