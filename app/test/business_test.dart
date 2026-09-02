import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:karots_trade/db.dart';
import 'package:karots_trade/files.dart';
import 'package:karots_trade/models.dart';
import 'package:karots_trade/screens/customers.dart';
import 'package:karots_trade/store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Batch;

/// Rs. 150.00 -> 15000 cents
int rs(num v) => (v * 100).round();

Future<String> buy(String name,
    {String? productId, required int cost, required int price, required int qty}) async {
  await savePurchase([
    BuyLine(productId: productId, name: name, cost: cost, price: price, qty: qty)
  ]);
  return (await products(q: name)).first.id;
}

void main() {
  setUp(() async => openDb(path: inMemoryDatabasePath));
  tearDown(closeDb);

  group('batches', () {
    test('different prices create separate batches, same price tops up', () async {
      final id = await buy('Coca-Cola 1L', cost: rs(150), price: rs(180), qty: 20);
      await buy('Coca-Cola 1L', productId: id, cost: rs(160), price: rs(190), qty: 15);

      var bs = await batches(id);
      expect(bs.length, 2);
      expect((await product(id))!.stock, 35);
      expect(bs[0].price, rs(180));
      expect(bs[1].price, rs(190));

      // Same cost/price pair again — no third batch, quantity grows instead.
      await buy('Coca-Cola 1L', productId: id, cost: rs(150), price: rs(180), qty: 5);
      bs = await batches(id);
      expect(bs.length, 2);
      expect(bs[0].qtyLeft, 25);
      expect(bs[0].qtyIn, 25);
      expect((await product(id))!.stock, 40);
    });

    test('purchase history is kept even when a batch is topped up', () async {
      final id = await buy('Soap', cost: rs(50), price: rs(70), qty: 10);
      await buy('Soap', productId: id, cost: rs(50), price: rs(70), qty: 10);
      expect((await purchases()).length, 2);
    });

    test('zero quantity is rejected', () async {
      expect(() => savePurchase([BuyLine(name: 'X', cost: 1, price: 2, qty: 0)]),
          throwsA(isA<Exception>()));
      expect((await products()).length, 0);
    });
  });

  group('sales', () {
    late String pid, cid, batchA;

    setUp(() async {
      pid = await buy('Coca-Cola 1L', cost: rs(150), price: rs(180), qty: 20);
      await buy('Coca-Cola 1L', productId: pid, cost: rs(160), price: rs(190), qty: 15);
      final bs = await batches(pid);
      batchA = bs[0].id;
      cid = await saveCustomer(name: 'ABC Shop', phone: '0712345678');
    });

    SellLine line(String batchId, int price, int qty) =>
        SellLine(productId: pid, batchId: batchId, name: 'Coca-Cola 1L', price: price, qty: qty);

    test('sale deducts the chosen batch only and records the ledger', () async {
      await saveDoc(
          customerId: cid,
          quote: false,
          lines: [line(batchA, rs(180), 10)],
          paid: rs(1000));

      final bs = await batches(pid);
      expect(bs[0].qtyLeft, 10, reason: 'batch A sold from');
      expect(bs[1].qtyLeft, 15, reason: 'batch B untouched');
      expect(await balance(cid), rs(800));
    });

    test('stock can never go negative', () async {
      expect(
          () => saveDoc(customerId: cid, quote: false, lines: [line(batchA, rs(180), 21)]),
          throwsA(isA<Exception>()));
      expect((await batches(pid))[0].qtyLeft, 20, reason: 'rolled back');
      expect(await balance(cid), 0, reason: 'no ledger entry either');
    });

    test('unpaid, part paid and fully paid sales', () async {
      await saveDoc(customerId: cid, quote: false, lines: [line(batchA, rs(180), 1)]);
      expect(await balance(cid), rs(180));

      await saveDoc(
          customerId: cid, quote: false, lines: [line(batchA, rs(180), 1)], paid: rs(100));
      expect(await balance(cid), rs(260));

      await saveDoc(
          customerId: cid, quote: false, lines: [line(batchA, rs(180), 1)], paid: rs(180));
      expect(await balance(cid), rs(260));
    });

    test('payments reduce debt and advances go negative', () async {
      await saveDoc(
          customerId: cid,
          quote: false,
          lines: [line(batchA, rs(180), 10)],
          paid: rs(1000));
      await recordPayment(cid, rs(500));
      expect(await balance(cid), rs(300));

      await recordPayment(cid, rs(800));
      expect(await balance(cid), -rs(500), reason: 'overpaid becomes an advance');
      expect(balanceLabelIsAdvance(await balance(cid)), isTrue);
    });

    test('cancelling a sale restores stock and reverses the charge', () async {
      final id = await saveDoc(
          customerId: cid,
          quote: false,
          lines: [line(batchA, rs(180), 10)],
          paid: rs(1000));
      await cancelDoc(id);

      expect((await batches(pid))[0].qtyLeft, 20);
      expect(await balance(cid), -rs(1000),
          reason: 'money actually received stays as customer credit');
      expect(() => cancelDoc(id), throwsA(isA<Exception>()));
    });

    test('historical prices survive later batch changes', () async {
      final id = await saveDoc(
          customerId: cid, quote: false, lines: [line(batchA, rs(180), 2)]);
      // Buying more at a new price must not rewrite what was already sold.
      await buy('Coca-Cola 1L', productId: pid, cost: rs(170), price: rs(210), qty: 5);
      expect((await docItems(id)).first.price, rs(180));
    });
  });

  group('quotations', () {
    late String pid, cid, batchA;

    setUp(() async {
      pid = await buy('Coca-Cola 1L', cost: rs(150), price: rs(180), qty: 20);
      batchA = (await batches(pid)).first.id;
      cid = await saveCustomer(name: 'ABC Shop');
    });

    Future<String> quote(int qty) => saveDoc(
          customerId: cid,
          quote: true,
          lines: [
            SellLine(
                productId: pid,
                batchId: batchA,
                name: 'Coca-Cola 1L',
                price: rs(180),
                qty: qty)
          ],
        );

    test('creating a quotation changes nothing', () async {
      await quote(5);
      expect((await product(pid))!.stock, 20);
      expect(await balance(cid), 0);
    });

    test('converting deducts stock exactly once', () async {
      final q = await quote(5);
      final saleId = await convertQuote(q, paid: rs(400));

      expect((await product(pid))!.stock, 15);
      expect(await balance(cid), rs(500));
      expect((await doc(q))!.status, 'completed');
      expect((await doc(saleId))!.fromQuote, q);
    });

    test('a quotation cannot be converted twice', () async {
      final q = await quote(5);
      await convertQuote(q);
      expect(() => convertQuote(q), throwsA(isA<Exception>()));
      expect((await product(pid))!.stock, 15, reason: 'no double deduction');
    });

    test('conversion fails cleanly when stock ran out meanwhile', () async {
      final q = await quote(20);
      // Sell the shelf empty before the quote is accepted.
      await saveDoc(customerId: cid, quote: false, lines: [
        SellLine(
            productId: pid, batchId: batchA, name: 'Coca-Cola 1L', price: rs(180), qty: 20)
      ]);
      expect(() => convertQuote(q), throwsA(isA<Exception>()));
      expect((await doc(q))!.status, 'pending', reason: 'quote left untouched');
    });

    test('cancelling a quotation blocks conversion', () async {
      final q = await quote(5);
      await cancelDoc(q);
      expect(() => convertQuote(q), throwsA(isA<Exception>()));
      expect((await product(pid))!.stock, 20);
    });
  });

  group('returns', () {
    late String pid, cid, saleId, batchA;

    setUp(() async {
      pid = await buy('Coca-Cola 1L', cost: rs(150), price: rs(180), qty: 20);
      batchA = (await batches(pid)).first.id;
      cid = await saveCustomer(name: 'ABC Shop');
      saleId = await saveDoc(
        customerId: cid,
        quote: false,
        paid: rs(1000),
        lines: [
          SellLine(
              productId: pid,
              batchId: batchA,
              name: 'Coca-Cola 1L',
              price: rs(180),
              qty: 10)
        ],
      );
    });

    test('returned items go back to their own batch and credit the customer', () async {
      final item = (await docItems(saleId)).first;
      await saveReturn(saleId, {item.id: 3});

      expect((await batches(pid)).first.qtyLeft, 13);
      expect(await balance(cid), rs(800) - rs(540));
      expect((await docItems(saleId)).first.returned, 3);
      expect((await returns()).length, 1);
    });

    test('cannot return more than was sold, even across two returns', () async {
      final item = (await docItems(saleId)).first;
      await saveReturn(saleId, {item.id: 6});
      expect(() => saveReturn(saleId, {item.id: 5}), throwsA(isA<Exception>()));

      expect((await batches(pid)).first.qtyLeft, 16, reason: 'second return rolled back');
      await saveReturn(saleId, {item.id: 4});
      expect((await batches(pid)).first.qtyLeft, 20);
    });

    test('an empty return is refused', () async {
      final item = (await docItems(saleId)).first;
      expect(() => saveReturn(saleId, {item.id: 0}), throwsA(isA<Exception>()));
    });

    test('cancelling a partly returned sale only restores what is left', () async {
      final item = (await docItems(saleId)).first;
      await saveReturn(saleId, {item.id: 4});
      await cancelDoc(saleId);
      expect((await batches(pid)).first.qtyLeft, 20, reason: 'not 24');
    });
  });

  group('backup', () {
    test('round trip keeps products, photos, batches, ledger and settings', () async {
      final photo = Uint8List.fromList(List.generate(64, (i) => i));
      final pid = await saveProduct(name: 'Coca-Cola 1L', image: photo);
      await savePurchase(
          [BuyLine(productId: pid, cost: rs(150), price: rs(180), qty: 20)]);
      final cid = await saveCustomer(name: 'ABC Shop', phone: '0712345678');
      final batchA = (await batches(pid)).first.id;
      await saveDoc(customerId: cid, quote: false, paid: rs(500), lines: [
        SellLine(
            productId: pid, batchId: batchA, name: 'Coca-Cola 1L', price: rs(180), qty: 5)
      ]);
      await setSetting('business_name', 'Karots Traders');

      final backup = await exportBackup();
      await db.delete('doc_items');
      await db.delete('docs');
      await db.delete('ledger');
      await db.delete('batches');
      await db.delete('products');
      expect((await products()).length, 0);

      await importBackup(backup);
      final p = (await products()).single;
      expect(p.name, 'Coca-Cola 1L');
      expect(p.image, photo, reason: 'photos must survive a backup');
      expect(p.stock, 15);
      expect(await balance(cid), rs(400));
      expect((await allSettingsMap())['business_name'], 'Karots Traders');
    });

    test('a junk file is rejected without touching the data', () async {
      await saveProduct(name: 'Soap');
      expect(() => importBackup(Uint8List.fromList('not a backup'.codeUnits)),
          throwsA(isA<Exception>()));
      expect((await products()).length, 1);
    });
  });

  group('a sale settles from the customer account', () {
    late String pid, cid, batchA;

    setUp(() async {
      pid = await buy('Coca-Cola 1L', cost: rs(150), price: rs(180), qty: 20);
      batchA = (await batches(pid)).first.id;
      cid = await saveCustomer(name: 'ABC Shop');
    });

    Future<String> sell(int qty, {int paid = 0, bool quote = false}) => saveDoc(
          customerId: cid,
          quote: quote,
          paid: paid,
          lines: [
            SellLine(
                productId: pid,
                batchId: batchA,
                name: 'Coca-Cola 1L',
                price: rs(180),
                qty: qty)
          ],
        );

    test('paying the rest later clears the sale', () async {
      // The reported bug: part paid at the counter, settled up days later,
      // and the sale still read "Part paid" forever.
      final id = await sell(10, paid: rs(1000)); // Rs. 1,800 bill
      expect((await doc(id))!.due, rs(800));

      await recordPayment(cid, rs(800));
      final d = (await doc(id))!;
      expect(d.settled, rs(1800));
      expect(d.due, 0, reason: 'the bill is clear');
      expect(d.paid, rs(1000), reason: 'the till record does not change');
      expect(d.settledLater, isTrue);
      expect(await balance(cid), 0);
    });

    test('paying part of what is left still reads as part paid', () async {
      final id = await sell(10, paid: rs(1000));
      await recordPayment(cid, rs(300));
      final d = (await doc(id))!;
      expect(d.settled, rs(1300));
      expect(d.due, rs(500));
    });

    test('money clears the oldest bill first', () async {
      final first = await sell(5); // Rs. 900
      final second = await sell(2); // Rs. 360
      await recordPayment(cid, rs(1000));

      expect((await doc(first))!.due, 0, reason: 'oldest cleared');
      expect((await doc(second))!.settled, rs(100));
      expect((await doc(second))!.due, rs(260));
      expect(await balance(cid), rs(260));
    });

    test('an advance bigger than the sale marks it fully paid', () async {
      await recordPayment(cid, rs(2000));
      final d = (await doc(await sell(10)))!;

      expect(d.paid, 0, reason: 'no cash at the counter');
      expect(d.settled, rs(1800));
      expect(d.due, 0, reason: 'must not read as unpaid');
      expect(await balance(cid), -rs(200), reason: 'Rs. 200 advance left');
    });

    test('a smaller advance leaves the rest owing', () async {
      await recordPayment(cid, rs(500));
      final d = (await doc(await sell(10)))!;

      expect(d.settled, rs(500));
      expect(d.due, rs(1300));
      expect(await balance(cid), rs(1300));
    });

    test('cash and advance together', () async {
      await recordPayment(cid, rs(2000));
      final d = (await doc(await sell(10, paid: rs(500))))!;

      expect(d.paid, rs(500));
      expect(d.settled, rs(1800));
      expect(d.due, 0);
      expect(await balance(cid), -rs(700));
    });

    test('a quotation is never settled', () async {
      await recordPayment(cid, rs(2000));
      final d = (await doc(await sell(10, quote: true)))!;
      expect(d.settled, 0);
      expect(await balance(cid), -rs(2000));
    });

    test('converting a quote applies the advance the customer has by then',
        () async {
      final q = await sell(10, quote: true);
      await recordPayment(cid, rs(2000));
      final d = (await doc(await convertQuote(q)))!;

      expect(d.settled, rs(1800));
      expect(d.due, 0);
      expect(await balance(cid), -rs(200));
    });

    test('a return credits the account and can clear a later bill', () async {
      final paidSale = await sell(10, paid: rs(1800));
      final item = (await docItems(paidSale)).first;
      await saveReturn(paidSale, {item.id: 5}); // Rs. 900 back

      final next = await sell(4); // Rs. 720
      expect((await doc(next))!.due, 0, reason: 'covered by the return credit');
      expect(await balance(cid), -rs(180));
    });

    test('a cancelled sale never counts as settled', () async {
      await recordPayment(cid, rs(2000));
      final id = await sell(10);
      await cancelDoc(id);
      expect((await doc(id))!.settled, 0);
      expect(await balance(cid), -rs(2000), reason: 'advance untouched');
    });

    test('cancelling gives the advance back', () async {
      await recordPayment(cid, rs(2000));
      await cancelDoc(await sell(10));
      expect(await balance(cid), -rs(2000));
      expect((await batches(pid)).first.qtyLeft, 20);
    });

    test('payments are numbered so a receipt can be reprinted', () async {
      final a = await recordPayment(cid, rs(100));
      final b = await recordPayment(cid, rs(200));
      expect((await ledgerEntry(a))!.no, 1);
      expect((await ledgerEntry(b))!.no, 2);
      expect((await ledgerEntry(b))!.balanceAfter, -rs(300),
          reason: 'balance printed on the receipt');
    });
  });

  group('correcting a batch', () {
    late String pid, batchA;

    setUp(() async {
      pid = await buy('Coca-Cola 1L', cost: rs(150), price: rs(180), qty: 20);
      batchA = (await batches(pid)).first.id;
    });

    test('a miscount is written down, not silently applied', () async {
      await fixBatch(batchA, qty: 17, cost: rs(150), price: rs(180),
          reason: 'Three broken');

      expect((await product(pid))!.stock, 17);
      final f = (await adjustments(productId: pid)).single;
      expect(f['qty_before'], 20);
      expect(f['qty_after'], 17);
      expect(f['reason'], 'Three broken');
    });

    test('correcting the price leaves past sales alone', () async {
      final cid = await saveCustomer(name: 'ABC Shop');
      final sale = await saveDoc(customerId: cid, quote: false, lines: [
        SellLine(
            productId: pid, batchId: batchA, name: 'Coca-Cola 1L', price: rs(180), qty: 2)
      ]);
      await fixBatch(batchA, qty: 18, cost: rs(150), price: rs(200));

      expect((await docItems(sale)).first.price, rs(180), reason: 'history is history');
      expect((await batches(pid)).first.price, rs(200));
      expect(await balance(cid), rs(360));
    });

    test('a correction upward keeps received at least the shelf count', () async {
      await fixBatch(batchA, qty: 25, cost: rs(150), price: rs(180));
      final b = (await batches(pid)).first;
      expect(b.qtyLeft, 25);
      expect(b.qtyIn, 25);
    });

    test('negative stock and no-op corrections are refused', () async {
      expect(() => fixBatch(batchA, qty: -1, cost: rs(150), price: rs(180)),
          throwsA(isA<Exception>()));
      expect(() => fixBatch(batchA, qty: 20, cost: rs(150), price: rs(180)),
          throwsA(isA<Exception>()));
      expect((await adjustments()).length, 0);
    });

    test('corrections survive a backup round trip', () async {
      await fixBatch(batchA, qty: 17, cost: rs(150), price: rs(180), reason: 'Broken');
      final backup = await exportBackup();
      await importBackup(backup);
      expect((await adjustments()).length, 1);
      expect((await product(pid))!.stock, 17);
    });
  });

  test('the full acceptance scenario', () async {
    // Buy the same product at two prices.
    final pid = await buy('Coca-Cola 1L', cost: rs(150), price: rs(180), qty: 20);
    await buy('Coca-Cola 1L', productId: pid, cost: rs(160), price: rs(190), qty: 15);
    expect((await product(pid))!.stock, 35);

    final cid = await saveCustomer(name: 'ABC Shop', phone: '0712345678');
    final batchA = (await batches(pid)).first.id;
    SellLine l(int qty) => SellLine(
        productId: pid, batchId: batchA, name: 'Coca-Cola 1L', price: rs(180), qty: qty);

    // Quote first, no stock movement.
    final q = await saveDoc(customerId: cid, quote: true, lines: [l(10)]);
    expect((await product(pid))!.stock, 35);

    // Convert with a partial payment.
    await convertQuote(q, paid: rs(1000));
    expect((await batches(pid)).first.qtyLeft, 10);
    expect(await balance(cid), rs(800));

    // Later payment.
    await recordPayment(cid, rs(500));
    expect(await balance(cid), rs(300));

    // Two of them come back.
    final sale = (await docs(customerId: cid, kind: 'sale')).first;
    final item = (await docItems(sale.id)).first;
    await saveReturn(sale.id, {item.id: 2});
    expect((await batches(pid)).first.qtyLeft, 12);
    expect(await balance(cid), rs(300) - rs(360));

    expect((await ledger(cid)).length, 4, reason: 'sale, payment, payment, return');
  });

  group('undoing a payment', () {
    late String cid, pid, bid;

    setUp(() async {
      pid = await buy('Soap', cost: rs(50), price: rs(70), qty: 20);
      bid = (await batches(pid)).first.id;
      cid = await saveCustomer(name: 'ABC Shop');
    });

    Future<String> sell({int qty = 10, int paid = 0}) => saveDoc(
        customerId: cid,
        quote: false,
        paid: paid,
        lines: [
          SellLine(productId: pid, batchId: bid, name: 'Soap', price: rs(70), qty: qty)
        ]);

    test('a wrong amount goes back, and the bill it cleared re-opens', () async {
      final sale = await sell(); // Rs. 700 owing
      final fat = await recordPayment(cid, rs(700));

      expect(await balance(cid), 0);
      expect((await doc(sale))!.due, 0, reason: 'the bill reads as paid');

      await undoPayment(fat);

      expect(await balance(cid), rs(700), reason: 'they owe it again');
      expect((await doc(sale))!.due, rs(700),
          reason: 'settlement is derived, so the bill re-opens by itself');
      expect((await doc(sale))!.settled, 0);
    });

    test('nothing is deleted — both the mistake and the fix stay visible',
        () async {
      await sell();
      final wrong = await recordPayment(cid, rs(5000));
      await undoPayment(wrong);

      final rows = await ledger(cid);
      expect(rows, hasLength(3), reason: 'sale, payment, reversal');
      expect(rows.map((e) => e.type),
          containsAll(['sale', 'payment', 'payment_cancelled']));

      final original = rows.firstWhere((e) => e.id == wrong);
      expect(original.amount, -rs(5000), reason: 'the original row is untouched');

      final fix = rows.firstWhere((e) => e.type == 'payment_cancelled');
      expect(fix.refId, wrong, reason: 'points at what it undid');
      expect(fix.amount, rs(5000));
    });

    test('the same payment cannot be undone twice', () async {
      await sell();
      final p = await recordPayment(cid, rs(300));
      await undoPayment(p);
      final after = await balance(cid);

      expect(() => undoPayment(p), throwsA(isA<Exception>()));
      expect(await balance(cid), after, reason: 'no double reversal');
    });

    test('cash taken with the sale is refused, and says what to do instead',
        () async {
      await sell(paid: rs(200));
      final atCounter =
          (await ledger(cid)).firstWhere((e) => e.type == 'payment');

      expect(() => undoPayment(atCounter.id),
          throwsA(predicate((e) => '$e'.contains('cancel the sale'))));
      expect(await balance(cid), rs(500), reason: 'untouched');
    });

    test('a reversal is not itself a payment that can be undone', () async {
      await sell();
      final p = await recordPayment(cid, rs(300));
      final fix = await undoPayment(p);
      expect(() => undoPayment(fix), throwsA(isA<Exception>()));
    });

    test('a cheque credited by mistake comes back off', () async {
      await sell();
      final ch = await saveCheque(
          customerId: cid, chequeNo: '400123', amount: rs(400), dueAt: 0);
      final paymentId = (await oneCheque(ch))!.ledgerId!;

      expect(await balance(cid), rs(300));

      await undoPayment(paymentId);

      expect((await oneCheque(ch))!.isBounced, isTrue);
      expect(await balance(cid), rs(700), reason: 'the money is owed again');
      expect((await stats()).cheques, 0, reason: 'nothing riding on the bank');
    });

    test('undoing one payment leaves the others settling as before', () async {
      final sale = await sell(); // Rs. 700
      await recordPayment(cid, rs(300));
      final wrong = await recordPayment(cid, rs(400));

      expect((await doc(sale))!.due, 0);

      await undoPayment(wrong);

      expect((await doc(sale))!.settled, rs(300), reason: 'the good payment stands');
      expect((await doc(sale))!.due, rs(400));
    });
  });

  group('adjustments and money owed from before', () {
    late String pid, bid, cid;

    setUp(() async {
      pid = await buy('Soap', cost: rs(50), price: rs(70), qty: 20);
      bid = (await batches(pid)).first.id;
      cid = await saveCustomer(name: 'ABC Shop');
    });

    Future<String> sell({int qty = 10}) => saveDoc(customerId: cid, quote: false, lines: [
          SellLine(productId: pid, batchId: bid, name: 'Soap', price: rs(70), qty: qty)
        ]);

    test('an opening balance is what they owed before any of this', () async {
      await adjustBalance(cid, rs(2000), opening: true);

      expect(await balance(cid), rs(2000));
      final e = (await ledger(cid)).single;
      expect(e.type, 'opening');
      expect(e.amount, rs(2000));
    });

    test('an opening balance cannot be entered twice', () async {
      await adjustBalance(cid, rs(2000), opening: true);

      expect(() => adjustBalance(cid, rs(2000), opening: true),
          throwsA(isA<Exception>()));
      expect(await balance(cid), rs(2000), reason: 'not doubled');
    });

    test('money paid clears the old debt before it touches a new sale',
        () async {
      await adjustBalance(cid, rs(2000), opening: true);
      final sale = await sell(); // Rs. 700

      await recordPayment(cid, rs(2000));

      expect(await balance(cid), rs(700));
      expect((await doc(sale))!.due, rs(700),
          reason: 'the payment went to what was owed first, not to this bill');

      await recordPayment(cid, rs(700));
      expect((await doc(sale))!.due, 0);
      expect(await balance(cid), 0);
    });

    test('an adjustment can put more on or let them off', () async {
      final sale = await sell(); // Rs. 700

      await adjustBalance(cid, rs(100), note: 'Delivery charge');
      expect(await balance(cid), rs(800));

      await adjustBalance(cid, -rs(300), note: 'Goodwill');
      expect(await balance(cid), rs(500));
      expect((await doc(sale))!.settled, rs(300),
          reason: 'letting them off counts against the bill like a payment');
    });

    test('an adjustment of nothing is refused', () async {
      expect(() => adjustBalance(cid, 0), throwsA(isA<Exception>()));
      expect(await ledger(cid), isEmpty);
    });

    test('a customer carrying an old debt cannot be deleted away', () async {
      await adjustBalance(cid, rs(2000), opening: true);
      expect(() => deleteCustomer(cid), throwsA(isA<Exception>()));
      expect(await balance(cid), rs(2000));
    });
  });

  group('what a customer still has to pay', () {
    late String pid, bid, cid;

    setUp(() async {
      pid = await buy('Soap', cost: rs(50), price: rs(70), qty: 100);
      bid = (await batches(pid)).first.id;
      cid = await saveCustomer(name: 'ABC Shop');
    });

    Future<String> sell({int qty = 10}) => saveDoc(customerId: cid, quote: false, lines: [
          SellLine(productId: pid, batchId: bid, name: 'Soap', price: rs(70), qty: qty)
        ]);

    /// Moves a sale and its ledger entry back in time, which is the only way
    /// to get a bill old enough to be overdue.
    Future<void> backdate(String docId, int days) async {
      final at = DateTime.now()
          .subtract(Duration(days: days))
          .millisecondsSinceEpoch;
      await db.update('docs', {'created_at': at},
          where: 'id = ?', whereArgs: [docId]);
      await db.update('ledger', {'created_at': at},
          where: 'ref_id = ?', whereArgs: [docId]);
    }

    test('settled bills drop off, unfinished ones stay, oldest first',
        () async {
      final one = await sell(); // Rs. 700
      final two = await sell();
      final three = await sell();

      await recordPayment(cid, rs(700)); // clears the first exactly

      final open = await outstanding(cid);
      expect(open.bills.map((d) => d.id), [two, three],
          reason: 'the paid-off bill is not what they want to see');
      expect(open.total, rs(1400));
      expect(one, isNotNull);
    });

    test('a part-paid bill stays, showing only what is left of it', () async {
      final one = await sell();
      await sell();
      await recordPayment(cid, rs(300));

      final open = await outstanding(cid);
      expect(open.bills.first.id, one);
      expect(open.bills.first.due, rs(400), reason: 'Rs. 700 less Rs. 300');
      expect(open.bills.fold(0, (a, d) => a + d.due), rs(1100));
      expect(open.total, rs(1100));
    });

    test('nothing is outstanding once the account is clear', () async {
      await sell();
      await recordPayment(cid, rs(700));

      final open = await outstanding(cid);
      expect(open.bills, isEmpty);
      expect(open.total, 0);
      expect(open.overdue, 0);
    });

    test('an advance leaves nothing outstanding and no negative bills',
        () async {
      await sell();
      await recordPayment(cid, rs(1000));

      final open = await outstanding(cid);
      expect(open.bills, isEmpty);
      expect(open.total, -rs(300), reason: 'they are ahead by Rs. 300');
    });

    test('a bill past its credit days counts as overdue', () async {
      final old = await sell();
      await sell();
      await backdate(old, creditDays + 3);

      final open = await outstanding(cid);
      expect(open.overdue, rs(700), reason: 'only the old one');
      expect(open.total, rs(1400));
    });

    test('a cheque not yet at the bank is already off the total', () async {
      await sell();
      await saveCheque(
          customerId: cid,
          chequeNo: '400123',
          amount: rs(200),
          dueAt: DateTime.now().add(const Duration(days: 10)).millisecondsSinceEpoch);

      final open = await outstanding(cid);
      expect(open.total, rs(500), reason: 'the cheque came off when it arrived');
      expect(open.bills.single.due, rs(500));
      expect((await cheques(customerId: cid, status: 'pending')).single.daysLeft,
          greaterThan(0), reason: 'and the report can say how long it has left');
    });

    test('debt carried in is the part no bill accounts for', () async {
      await adjustBalance(cid, rs(2000), opening: true);
      await sell(); // Rs. 700
      await recordPayment(cid, rs(500));

      final open = await outstanding(cid);
      // Rs. 500 went against the old debt, so the bill is untouched and the
      // remainder — what the report calls brought forward — is Rs. 1,500.
      expect(open.bills.single.due, rs(700));
      expect(open.total, rs(2200));
      expect(open.total - open.bills.fold(0, (a, d) => a + d.due), rs(1500));
    });
  });

  group('the outstanding report adds up', () {
    late String pid, bid, cid;

    setUp(() async {
      pid = await buy('Soap', cost: rs(50), price: rs(70), qty: 200);
      bid = (await batches(pid)).first.id;
      cid = await saveCustomer(name: 'ABC Shop', phone: '0712345678');
    });

    Future<String> sell({int qty = 10}) => saveDoc(customerId: cid, quote: false, lines: [
          SellLine(productId: pid, batchId: bid, name: 'Soap', price: rs(70), qty: qty)
        ]);

    /// The report as the customer would receive it.
    Future<Receipt> report() async => outstandingReceipt(
          (await customer(cid))!,
          await outstanding(cid),
          await ledger(cid),
          await docs(customerId: cid),
          await cheques(customerId: cid, status: 'pending'),
        );

    /// Brought forward, plus every line on the report, must land exactly on
    /// the balance the rest of the app shows. That is the whole point.
    void expectAddsUp(Receipt r, int balance) {
      final sum = r.statement.fold(0, (a, row) => a + row.$3);
      expect(sum, balance, reason: 'the lines add up to the balance');
      if (r.statement.isNotEmpty) {
        expect(r.statement.last.$4, balance,
            reason: 'and the last running balance is that same figure');
      }
    }

    test('a bill already paid off is left out entirely', () async {
      await sell(); // Rs. 700, paid off below
      await recordPayment(cid, rs(700));
      await sell(qty: 4); // Rs. 280, still owed

      final r = await report();
      final details = r.statement.map((row) => row.$2).toList();

      expect(details.where((d) => d.startsWith('Sale #1')), isEmpty,
          reason: 'the bill they already paid is not listed');
      expect(details.any((d) => d.startsWith('Sale #2  ·  due ')), isTrue,
          reason: 'the open bill, with the date it was due by');
      expect(details, isNot(contains('Balance brought forward')),
          reason: 'nothing was carried in, so no line saying zero');
      expectAddsUp(r, rs(280));
    });

    test('payments landing between open bills are on the report', () async {
      await sell(); // Rs. 700
      await recordPayment(cid, rs(200), note: 'Part payment');
      await sell(qty: 4); // Rs. 280

      final r = await report();
      final details = r.statement.map((row) => row.$2).toList();

      expect(details, contains('Part payment'), reason: 'the money in between');
      expect(details.where((d) => d.startsWith('Sale #')), hasLength(2));
      expectAddsUp(r, rs(780));
    });

    test('a cheque still waiting is listed, subtracted, and explained',
        () async {
      await sell(); // Rs. 700
      await saveCheque(
          customerId: cid,
          chequeNo: '400123',
          bank: 'Sampath',
          amount: rs(200),
          dueAt: DateTime.now().add(const Duration(days: 5)).millisecondsSinceEpoch);

      final r = await report();
      final cheque =
          r.statement.firstWhere((row) => row.$2.contains('400123'));

      expect(cheque.$3, -rs(200), reason: 'shown as a subtraction');
      expect(r.notes.first, contains('already been taken off this total'));
      expect(r.notes.first, contains('5 days from now'));
      expect(r.totals.first, ('Total to pay', rs(500)));
      expectAddsUp(r, rs(500));
    });

    test('a balance carried in from before the app opens the report',
        () async {
      await adjustBalance(cid, rs(2000), opening: true);
      await sell(); // Rs. 700
      await recordPayment(cid, rs(500));

      final r = await report();
      expect(r.statement.first.$2, 'Balance brought forward');
      expect(r.statement.first.$3, rs(2000), reason: 'the old debt itself');
      // The Rs. 500 landed after the bill, so it keeps its own line rather
      // than being netted away — the customer can see the money they sent.
      expect(r.statement.map((row) => row.$2), contains('Payment received'));
      expectAddsUp(r, rs(2200));
    });

    test('a settled account says so and lists nothing', () async {
      await sell();
      await recordPayment(cid, rs(700));

      final r = await report();
      expect(r.statement, isEmpty);
      expect(r.totals.first, ('Nothing outstanding', 0));
      expect(r.notes, contains('This account is fully settled. Thank you.'));
    });

    test('an overdue bill is marked and totalled', () async {
      final old = await sell();
      final at = DateTime.now()
          .subtract(Duration(days: creditDays + 3))
          .millisecondsSinceEpoch;
      await db.update('docs', {'created_at': at}, where: 'id = ?', whereArgs: [old]);
      await db.update('ledger', {'created_at': at},
          where: 'ref_id = ?', whereArgs: [old]);

      final r = await report();
      expect(r.statement.any((row) => row.$2.contains('(overdue)')), isTrue);
      expect(r.totals, contains(('Of that, overdue', rs(700))));
    });

    test('a cancelled sale and the line cancelling it are both left off',
        () async {
      final wrong = await sell(); // Rs. 700, written by mistake
      await cancelDoc(wrong);
      await sell(qty: 4); // Rs. 280, the real one

      final r = await report();
      final details = r.statement.map((row) => row.$2).toList();

      expect(details.where((d) => d.contains('#1')), isEmpty,
          reason: 'the customer sees neither half of a correction');
      expect(details.any((d) => d.startsWith('Sale #2')), isTrue);
      expectAddsUp(r, rs(280));
    });

    test('an undone payment and the line undoing it are both left off',
        () async {
      await sell(); // Rs. 700
      final oops = await recordPayment(cid, rs(500), note: 'Typed twice');
      await undoPayment(oops);

      final r = await report();
      final details = r.statement.map((row) => row.$2).toList();

      expect(details, isNot(contains('Typed twice')));
      expect(details.any((d) => d.toLowerCase().contains('undone')), isFalse);
      expectAddsUp(r, rs(700));
    });

    test('a payment receipt carries the run-up to it', () async {
      await sell(); // Rs. 700
      await sell(qty: 4); // Rs. 280
      final paid =
          await recordPayment(cid, rs(500), method: 'bank', note: 'Part payment');

      final r = paymentReceipt((await customer(cid))!, paid, await ledger(cid),
          await docs(customerId: cid))!;
      final details = r.statement.map((row) => row.$2).toList();

      expect(details.where((d) => d.startsWith('Sale #')), hasLength(2),
          reason: 'the bills this money is going against');
      expect(r.reference, 'Received by Bank transfer');
      expect(r.totals, contains(('Payment received', rs(500))));
      expect(r.totals.last, ('Still owing', rs(480)));
      expect(r.statement.last.$4, rs(480),
          reason: 'the running column ends on what is left');
    });

    test('there is no receipt for a payment that was undone', () async {
      await sell();
      final oops = await recordPayment(cid, rs(500));
      await undoPayment(oops);

      expect(
          paymentReceipt((await customer(cid))!, oops, await ledger(cid),
              await docs(customerId: cid)),
          isNull);
    });
  });

  group('how the money came in, and when', () {
    late String cid;
    setUp(() async => cid = await saveCustomer(name: 'ABC Shop'));

    test('cash by hand and by bank are told apart on the account', () async {
      await recordPayment(cid, rs(100), method: 'bank');
      await recordPayment(cid, rs(50), method: 'cash');

      final entries = await ledger(cid);
      expect(entries.map((e) => e.method), ['cash', 'bank']);
      expect(entryDetail(entries.last, const {}),
          'Payment received  ·  Bank transfer');
    });

    test('a cheque says cheque without repeating itself', () async {
      await saveCheque(
          customerId: cid, chequeNo: '400123', amount: rs(100), dueAt: 0);

      final e = (await ledger(cid)).single;
      expect(e.method, 'cheque');
      expect(entryDetail(e, const {}), 'Cheque 400123',
          reason: 'the note already says what it was');
    });

    test('a payment entered late is dated when the money actually came',
        () async {
      final threeDaysAgo =
          DateTime.now().subtract(const Duration(days: 3)).millisecondsSinceEpoch;
      await recordPayment(cid, rs(100), at: threeDaysAgo);

      expect((await ledger(cid)).single.createdAt, threeDaysAgo);
    });

    test('a backdated payment settles the bill that was open back then',
        () async {
      final pid = await buy('Soap', cost: rs(50), price: rs(70), qty: 100);
      final bid = (await batches(pid)).first.id;
      SellLine soap(int qty) => SellLine(
          productId: pid, batchId: bid, name: 'Soap', price: rs(70), qty: qty);

      // An old bill, then money that was taken the day after it and only
      // written up now.
      final old = await saveDoc(customerId: cid, quote: false, lines: [soap(10)]);
      final at = DateTime.now().subtract(const Duration(days: 30));
      await db.update('docs', {'created_at': at.millisecondsSinceEpoch},
          where: 'id = ?', whereArgs: [old]);
      await db.update('ledger', {'created_at': at.millisecondsSinceEpoch},
          where: 'ref_id = ?', whereArgs: [old]);
      await saveDoc(customerId: cid, quote: false, lines: [soap(4)]);

      await recordPayment(cid, rs(700),
          at: at.add(const Duration(days: 1)).millisecondsSinceEpoch);

      final bills = await docs(customerId: cid, kind: 'sale');
      expect(bills.firstWhere((d) => d.id == old).due, 0,
          reason: 'the money went where it was owed at the time');
      expect(await balance(cid), rs(280));
    });
  });

  group('giving cash back', () {
    late String pid, bid, cid;

    setUp(() async {
      pid = await buy('Soap', cost: rs(50), price: rs(70), qty: 100);
      bid = (await batches(pid)).first.id;
      cid = await saveCustomer(name: 'ABC Shop');
    });

    SellLine soap(int qty) => SellLine(
        productId: pid, batchId: bid, name: 'Soap', price: rs(70), qty: qty);

    test('an advance handed back leaves nothing on the account', () async {
      await recordPayment(cid, rs(500));
      expect(await balance(cid), -rs(500), reason: 'they are ahead');

      await payOut(cid, rs(500), method: 'cash');
      expect(await balance(cid), 0);
    });

    test('money handed back stops settling bills that come later', () async {
      // The trap: an advance that has already been given back must not still
      // be sitting there quietly paying off the next sale.
      await recordPayment(cid, rs(500));
      await payOut(cid, rs(500));

      await saveDoc(customerId: cid, quote: false, lines: [soap(5)]);

      final bill = (await docs(customerId: cid, kind: 'sale')).single;
      expect(bill.settled, 0, reason: 'there was no money left to settle it');
      expect(bill.due, rs(350));
      expect(await balance(cid), rs(350));
    });

    test('handing back part of it leaves the rest working', () async {
      await recordPayment(cid, rs(500));
      await payOut(cid, rs(200));
      await saveDoc(customerId: cid, quote: false, lines: [soap(10)]);

      final bill = (await docs(customerId: cid, kind: 'sale')).single;
      expect(bill.settled, rs(300), reason: 'what is left of the advance');
      expect(bill.due, rs(400));
      expect(await balance(cid), rs(400));
    });

    test('it is on the account as its own entry, with a receipt', () async {
      await recordPayment(cid, rs(500));
      final id = await payOut(cid, rs(500), method: 'bank', note: 'Cash returned');

      final e = (await ledger(cid)).first;
      expect(e.id, id);
      expect(e.type, 'refund');
      expect(e.amount, rs(500), reason: 'positive, the way a debt is');

      final r = paymentReceipt((await customer(cid))!, id, await ledger(cid),
          await docs(customerId: cid))!;
      expect(r.kind, 'Refund');
      expect(r.totals.first, ('Cash returned', rs(500)));
      expect(r.reference, 'Paid out by Bank transfer');
    });

    test('nothing and less than nothing are refused', () async {
      expect(() => payOut(cid, 0), throwsA(isA<Exception>()));
      expect(() => payOut(cid, -rs(100)), throwsA(isA<Exception>()));
      expect(await ledger(cid), isEmpty);
    });
  });

  group('what the shelf is worth', () {
    test('both figures, counting only what is still there', () async {
      final pid = await buy('Soap', cost: rs(50), price: rs(70), qty: 10);
      await buy('Rice', cost: rs(1000), price: rs(1300), qty: 4);

      var v = await stockValue();
      expect(v.items, 14);
      expect(v.cost, rs(50) * 10 + rs(1000) * 4);
      expect(v.retail, rs(70) * 10 + rs(1300) * 4);

      // Selling takes goods off the shelf, and off the figure with them.
      final cid = await saveCustomer(name: 'ABC');
      await saveDoc(customerId: cid, quote: false, lines: [
        SellLine(
            productId: pid,
            batchId: (await batches(pid)).first.id,
            name: 'Soap',
            price: rs(70),
            qty: 4)
      ]);

      v = await stockValue();
      expect(v.items, 10);
      expect(v.cost, rs(50) * 6 + rs(1000) * 4);
    });

    test('an empty shop is worth nothing, not an error', () async {
      final v = await stockValue();
      expect((v.items, v.cost, v.retail), (0, 0, 0));
    });
  });

  group('who is late', () {
    late String pid, bid;

    setUp(() async {
      pid = await buy('Soap', cost: rs(50), price: rs(70), qty: 500);
      bid = (await batches(pid)).first.id;
    });

    /// A sale written [daysAgo] days ago, backdated in the books the same way
    /// the rest of the app would have seen it happen.
    Future<String> oldSale(String cid, int qty, int daysAgo) async {
      final id = await saveDoc(customerId: cid, quote: false, lines: [
        SellLine(productId: pid, batchId: bid, name: 'Soap', price: rs(70), qty: qty)
      ]);
      final at = DateTime.now()
          .subtract(Duration(days: daysAgo))
          .millisecondsSinceEpoch;
      await db.update('docs', {'created_at': at}, where: 'id = ?', whereArgs: [id]);
      await db.update('ledger', {'created_at': at},
          where: 'ref_id = ?', whereArgs: [id]);
      return id;
    }

    test('only bills past the date count, and the days are the oldest',
        () async {
      final late = await saveCustomer(name: 'Late');
      await oldSale(late, 10, 30); // Rs. 700, long overdue
      await oldSale(late, 4, 20); // Rs. 280, also overdue
      await saveDoc(customerId: late, quote: false, lines: [
        SellLine(productId: pid, batchId: bid, name: 'Soap', price: rs(70), qty: 2)
      ]); // today, not late

      final onTime = await saveCustomer(name: 'On time');
      await saveDoc(customerId: onTime, quote: false, lines: [
        SellLine(productId: pid, batchId: bid, name: 'Soap', price: rs(70), qty: 5)
      ]);

      final rows = await overdue();
      expect(rows, hasLength(1), reason: 'only the one with a bill past its date');
      expect(rows.single.customer.name, 'Late');
      expect(rows.single.overdue, rs(980), reason: 'the two late bills, not today');
      expect(rows.single.days, 30 - creditDays);
    });

    test('paying up takes them off the list', () async {
      final c = await saveCustomer(name: 'Paid up');
      await oldSale(c, 10, 30);
      expect(await overdue(), hasLength(1));

      await recordPayment(c, rs(700));
      expect(await overdue(), isEmpty);
    });

    test('a cancelled bill is never late', () async {
      final c = await saveCustomer(name: 'Cancelled');
      await cancelDoc(await oldSale(c, 10, 30));
      expect(await overdue(), isEmpty);
    });

    test('the worst debt comes first', () async {
      final small = await saveCustomer(name: 'Small');
      await oldSale(small, 2, 40);
      final big = await saveCustomer(name: 'Big');
      await oldSale(big, 20, 10);

      expect((await overdue()).map((x) => x.customer.name), ['Big', 'Small']);
    });
  });

  group('editing a sale instead of cancelling it', () {
    late String pid, bid, cid;

    setUp(() async {
      pid = await buy('Soap', cost: rs(50), price: rs(70), qty: 100);
      bid = (await batches(pid)).first.id;
      cid = await saveCustomer(name: 'ABC Shop');
    });

    SellLine soap(int qty, {int? price}) => SellLine(
        productId: pid, batchId: bid, name: 'Soap', price: price ?? rs(70), qty: qty);

    test('the bill keeps its number and the books follow the new total',
        () async {
      final id = await saveDoc(customerId: cid, quote: false, lines: [soap(10)]);
      expect(await balance(cid), rs(700));

      await editDoc(id, lines: [soap(4)]);

      final d = (await doc(id))!;
      expect(d.no, 1, reason: 'the same bill, put right');
      expect(d.total, rs(280));
      expect(d.editedAt, isNotNull);
      expect(await balance(cid), rs(280), reason: 'the debt is the new total');
      expect((await product(pid))!.stock, 96,
          reason: 'six went back on the shelf');
      expect((await docItems(id)).single.qty, 4);
    });

    test('cash taken at the counter moves with the sale', () async {
      final id = await saveDoc(
          customerId: cid, quote: false, lines: [soap(10)], paid: rs(700));
      expect(await balance(cid), 0);

      await editDoc(id, lines: [soap(10)], paid: rs(300));
      expect(await balance(cid), rs(400));
      expect((await doc(id))!.settled, rs(300));

      // And taking it away entirely leaves the whole bill open.
      await editDoc(id, lines: [soap(10)]);
      expect(await balance(cid), rs(700));
      expect((await ledger(cid)).where((e) => e.isPayment), isEmpty);
    });

    test('a correction that needs more stock than there is is refused',
        () async {
      final id = await saveDoc(customerId: cid, quote: false, lines: [soap(10)]);

      expect(() => editDoc(id, lines: [soap(500)]), throwsA(isA<Exception>()));

      expect((await doc(id))!.total, rs(700), reason: 'the bill is untouched');
      expect((await product(pid))!.stock, 90, reason: 'and so is the shelf');
    });

    test('a sale with goods already returned has to be cancelled instead',
        () async {
      final id = await saveDoc(customerId: cid, quote: false, lines: [soap(10)]);
      await saveReturn(id, {(await docItems(id)).single.id: 2});

      expect(() => editDoc(id, lines: [soap(4)]), throwsA(isA<Exception>()));
      expect((await doc(id))!.total, rs(700));
    });

    test('a cancelled sale cannot be brought back by editing it', () async {
      final id = await saveDoc(customerId: cid, quote: false, lines: [soap(10)]);
      await cancelDoc(id);

      expect(() => editDoc(id, lines: [soap(4)]), throwsA(isA<Exception>()));
      expect(await balance(cid), 0);
      expect((await product(pid))!.stock, 100);
    });

    test('what the bill used to say is kept', () async {
      final id = await saveDoc(
          customerId: cid, quote: false, lines: [soap(10)], paid: rs(200));
      await editDoc(id, lines: [soap(4)]);
      await editDoc(id, lines: [soap(6), soap(1, price: rs(90))]);

      final was = await docEdits(id);
      expect(was, hasLength(2), reason: 'one entry per correction');
      expect(was.first.total, rs(280), reason: 'newest first: the second version');
      expect(was.first.lines.single, ('Soap', 4, rs(70)));
      expect(was.last.total, rs(700), reason: 'and the bill as first written');
      expect(was.last.paid, rs(200), reason: 'including the cash taken then');
    });

    test('a price under cost is refused, the same as when selling', () async {
      final id = await saveDoc(customerId: cid, quote: false, lines: [soap(10)]);

      expect(() => editDoc(id, lines: [soap(10, price: rs(20))]),
          throwsA(isA<Exception>()));
      expect((await doc(id))!.total, rs(700));
      expect((await product(pid))!.stock, 90);
    });
  });

  group('deleting cannot destroy money or stock', () {
    test('a customer holding an advance is not deletable', () async {
      final c = await saveCustomer(name: 'Paid ahead');
      await recordPayment(c, rs(5000));

      expect(() => deleteCustomer(c), throwsA(isA<Exception>()));

      expect((await customers()).length, 1);
      expect(await balance(c), -rs(5000), reason: 'the money is still on the books');
    });

    test('a customer with only a waiting cheque is not deletable', () async {
      final c = await saveCustomer(name: 'Gave a cheque');
      await saveCheque(
          customerId: c, chequeNo: '400123', amount: rs(1000), dueAt: 0);

      expect(() => deleteCustomer(c), throwsA(isA<Exception>()));
      expect(await cheques(), hasLength(1));
    });

    test('a customer who never traded still goes', () async {
      final c = await saveCustomer(name: 'Typed by mistake');
      await deleteCustomer(c);
      expect(await customers(), isEmpty);
    });

    test('a customer who owes money is not deletable', () async {
      final pid = await buy('Soap', cost: rs(50), price: rs(70), qty: 10);
      final c = await saveCustomer(name: 'Still owes');
      await saveDoc(customerId: c, quote: false, lines: [
        SellLine(
            productId: pid,
            batchId: (await batches(pid)).first.id,
            name: 'Soap',
            price: rs(70),
            qty: 5)
      ]);

      expect(() => deleteCustomer(c), throwsA(isA<Exception>()));
      expect(await balance(c), rs(350), reason: 'the debt is still on the books');
    });

    test('a customer who has settled up goes, history and all', () async {
      final pid = await buy('Soap', cost: rs(50), price: rs(70), qty: 10);
      final c = await saveCustomer(name: 'All square');
      final sale = await saveDoc(customerId: c, quote: false, lines: [
        SellLine(
            productId: pid,
            batchId: (await batches(pid)).first.id,
            name: 'Soap',
            price: rs(70),
            qty: 5)
      ], paid: rs(350));
      expect(await balance(c), 0);

      await deleteCustomer(c);

      expect(await customers(), isEmpty);
      expect(await doc(sale), isNull, reason: 'the sale goes with the person');
      expect(await docItems(sale), isEmpty);
      expect((await product(pid))!.stock, 5,
          reason: 'goods that left the shop do not come back onto the shelf');
    });

    test('a product with stock on the shelf is not deletable', () async {
      final pid = await buy('Rice 5kg', cost: rs(1000), price: rs(1300), qty: 40);

      expect(() => deleteProduct(pid), throwsA(isA<Exception>()));

      expect((await product(pid))!.stock, 40, reason: 'the stock is still there');
      expect((await stats()).stock, 40);
      expect((await batches(pid)), hasLength(1));
    });

    test('a product sold out but with history is not deletable', () async {
      final pid = await buy('Soap', cost: rs(50), price: rs(70), qty: 1);
      final cid = await saveCustomer(name: 'ABC');
      final b = (await batches(pid)).first;
      await saveDoc(customerId: cid, quote: false, lines: [
        SellLine(productId: pid, batchId: b.id, name: 'Soap', price: rs(70))
      ]);

      expect((await product(pid))!.stock, 0);
      expect(() => deleteProduct(pid), throwsA(isA<Exception>()));
    });

    test('a product typed by mistake and never bought still goes', () async {
      final pid = await saveProduct(name: 'Wrong name');
      await deleteProduct(pid);
      expect(await products(), isEmpty);
    });
  });

  group('discounts', () {
    late String pid, cid, bid;

    setUp(() async {
      pid = await buy('Coca-Cola 1L', cost: rs(850), price: rs(900), qty: 10);
      bid = (await batches(pid)).first.id;
      cid = await saveCustomer(name: 'Regular');
    });

    SellLine line(int price, {int qty = 1, int listPrice = 0}) => SellLine(
        productId: pid,
        batchId: bid,
        name: 'Coca-Cola 1L',
        price: price,
        listPrice: listPrice,
        qty: qty);

    test('a friend price is charged, and the normal price is remembered',
        () async {
      final id =
          await saveDoc(customerId: cid, quote: false, lines: [line(rs(875), qty: 4)]);

      final d = (await doc(id))!;
      expect(d.total, rs(3500), reason: '4 x 875, not 4 x 900');
      expect(await balance(cid), rs(3500), reason: 'the account is charged what was agreed');

      final i = (await docItems(id)).single;
      expect(i.price, rs(875));
      expect(i.listPrice, rs(900));
      expect(i.discount, rs(100), reason: 'Rs. 25 off each, four of them');
    });

    test('the full price leaves no discount to print', () async {
      final id = await saveDoc(customerId: cid, quote: false, lines: [line(rs(900))]);
      expect((await docItems(id)).single.discount, 0);
    });

    test('the list price falls back to the batch when none is given', () async {
      final id = await saveDoc(customerId: cid, quote: false, lines: [line(rs(880))]);
      expect((await docItems(id)).single.listPrice, rs(900));
    });

    test('selling under cost is refused, and nothing is left behind', () async {
      expect(
          () => saveDoc(customerId: cid, quote: false, lines: [line(rs(849))]),
          throwsA(isA<Exception>()));

      expect(await docs(), isEmpty, reason: 'the whole sale rolled back');
      expect((await batches(pid)).first.qtyLeft, 10, reason: 'stock untouched');
      expect(await balance(cid), 0);
    });

    test('selling exactly at cost is allowed', () async {
      final id = await saveDoc(customerId: cid, quote: false, lines: [line(rs(850))]);
      expect((await doc(id))!.total, rs(850));
    });

    test('a quotation is held to the same floor', () async {
      expect(() => saveDoc(customerId: cid, quote: true, lines: [line(rs(800))]),
          throwsA(isA<Exception>()));
    });

    test('a discounted quote keeps its price when it becomes a sale', () async {
      final q =
          await saveDoc(customerId: cid, quote: true, lines: [line(rs(875), qty: 2)]);
      final sale = await convertQuote(q);

      final i = (await docItems(sale)).single;
      expect(i.price, rs(875));
      expect(i.listPrice, rs(900), reason: 'the discount quoted is the discount billed');
      expect((await doc(sale))!.total, rs(1750));
    });

    test('a cost correction cannot strand an agreed quote at the counter',
        () async {
      final q = await saveDoc(customerId: cid, quote: true, lines: [line(rs(875))]);

      // The cost was typed wrong and gets fixed to above the quoted price.
      await fixBatch(bid, qty: 10, cost: rs(880), price: rs(900), reason: 'Typo');

      final sale = await convertQuote(q);
      expect((await doc(sale))!.total, rs(875), reason: 'the promise is honoured');

      // A brand new sale at that price is still refused.
      expect(() => saveDoc(customerId: cid, quote: false, lines: [line(rs(875))]),
          throwsA(isA<Exception>()));
    });

    test('a discounted line is credited back at the discounted price', () async {
      final id =
          await saveDoc(customerId: cid, quote: false, lines: [line(rs(875), qty: 4)]);
      final item = (await docItems(id)).single;

      await saveReturn(id, {item.id: 2});
      expect(await balance(cid), rs(3500) - rs(1750),
          reason: 'refunded what was charged, not the shelf price');
    });
  });

  group('cheques', () {
    late String cid, pid, bid;

    Future<String> aCheque({int amount = 5000, String no = '400123'}) => saveCheque(
        customerId: cid,
        chequeNo: no,
        amount: amount,
        bank: 'Sampath',
        dueAt: DateTime.now().add(const Duration(days: 7)).millisecondsSinceEpoch);

    setUp(() async {
      pid = await buy('Soap', cost: rs(50), price: rs(70), qty: 20);
      bid = (await batches(pid)).first.id;
      cid = await saveCustomer(name: 'ABC Shop');
      await saveDoc(customerId: cid, quote: false, lines: [
        SellLine(productId: pid, batchId: bid, name: 'Soap', price: rs(70), qty: 10)
      ]);
    });

    test('a cheque taken in comes off what is owed straight away', () async {
      final owed = await balance(cid);
      await aCheque(amount: rs(400));

      expect(await balance(cid), owed - rs(400),
          reason: 'the counter treats a cheque as settled up');
      expect(await ledger(cid), hasLength(2), reason: 'the sale and its payment');
      expect((await stats()).cheques, rs(400),
          reason: 'still flagged as riding on the bank');
    });

    test('taking a cheque settles the bill it covers', () async {
      final owed = await balance(cid);
      final id = await aCheque(amount: owed);

      expect(await balance(cid), 0);
      expect((await docs(kind: 'sale')).single.due, 0,
          reason: 'it settles like any other payment');
      expect((await oneCheque(id))!.isPending, isTrue,
          reason: 'credited, but the bank has not confirmed it yet');
    });

    test('a cheque leaves a numbered payment that can be reprinted', () async {
      final id = await aCheque(amount: rs(400));

      final ledgerId = (await oneCheque(id))!.ledgerId!;
      final e = (await ledgerEntry(ledgerId))!;
      expect(e.type, 'payment');
      expect(e.amount, -rs(400));
      expect(e.no, greaterThan(0), reason: 'a receipt number to hand over');
      expect(e.note, contains('400123'), reason: 'says which cheque it was');
    });

    test('marking it banked confirms it without moving the money again',
        () async {
      final id = await aCheque(amount: rs(400));
      final after = await balance(cid);

      await clearCheque(id);

      expect(await balance(cid), after, reason: 'it was already credited');
      expect((await oneCheque(id))!.isCleared, isTrue);
      expect(await ledger(cid), hasLength(2), reason: 'no second payment row');
      expect((await stats()).cheques, 0, reason: 'no longer riding on the bank');
    });

    test('a bounced cheque puts the amount back on the account', () async {
      final owed = await balance(cid);
      final id = await aCheque(amount: rs(400));
      expect(await balance(cid), owed - rs(400));

      await bounceCheque(id);

      expect(await balance(cid), owed, reason: 'they owe exactly what they did');
      expect((await docs(kind: 'sale')).single.due, owed,
          reason: 'the bill it had cleared re-opens on its own');
      expect((await oneCheque(id))!.isBounced, isTrue);
      expect((await stats()).cheques, 0);
      expect(await ledger(cid), hasLength(3),
          reason: 'sale, credit and its reversal all stay on the account');
    });

    test('bouncing the same cheque twice cannot charge them twice', () async {
      final id = await aCheque(amount: rs(400));
      await bounceCheque(id);
      final after = await balance(cid);

      expect(() => bounceCheque(id), throwsA(isA<Exception>()));

      expect(await balance(cid), after);
      expect(await ledger(cid), hasLength(3));
    });

    test('marking the same cheque banked twice changes nothing', () async {
      final id = await aCheque(amount: rs(400));
      await clearCheque(id);
      final after = await balance(cid);

      expect(() => clearCheque(id), throwsA(isA<Exception>()));

      expect(await balance(cid), after);
      expect(await ledger(cid), hasLength(2), reason: 'sale and one payment only');
    });

    test('a cheque already banked cannot then be marked returned', () async {
      final id = await aCheque(amount: rs(400));
      await clearCheque(id);
      final after = await balance(cid);

      expect(() => clearCheque(id), throwsA(isA<Exception>()));
      expect(await balance(cid), after);
    });

    test('undoing a cheque payment marks the cheque returned', () async {
      final id = await aCheque(amount: rs(400));
      final ledgerId = (await oneCheque(id))!.ledgerId!;
      final owed = await balance(cid);

      await undoPayment(ledgerId);

      expect((await oneCheque(id))!.isBounced, isTrue,
          reason: 'pulling the credit is the same event as the bank refusing it');
      expect(await balance(cid), owed + rs(400));
      expect((await stats()).cheques, 0);
    });

    test('a cheque needs a number and a real amount', () async {
      expect(
          () => saveCheque(
              customerId: cid, chequeNo: '  ', amount: rs(100), dueAt: 0),
          throwsA(isA<Exception>()));
      expect(
          () => saveCheque(
              customerId: cid, chequeNo: '400123', amount: 0, dueAt: 0),
          throwsA(isA<Exception>()));
      expect(await cheques(), isEmpty);
    });

    test('waiting cheques come first, nearest banking date at the top',
        () async {
      final now = DateTime.now();
      int inDays(int d) => now.add(Duration(days: d)).millisecondsSinceEpoch;

      final far = await saveCheque(
          customerId: cid, chequeNo: 'A', amount: rs(100), dueAt: inDays(30));
      final soon = await saveCheque(
          customerId: cid, chequeNo: 'B', amount: rs(100), dueAt: inDays(2));
      final done = await saveCheque(
          customerId: cid, chequeNo: 'C', amount: rs(100), dueAt: inDays(1));
      await clearCheque(done);

      expect((await cheques()).map((c) => c.id).toList(), [soon, far, done]);
      expect((await cheques(status: 'pending')).map((c) => c.chequeNo), ['B', 'A']);
      expect((await cheques(q: 'Sampath')), isEmpty, reason: 'these had no bank set');
    });
  });
}

Future<Map<String, String>> allSettingsMap() async {
  await loadSettings();
  return settings;
}

bool balanceLabelIsAdvance(int cents) => cents < 0;
