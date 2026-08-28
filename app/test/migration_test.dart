import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:karots_trade/db.dart';
import 'package:karots_trade/store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Batch;

/// The shipped version 1 schema, kept verbatim so the upgrade path is tested
/// against what is actually sitting on the phone.
const _v1 = [
  '''CREATE TABLE products(id TEXT PRIMARY KEY, name TEXT NOT NULL, image BLOB,
      created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)''',
  '''CREATE TABLE batches(id TEXT PRIMARY KEY, product_id TEXT NOT NULL,
      cost INTEGER NOT NULL, price INTEGER NOT NULL, qty_in INTEGER NOT NULL,
      qty_left INTEGER NOT NULL, purchase_id TEXT, created_at INTEGER NOT NULL)''',
  '''CREATE TABLE purchases(id TEXT PRIMARY KEY, no INTEGER NOT NULL,
      total INTEGER NOT NULL, created_at INTEGER NOT NULL)''',
  '''CREATE TABLE purchase_items(id TEXT PRIMARY KEY, purchase_id TEXT NOT NULL,
      product_id TEXT NOT NULL, batch_id TEXT NOT NULL, name TEXT NOT NULL,
      cost INTEGER NOT NULL, price INTEGER NOT NULL, qty INTEGER NOT NULL)''',
  '''CREATE TABLE customers(id TEXT PRIMARY KEY, name TEXT NOT NULL,
      phone TEXT NOT NULL DEFAULT '', created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL)''',
  '''CREATE TABLE docs(id TEXT PRIMARY KEY, no INTEGER NOT NULL, kind TEXT NOT NULL,
      status TEXT NOT NULL, customer_id TEXT NOT NULL, total INTEGER NOT NULL,
      paid INTEGER NOT NULL DEFAULT 0, from_quote TEXT,
      note TEXT NOT NULL DEFAULT '', created_at INTEGER NOT NULL)''',
  '''CREATE TABLE doc_items(id TEXT PRIMARY KEY, doc_id TEXT NOT NULL,
      product_id TEXT NOT NULL, batch_id TEXT NOT NULL, name TEXT NOT NULL,
      qty INTEGER NOT NULL, price INTEGER NOT NULL,
      returned INTEGER NOT NULL DEFAULT 0)''',
  '''CREATE TABLE returns(id TEXT PRIMARY KEY, no INTEGER NOT NULL,
      doc_id TEXT NOT NULL, customer_id TEXT NOT NULL, total INTEGER NOT NULL,
      created_at INTEGER NOT NULL)''',
  '''CREATE TABLE return_items(id TEXT PRIMARY KEY, return_id TEXT NOT NULL,
      item_id TEXT NOT NULL, batch_id TEXT NOT NULL, name TEXT NOT NULL,
      qty INTEGER NOT NULL, price INTEGER NOT NULL)''',
  '''CREATE TABLE ledger(id TEXT PRIMARY KEY, customer_id TEXT NOT NULL,
      type TEXT NOT NULL, amount INTEGER NOT NULL, ref_id TEXT,
      note TEXT NOT NULL DEFAULT '', created_at INTEGER NOT NULL)''',
  'CREATE TABLE settings(key TEXT PRIMARY KEY, value TEXT NOT NULL)',
];

