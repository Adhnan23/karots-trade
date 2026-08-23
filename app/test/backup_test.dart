import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:karots_trade/db.dart';
import 'package:karots_trade/files.dart';
import 'package:karots_trade/models.dart';
import 'package:karots_trade/store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Batch;

int rs(num v) => (v * 100).round();

/// A photo big enough that base64 round-tripping is actually exercised.
final photo = Uint8List.fromList(List.generate(3000, (i) => (i * 37) % 256));

/// Fills the database with something touching every single table.
Future<void> seed() async {
  await setSetting('business_name', 'Karots Traders');
  await setSetting('business_phone', '077 123 4567');
  await setSetting('language', 'ta');
  await setSetting('product_view', 'list');

  final cola = await saveProduct(name: 'Coca-Cola 1L', image: photo);
  final soap = await saveProduct(name: 'Soap');

  await savePurchase([
    BuyLine(productId: cola, cost: rs(150), price: rs(180), qty: 20),
    BuyLine(productId: soap, cost: rs(50), price: rs(70), qty: 30),
  ]);
  await savePurchase([
    BuyLine(productId: cola, cost: rs(160), price: rs(190), qty: 15),
    BuyLine(name: 'Biscuits', cost: rs(80), price: rs(110), qty: 40),
  ]);

  final abc = await saveCustomer(name: 'ABC Shop', phone: '0712345678');
  final nimal = await saveCustomer(name: 'Nimal Stores', phone: '0779876543');

  final colaBatches = await batches(cola);
  SellLine line(Batch b, int qty) => SellLine(
      productId: cola, batchId: b.id, name: 'Coca-Cola 1L', price: b.price, qty: qty);

  // A paid-in-part sale, a quotation, a converted quotation, a cancelled sale,
  // an advance, a return and a stock correction.
  final sale = await saveDoc(
      customerId: abc, quote: false, lines: [line(colaBatches[0], 10)], paid: rs(1000));
  await recordPayment(abc, rs(500));
  await saveReturn(sale, {(await docItems(sale)).first.id: 2});

  final quote =
      await saveDoc(customerId: nimal, quote: true, lines: [line(colaBatches[1], 5)]);
  await recordPayment(nimal, rs(2000));
  await convertQuote(quote);

  final doomed =
      await saveDoc(customerId: abc, quote: false, lines: [line(colaBatches[0], 1)]);
  await cancelDoc(doomed);

  await fixBatch(colaBatches[1].id, qty: 9, cost: rs(160), price: rs(195),
      reason: 'One case damaged');
}

/// Everything in the database, as comparable plain values.
Future<Map<String, List<Map<String, Object?>>>> snapshot() async {
  final out = <String, List<Map<String, Object?>>>{};
  for (final table in tables) {
    out[table] = (await db.query(table, orderBy: 'rowid'))
        .map((r) => r.map((k, v) =>
            MapEntry(k, v is Uint8List ? 'blob:${base64Encode(v)}' : v)))
        .toList();
  }
  return out;
}

