import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:karots_trade/db.dart';
import 'package:karots_trade/files.dart';
import 'package:karots_trade/models.dart';
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