void main() {
  late Directory dir;
  late String path;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    dir = await Directory.systemTemp.createTemp('karots');
    path = '${dir.path}/karots_trade.db';
  });
  tearDown(() async {
    await closeDb();
    await dir.delete(recursive: true);
  });

  test('a version 1 database keeps its data and gains the new columns',
      () async {
    // Build a v1 database with a sale already recorded in it.
    final old = await databaseFactory.openDatabase(path,
        options: OpenDatabaseOptions(
            version: 1,
            onCreate: (d, _) async {
              for (final q in _v1) {
                await d.execute(q);
              }
            }));
    final now = DateTime.now().millisecondsSinceEpoch;
    await old.insert('products',
        {'id': 'p1', 'name': 'Coca-Cola 1L', 'created_at': now, 'updated_at': now});
    await old.insert('batches', {
      'id': 'b1', 'product_id': 'p1', 'cost': 15000, 'price': 18000,
      'qty_in': 20, 'qty_left': 10, 'created_at': now,
    });
    await old.insert('customers',
        {'id': 'c1', 'name': 'ABC Shop', 'phone': '0712345678', 'created_at': now, 'updated_at': now});
    await old.insert('docs', {
      'id': 'd1', 'no': 1, 'kind': 'sale', 'status': 'active', 'customer_id': 'c1',
      'total': 180000, 'paid': 100000, 'created_at': now,
    });
    await old.insert('doc_items', {
      'id': 'i1', 'doc_id': 'd1', 'product_id': 'p1', 'batch_id': 'b1',
      'name': 'Coca-Cola 1L', 'qty': 10, 'price': 18000,
    });
    await old.insert('ledger', {
      'id': 'l1', 'customer_id': 'c1', 'type': 'sale', 'amount': 180000,
      'ref_id': 'd1', 'created_at': now,
    });
    await old.insert('ledger', {
      'id': 'l2', 'customer_id': 'c1', 'type': 'payment', 'amount': -100000,
      'ref_id': 'd1', 'created_at': now,
    });
    await old.close();

    // Reopen with the current app.
    await openDb(path: path);

    expect((await products()).single.stock, 10, reason: 'stock untouched');
    expect(await balance('c1'), 80000, reason: 'balance untouched');

    final d = (await doc('d1'))!;
    expect(d.paid, 100000);
    expect(d.settled, 100000, reason: 'derived from the ledger that came across');
    expect(d.due, 80000);

    // The new tables and columns are usable straight away.
    expect((await ledger('c1')).first.no, 0);
    await fixBatch('b1', qty: 9, cost: 15000, price: 18000, reason: 'One broken');
    expect((await adjustments()).single['qty_after'], 9);

    // And a new payment numbers itself from a clean slate.
    final pay = await recordPayment('c1', 50000);
    expect((await ledgerEntry(pay))!.no, 1);
    expect(await balance('c1'), 30000);

    // Cheques and discounts arrived later; the old sale simply has neither.
    expect((await docItems('d1')).single.discount, 0,
        reason: 'a line written before discounts existed is not a discount');
    expect(await cheques(), isEmpty);

    final ch = await saveCheque(
        customerId: 'c1',
        chequeNo: '400123',
        amount: 30000,
        dueAt: DateTime.now().millisecondsSinceEpoch);
    expect(await balance('c1'), 0, reason: 'a cheque credits the account at once');
    await clearCheque(ch);
    expect(await balance('c1'), 0, reason: 'confirming it moves nothing again');

    // Adjustments arrived later still, and land on a database that never had
    // one — including the balance the customer walked in with.
    await adjustBalance('c1', 5000, note: 'Old debt', opening: true);
    expect(await balance('c1'), 5000);
  });

  test('cheques taken before v5 get the credit the new rule gives them',
      () async {
    // v4 kept a waiting cheque out of the ledger. v5 credits it on arrival, so
    // the upgrade owes every cheque still waiting the payment row it missed.
    final db = await databaseFactory.openDatabase(path,
        options: OpenDatabaseOptions(
            version: 4,
            onCreate: (d, _) async {
              for (final st in schema) {
                await d.execute(st);
              }
            }));
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert('customers',
        {'id': 'c1', 'name': 'Old Shop', 'created_at': now, 'updated_at': now});
    await db.insert('ledger', {
      'id': 'l1', 'no': 0, 'customer_id': 'c1', 'type': 'sale',
      'amount': 100000, 'created_at': now,
    });
    for (final (id, no, amount, status) in [
      ('h1', 1, 30000, 'pending'),
      ('h2', 2, 20000, 'bounced'),
    ]) {
      await db.insert('cheques', {
        'id': id, 'no': no, 'customer_id': 'c1', 'cheque_no': '4001$no',
        'amount': amount, 'due_at': now, 'status': status, 'created_at': now,
      });
    }
    await db.close();

    await openDb(path: path);

    expect(await balance('c1'), 70000,
        reason: 'the waiting cheque now comes off the balance');
    final waiting = (await cheques(status: 'pending')).single;
    expect(waiting.ledgerId, isNotNull, reason: 'linked to the row it wrote');
    expect((await ledgerEntry(waiting.ledgerId!))!.amount, -30000);
    expect((await ledger('c1')).where((e) => e.type == 'payment'), hasLength(1),
        reason: 'the bounced one is not resurrected');
  });
}