void main() {
  setUp(() async => openDb(path: inMemoryDatabasePath));
  tearDown(closeDb);

  test('a backup restored into a fresh install is identical, row for row',
      () async {
    await seed();
    final before = await snapshot();
    final backup = await exportBackup();

    // Every table actually has something in it — otherwise this proves nothing.
    for (final e in before.entries) {
      expect(e.value, isNotEmpty, reason: '${e.key} was never exercised');
    }

    // Reinstall: brand new empty database, then restore.
    await closeDb();
    await openDb(path: inMemoryDatabasePath);
    for (final table in tables) {
      expect(await db.query(table), isEmpty, reason: '$table should start empty');
    }
    await importBackup(backup);

    expect(await snapshot(), before);
  });

  test('the restored database still works and adds up', () async {
    await seed();
    final backup = await exportBackup();
    final owedBefore = (await stats()).owed;

    await closeDb();
    await openDb(path: inMemoryDatabasePath);
    await importBackup(backup);
    await loadSettings();

    // Settings came back, photos came back, stock and balances came back.
    expect(businessName, 'Karots Traders');
    expect(settings['language'], 'ta');
    expect(productsAsCards, isFalse);

    final cola = (await products(q: 'Coca')).single;
    expect(cola.image, photo, reason: 'product photo survived');
    expect((await stats()).owed, owedBefore);

    final abc = (await customers(q: 'ABC')).single;
    final history = await ledger(abc.id);
    expect(history.map((e) => e.type),
        containsAll(['sale', 'payment', 'return', 'sale_cancelled']));
    expect(await balance(abc.id), abc.balance);

    // And the restored data is live, not just readable.
    final b = (await batches(cola.id)).first;
    final before = b.qtyLeft;
    await saveDoc(customerId: abc.id, quote: false, lines: [
      SellLine(
          productId: cola.id, batchId: b.id, name: cola.name, price: b.price, qty: 1)
    ]);
    expect((await batches(cola.id)).first.qtyLeft, before - 1);
    expect(await balance(abc.id), abc.balance + b.price);
  });

  test('numbering carries on where the backup left off', () async {
    await seed();
    final backup = await exportBackup();
    final lastSale = (await docs(kind: 'sale')).first.no;

    await closeDb();
    await openDb(path: inMemoryDatabasePath);
    await importBackup(backup);

    final cust = (await customers()).first;
    final b = (await batches((await products()).first.id)).first;
    final next = await saveDoc(customerId: cust.id, quote: false, lines: [
      SellLine(productId: b.productId, batchId: b.id, name: b.productName, price: b.price, qty: 1)
    ]);
    expect((await doc(next))!.no, lastSale + 1, reason: 'no duplicate receipt numbers');
  });

  test('a backup from an older version restores without its newer tables',
      () async {
    await seed();
    final full = jsonDecode(utf8.decode(await exportBackup())) as Map<String, Object?>;

    // Simulate a file written before stock corrections and advances existed.
    full.remove('adjustments');
    for (final row in full['docs'] as List) {
      (row as Map).remove('advance_used');
    }
    for (final row in full['ledger'] as List) {
      (row as Map).remove('no');
    }
    final old = Uint8List.fromList(utf8.encode(jsonEncode(full)));

    await closeDb();
    await openDb(path: inMemoryDatabasePath);
    await importBackup(old);

    expect((await products()).length, 3);
    expect((await adjustments()), isEmpty);
    expect((await docs()).first.settled, isNonNegative,
        reason: 'settlement is derived, so an old file loses nothing');
    final cust = (await customers(q: 'ABC')).single;
    expect(await balance(cust.id), cust.balance);
  });

  test('a broken file changes nothing', () async {
    await seed();
    final before = await snapshot();

    for (final junk in [
      'not a backup',
      '{}',
      '{"products": null}',
      '[1,2,3]',
      '',
    ]) {
      expect(() => importBackup(Uint8List.fromList(utf8.encode(junk))),
          throwsA(isA<Object>()),
          reason: 'should refuse: $junk');
    }
    expect(await snapshot(), before, reason: 'nothing was touched');
  });

  test('a truncated backup rolls back completely', () async {
    await seed();
    final before = await snapshot();

    // Valid JSON, valid products, but a sale pointing at a customer that the
    // file never included — the insert fails partway through.
    final data = jsonDecode(utf8.decode(await exportBackup())) as Map<String, Object?>;
    (data['customers'] as List).clear();
    final broken = Uint8List.fromList(utf8.encode(jsonEncode(data)));

    expect(() => importBackup(broken), throwsA(isA<Object>()));
    expect(await snapshot(), before,
        reason: 'a half-applied restore would be worse than no restore');
  });

  test('the backup file is plain readable JSON', () async {
    await seed();
    final decoded =
        jsonDecode(utf8.decode(await exportBackup())) as Map<String, Object?>;

    expect(decoded['version'], 2);
    expect(decoded['at'], isA<String>());
    for (final table in tables) {
      expect(decoded[table], isA<List>(), reason: '$table missing from the file');
    }
    // Photos travel as base64 inside the same file, not as separate files.
    final product = (decoded['products'] as List)
        .cast<Map>()
        .firstWhere((p) => p['image'] != null);
    expect(base64Decode((product['image'] as Map)['b64'] as String), photo);
  });
}
