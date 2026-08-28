import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Batch;

import 'db.dart';
import 'models.dart';

final _rnd = Random.secure();

String uid() =>
    '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${_rnd.nextInt(1 << 32).toRadixString(36)}';

int _now() => DateTime.now().millisecondsSinceEpoch;

Future<int> _nextNo(DatabaseExecutor d, String table, [String? where]) async {
  final r = await d.rawQuery(
      'SELECT IFNULL(MAX(no),0)+1 n FROM $table${where == null ? '' : ' WHERE $where'}');
  return (r.first['n'] as num).toInt();
}

String _like(String q) => '%${q.trim()}%';

// ============================================================ products

Future<List<Product>> products({String q = ''}) async => (await db.rawQuery('''
      SELECT p.*, IFNULL(SUM(b.qty_left),0) stock
      FROM products p LEFT JOIN batches b ON b.product_id = p.id
      WHERE p.name LIKE ?
      GROUP BY p.id ORDER BY p.name COLLATE NOCASE''', [_like(q)]))
    .map(Product.fromRow)
    .toList();

Future<Product?> product(String id) async {
  final r = await db.rawQuery('''
      SELECT p.*, IFNULL(SUM(b.qty_left),0) stock
      FROM products p LEFT JOIN batches b ON b.product_id = p.id
      WHERE p.id = ? GROUP BY p.id''', [id]);
  return r.isEmpty ? null : Product.fromRow(r.first);
}

Future<String> saveProduct(
    {String? id, required String name, Uint8List? image, bool clearImage = false}) async {
  name = name.trim();
  if (name.isEmpty) throw Exception('Product name is required');
  final now = _now();
  if (id == null) {
    final newId = uid();
    await db.insert('products', {
      'id': newId,
      'name': name,
      'image': image,
      'created_at': now,
      'updated_at': now,
    });
    return newId;
  }
  await db.update(
      'products',
      {
        'name': name,
        'updated_at': now,
        if (image != null || clearImage) 'image': image,
      },
      where: 'id = ?',
      whereArgs: [id]);
  return id;
}

/// A product can only go away if it never took part in anything.
///
/// Stock counts as taking part: `batches` cascade-deletes with the product, so
/// deleting one that was ever bought in would quietly take its stock — and the
/// money that stock is worth — with it. Use a batch correction to zero it out
/// instead; that leaves a record. A product typed by mistake and never bought
/// has no batches, so it still deletes cleanly.
Future<void> deleteProduct(String id) async {
  final used = (await db.rawQuery('''
      SELECT (SELECT COUNT(*) FROM doc_items WHERE product_id = ?)
           + (SELECT COUNT(*) FROM batches WHERE product_id = ?)
           + (SELECT COUNT(*) FROM purchase_items WHERE product_id = ?) n''',
      [id, id, id])).first['n'] as int;
  if (used > 0) {
    throw Exception('This product has been bought or sold and cannot be deleted');
  }
  await db.delete('products', where: 'id = ?', whereArgs: [id]);
}

Future<List<Batch>> batches(String productId, {bool availableOnly = false}) async =>
    (await db.rawQuery('''
      SELECT b.*, p.name FROM batches b JOIN products p ON p.id = b.product_id
      WHERE b.product_id = ? ${availableOnly ? 'AND b.qty_left > 0' : ''}
      ORDER BY b.created_at''', [productId]))
        .map(Batch.fromRow)
        .toList();

/// Corrects a batch that was entered wrong: wrong count on the shelf, a typo
/// in the cost, a selling price that should have been different. Past sales
/// keep the price they were charged — only this batch changes from now on.
Future<String> fixBatch(
  String batchId, {
  required int qty,
  required int cost,
  required int price,
  String reason = '',
}) async {
  if (qty < 0) throw Exception('Quantity cannot be negative');
  if (cost < 0 || price < 0) throw Exception('Prices cannot be negative');

  final id = uid();
  await db.transaction((tx) async {
    final rows = await tx.rawQuery('''
        SELECT b.*, p.name FROM batches b JOIN products p ON p.id = b.product_id
        WHERE b.id = ?''', [batchId]);
    if (rows.isEmpty) throw Exception('Batch not found');
    final b = Batch.fromRow(rows.first);

    if (b.qtyLeft == qty && b.cost == cost && b.price == price) {
      throw Exception('Nothing changed');
    }

    await tx.update(
        'batches',
        {
          'qty_left': qty,
          'cost': cost,
          'price': price,
          // Received count follows an upward correction so the shelf never
          // shows more left than ever came in.
          if (qty > b.qtyIn) 'qty_in': qty,
        },
        where: 'id = ?',
        whereArgs: [batchId]);

    await tx.insert('adjustments', {
      'id': id,
      'no': await _nextNo(tx, 'adjustments'),
      'product_id': b.productId,
      'batch_id': batchId,
      'name': b.productName,
      'qty_before': b.qtyLeft,
      'qty_after': qty,
      'cost_before': b.cost,
      'cost_after': cost,
      'price_before': b.price,
      'price_after': price,
      'reason': reason.trim(),
      'created_at': _now(),
    });
  });
  return id;
}

Future<List<SqlRow>> adjustments({String? productId, int limit = 50}) => db.query(
      'adjustments',
      where: productId == null ? null : 'product_id = ?',
      whereArgs: productId == null ? null : [productId],
      orderBy: 'created_at DESC',
      limit: limit,
    );

// ============================================================ purchases

/// Records a purchase. Each distinct cost/selling-price pair becomes its own
/// batch; buying at a price combination that already exists tops that batch up.
Future<String> savePurchase(List<BuyLine> lines) async {
  if (lines.isEmpty) throw Exception('Add at least one item');
  for (final l in lines) {
    if (l.productId == null && l.name.trim().isEmpty) {
      throw Exception('Product name is required');
    }
    if (l.qty <= 0) throw Exception('Quantity must be more than zero');
    if (l.cost < 0 || l.price < 0) throw Exception('Prices cannot be negative');
  }

  final id = uid();
  await db.transaction((tx) async {
    final now = _now();
    await tx.insert('purchases', {
      'id': id,
      'no': await _nextNo(tx, 'purchases'),
      'total': lines.fold<int>(0, (s, l) => s + l.total),
      'created_at': now,
    });

    for (final l in lines) {
      var productId = l.productId;
      var name = l.name.trim();
      if (productId == null) {
        productId = uid();
        await tx.insert('products', {
          'id': productId,
          'name': name,
          'image': l.image,
          'created_at': now,
          'updated_at': now,
        });
      } else {
        name = ((await tx.query('products',
                    columns: ['name'], where: 'id = ?', whereArgs: [productId]))
                .first['name'] as String?) ??
            name;
      }

      final same = await tx.query('batches',
          where: 'product_id = ? AND cost = ? AND price = ?',
          whereArgs: [productId, l.cost, l.price],
          limit: 1);
      String batchId;
      if (same.isEmpty) {
        batchId = uid();
        await tx.insert('batches', {
          'id': batchId,
          'product_id': productId,
          'cost': l.cost,
          'price': l.price,
          'qty_in': l.qty,
          'qty_left': l.qty,
          'purchase_id': id,
          'created_at': now,
        });
      } else {
        batchId = same.first['id'] as String;
        await tx.rawUpdate(
            'UPDATE batches SET qty_in = qty_in + ?, qty_left = qty_left + ? WHERE id = ?',
            [l.qty, l.qty, batchId]);
      }

      await tx.insert('purchase_items', {
        'id': uid(),
        'purchase_id': id,
        'product_id': productId,
        'batch_id': batchId,
        'name': name,
        'cost': l.cost,
        'price': l.price,
        'qty': l.qty,
      });
    }
  });
  return id;
}

Future<List<SqlRow>> purchases({String q = '', DateTime? from, DateTime? to}) {
  final w = <String>[], a = <Object?>[];
  if (q.trim().isNotEmpty) {
    w.add('no = ?');
    a.add(int.tryParse(q.trim().replaceAll('#', '')) ?? -1);
  }
  if (from != null) {
    w.add('created_at >= ?');
    a.add(from.millisecondsSinceEpoch);
  }
  if (to != null) {
    w.add('created_at <= ?');
    a.add(to.millisecondsSinceEpoch);
  }
  return db.query('purchases',
      where: w.isEmpty ? null : w.join(' AND '),
      whereArgs: a,
      orderBy: 'created_at DESC');
}

Future<(SqlRow, List<SqlRow>)?> onePurchase(String id) async {
  final r = await db.query('purchases', where: 'id = ?', whereArgs: [id]);
  if (r.isEmpty) return null;
  return (r.first, await purchaseItems(id));
}

Future<List<SqlRow>> purchaseItems(String id) =>
    db.query('purchase_items', where: 'purchase_id = ?', whereArgs: [id]);

// ============================================================ customers

Future<List<Customer>> customers({String q = ''}) async => (await db.rawQuery('''
      SELECT c.*, IFNULL(SUM(l.amount),0) balance
      FROM customers c LEFT JOIN ledger l ON l.customer_id = c.id
      WHERE c.name LIKE ? OR c.phone LIKE ?
      GROUP BY c.id ORDER BY c.name COLLATE NOCASE''', [_like(q), _like(q)]))
    .map(Customer.fromRow)
    .toList();

Future<Customer?> customer(String id) async {
  final r = await db.rawQuery('''
      SELECT c.*, IFNULL(SUM(l.amount),0) balance
      FROM customers c LEFT JOIN ledger l ON l.customer_id = c.id
      WHERE c.id = ? GROUP BY c.id''', [id]);
  return r.isEmpty ? null : Customer.fromRow(r.first);
}

Future<String> saveCustomer({String? id, required String name, String phone = ''}) async {
  name = name.trim();
  if (name.isEmpty) throw Exception('Customer name is required');
  final now = _now();
  if (id == null) {
    final newId = uid();
    await db.insert('customers', {
      'id': newId,
      'name': name,
      'phone': phone.trim(),
      'created_at': now,
      'updated_at': now,
    });
    return newId;
  }
  await db.update('customers', {'name': name, 'phone': phone.trim(), 'updated_at': now},
      where: 'id = ?', whereArgs: [id]);
  return id;
}

/// Only a customer with no history at all can be removed.
///
/// The ledger and cheques both cascade-delete with the customer, so an account
/// holding an advance — money already handed over — would disappear along with
/// them if `docs` were the only thing checked.
Future<void> deleteCustomer(String id) async {
  final used = (await db.rawQuery('''
      SELECT (SELECT COUNT(*) FROM docs WHERE customer_id = ?)
           + (SELECT COUNT(*) FROM ledger WHERE customer_id = ?)
           + (SELECT COUNT(*) FROM cheques WHERE customer_id = ?) n''',
      [id, id, id])).first['n'] as int;
  if (used > 0) {
    throw Exception('This customer has transactions and cannot be deleted');
  }
  await db.delete('customers', where: 'id = ?', whereArgs: [id]);
}

/// Positive = customer owes you. Negative = customer has an advance with you.
Future<int> balance(String customerId) async =>
    ((await db.rawQuery('SELECT IFNULL(SUM(amount),0) b FROM ledger WHERE customer_id = ?',
                [customerId]))
            .first['b'] as num)
        .toInt();

/// Newest first, each row carrying the balance as it stood right after it —
/// that is what a payment receipt has to print.
Future<List<LedgerEntry>> ledger(String customerId) async => (await db.rawQuery('''
      SELECT *, SUM(amount) OVER (ORDER BY created_at, rowid) balance_after
      FROM ledger WHERE customer_id = ?
      ORDER BY created_at DESC, rowid DESC''', [customerId]))
    .map(LedgerEntry.fromRow)
    .toList();

Future<LedgerEntry?> ledgerEntry(String id) async {
  final r = await db.rawQuery('''
      SELECT * FROM (
        SELECT *, SUM(amount) OVER (ORDER BY created_at, rowid) balance_after
        FROM ledger
        WHERE customer_id = (SELECT customer_id FROM ledger WHERE id = ?))
      WHERE id = ?''', [id, id]);
  return r.isEmpty ? null : LedgerEntry.fromRow(r.first);
}

/// Works for both settling a debt and paying in advance — an advance is simply
/// a payment recorded while nothing is owed, which pushes the balance negative.
Future<String> recordPayment(String customerId, int amount, {String note = ''}) async {
  if (amount <= 0) throw Exception('Payment must be more than zero');
  final id = uid();
  await db.transaction((tx) async {
    await tx.insert('ledger', {
      'id': id,
      'no': await _nextNo(tx, 'ledger', "type = 'payment'"),
      'customer_id': customerId,
      'type': 'payment',
      'amount': -amount,
      'ref_id': null,
      'note': note,
      'created_at': _now(),
    });
  });
  return id;
}

/// A correction made by hand, and the one way a balance moves without a sale
/// or a payment behind it.
///
/// [amount] is signed the way the ledger is: positive means the customer owes
/// more, negative means they owe less. [opening] marks the balance a customer
/// walked in with — what they already owed before any of this was on a phone —
/// and it is backdated to the day they were added so every later payment
/// settles it first.
Future<String> adjustBalance(String customerId, int amount,
    {String note = '', bool opening = false}) async {
  if (amount == 0) throw Exception('Enter an amount to adjust');
  final id = uid();
  await db.transaction((tx) async {
    final c = await tx.query('customers', where: 'id = ?', whereArgs: [customerId]);
    if (c.isEmpty) throw Exception('Not found');

    if (opening) {
      // Two opening balances means the customer owes their old debt twice,
      // which is exactly the mistake a second tap on Save would make.
      final had = await tx.query('ledger',
          where: "customer_id = ? AND type = 'opening'", whereArgs: [customerId]);
      if (had.isNotEmpty) {
        throw Exception('This customer already has an opening balance');
      }
    }

    await tx.insert('ledger', {
      'id': id,
      'customer_id': customerId,
      'type': opening ? 'opening' : 'adjustment',
      'amount': amount,
      'ref_id': null,
      'note': note.trim(),
      'created_at':
          opening ? (c.first['created_at'] as num).toInt() : _now(),
    });
  });
  return id;
}

/// Undoes a payment that was entered wrong — the wrong amount, or the wrong
/// customer.
///
/// The original row is never deleted. The ledger only ever grows, so both the
/// mistake and its correction stay on the account where anyone can see what
/// happened. Putting the money back is enough on its own: settlement is
/// derived, so any bill this payment had cleared re-opens by itself.
Future<String> undoPayment(String ledgerId) async {
  final id = uid();
  await db.transaction((tx) async {
    final rows = await tx.query('ledger', where: 'id = ?', whereArgs: [ledgerId]);
    if (rows.isEmpty) throw Exception('Payment not found');
    final e = LedgerEntry.fromRow(rows.first);
    if (e.type != 'payment') throw Exception('Only a payment can be undone');

    final already = await tx.query('ledger',
        where: "type = 'payment_cancelled' AND ref_id = ?", whereArgs: [ledgerId]);
    if (already.isNotEmpty) throw Exception('This payment was already undone');

    // Cash handed over as part of a sale belongs to that sale. Pulling it out
    // on its own would leave the bill claiming something that never happened,
    // so that case has to go through cancelling the sale.
    if (e.refId != null) {
      final onSale = await tx.query('docs', where: 'id = ?', whereArgs: [e.refId]);
      if (onSale.isNotEmpty) {
        throw Exception('This was paid with the sale, so cancel the sale instead');
      }
    }

    // Pulling a cheque's credit back off the account is the same event as the
    // bank sending it back, so the cheque has to say so too.
    await tx.rawUpdate(
        "UPDATE cheques SET status = 'bounced', settled_at = ? WHERE ledger_id = ?",
        [_now(), ledgerId]);

    await tx.insert('ledger', {
      'id': id,
      'customer_id': e.customerId,
      'type': 'payment_cancelled',
      'amount': -e.amount, // the payment was negative, so this puts it back
      'ref_id': ledgerId,
      'note': 'Payment #${e.no} undone',
      'created_at': _now(),
    });
  });
  return id;
}

// ============================================================ cheques

/// Records a cheque handed over as payment, and credits the account there and
/// then.
///
/// Taking a cheque is how these customers settle up, so the balance has to drop
/// the moment it changes hands — waiting on the bank would leave the counter
/// looking at a figure nobody agrees with. The cheque row keeps its own status
/// alongside, so the one case that does need unwinding — it comes back unpaid —
/// is still a single tap away in [bounceCheque].
Future<String> saveCheque({
  required String customerId,
  required String chequeNo,
  required int amount,
  required int dueAt,
  String bank = '',
  String note = '',
}) async {
  if (amount <= 0) throw Exception('Payment must be more than zero');
  if (chequeNo.trim().isEmpty) throw Exception('Cheque number is required');

  final id = uid(), ledgerId = uid();
  await db.transaction((tx) async {
    final now = _now();
    await tx.insert('cheques', {
      'id': id,
      'no': await _nextNo(tx, 'cheques'),
      'customer_id': customerId,
      'cheque_no': chequeNo.trim(),
      'bank': bank.trim(),
      'amount': amount,
      'due_at': dueAt,
      'status': 'pending',
      'ledger_id': ledgerId,
      'note': note.trim(),
      'created_at': now,
    });
    await tx.insert('ledger', {
      'id': ledgerId,
      'no': await _nextNo(tx, 'ledger', "type = 'payment'"),
      'customer_id': customerId,
      'type': 'payment',
      'amount': -amount,
      'ref_id': id,
      'note': 'Cheque ${chequeNo.trim()}',
      'created_at': now,
    });
  });
  return id;
}

/// The bank paid, as expected. The money was credited when the cheque came in,
/// so this only records that it is now beyond doubt.
///
/// The status guard makes a double tap harmless: the second attempt updates no
/// rows and is refused.
Future<void> clearCheque(String id) async {
  final ok = await db.rawUpdate(
      "UPDATE cheques SET status = 'cleared', settled_at = ? "
      "WHERE id = ? AND status = 'pending'",
      [_now(), id]);
  if (ok != 1) throw Exception('This cheque is already settled');
}

/// The bank sent it back, so the credit it was given has to come off again.
///
/// The reversal is a new ledger row rather than a deletion: both the credit and
/// its withdrawal stay on the account, and because settlement is derived, every
/// bill the cheque had cleared re-opens on its own.
Future<void> bounceCheque(String id) async {
  await db.transaction((tx) async {
    final rows = await tx.query('cheques', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) throw Exception('Cheque not found');
    final ch = Cheque.fromRow(rows.first);
    if (ch.isBounced) throw Exception('This cheque is already marked returned');

    // Cheques taken before this app credited the account are the one kind with
    // nothing to reverse; anything else gets its credit pulled back.
    if (ch.ledgerId != null) {
      final already = await tx.query('ledger',
          where: "type = 'payment_cancelled' AND ref_id = ?", whereArgs: [ch.ledgerId]);
      if (already.isEmpty) {
        await tx.insert('ledger', {
          'id': uid(),
          'customer_id': ch.customerId,
          'type': 'payment_cancelled',
          'amount': ch.amount, // the credit was negative, so this puts it back
          'ref_id': ch.ledgerId,
          'note': 'Cheque ${ch.chequeNo} returned unpaid',
          'created_at': _now(),
        });
      }
    }
    await tx.update('cheques', {'status': 'bounced', 'settled_at': _now()},
        where: 'id = ?', whereArgs: [id]);
  });
}

/// Waiting cheques first, the nearest banking date at the top — that is the
/// order the seller works in. Dates filter on when the cheque was taken in, so
/// the same date filters as the rest of History keep working on future-dated
/// cheques.
Future<List<Cheque>> cheques({
  String? customerId,
  String? status,
  String q = '',
  DateTime? from,
  DateTime? to,
}) async {
  final w = <String>[], a = <Object?>[];
  if (customerId != null) {
    w.add('h.customer_id = ?');
    a.add(customerId);
  }
  if (status != null) {
    w.add('h.status = ?');
    a.add(status);
  }
  if (q.trim().isNotEmpty) {
    w.add('(c.name LIKE ? OR c.phone LIKE ? OR h.cheque_no LIKE ? OR h.bank LIKE ?)');
    a.addAll([_like(q), _like(q), _like(q), _like(q)]);
  }
  if (from != null) {
    w.add('h.created_at >= ?');
    a.add(from.millisecondsSinceEpoch);
  }
  if (to != null) {
    w.add('h.created_at <= ?');
    a.add(to.millisecondsSinceEpoch);
  }
  return (await db.rawQuery('''
      SELECT h.*, c.name customer_name, c.phone customer_phone
      FROM cheques h JOIN customers c ON c.id = h.customer_id
      ${w.isEmpty ? '' : 'WHERE ${w.join(' AND ')}'}
      ORDER BY h.status = 'pending' DESC, h.due_at, h.created_at DESC''', a))
      .map(Cheque.fromRow)
      .toList();
}

Future<Cheque?> oneCheque(String id) async {
  final r = await db.rawQuery('''
      SELECT h.*, c.name customer_name, c.phone customer_phone
      FROM cheques h JOIN customers c ON c.id = h.customer_id
      WHERE h.id = ?''', [id]);
  return r.isEmpty ? null : Cheque.fromRow(r.first);
}

// ============================================================ sales & quotes

/// A customer runs one account, not one account per bill. Money coming in
/// clears the oldest unpaid sale first, so a sale counts as settled once the
/// credits on the account reach it.
///
/// Derived rather than stored, which is what makes a later payment finish off
/// an earlier part-paid sale — and makes an advance paid before the sale was
/// even written settle it too, with no special case for either.
///
/// Credits are payments and returns, netted against undone payments: a reversal
/// is positive, so it cancels its payment inside the same sum and the bill it
/// had cleared goes back to unpaid on its own. A hand-written adjustment that
/// lets the customer off counts as a credit for the same reason.
///
/// Debts owed before this bill queue in front of it: earlier sales, and any
/// balance carried in or added by hand up to that point. Without that, money
/// paid against an opening balance would quietly tick off a sale it never
/// touched.
const _settled = '''
    CASE WHEN d.kind = 'sale' AND d.status <> 'cancelled' THEN
      MAX(0, MIN(d.total,
        IFNULL((SELECT -SUM(l.amount) FROM ledger l
                 WHERE l.customer_id = d.customer_id
                   AND (l.type IN ('payment', 'return', 'payment_cancelled')
                        OR (l.type IN ('opening', 'adjustment') AND l.amount < 0))), 0)
        - IFNULL((SELECT SUM(e.total) FROM docs e
                   WHERE e.customer_id = d.customer_id AND e.kind = 'sale'
                     AND e.status <> 'cancelled'
                     AND (e.created_at < d.created_at
                          OR (e.created_at = d.created_at AND e.rowid < d.rowid))), 0)
        - IFNULL((SELECT SUM(l.amount) FROM ledger l
                   WHERE l.customer_id = d.customer_id AND l.amount > 0
                     AND l.type IN ('opening', 'adjustment')
                     AND l.created_at <= d.created_at), 0)))
    ELSE 0 END settled''';

Future<List<Doc>> docs({
  String? customerId,
  String? kind,
  String q = '',
  DateTime? from,
  DateTime? to,
  // High enough that a shop writing 20 bills a day will not reach it for years.
  // It is a guard against runaway memory, not a page size.
  int limit = 20000,
}) async {
  final w = <String>[], a = <Object?>[];
  if (customerId != null) {
    w.add('d.customer_id = ?');
    a.add(customerId);
  }
  if (kind != null) {
    w.add('d.kind = ?');
    a.add(kind);
  }
  if (q.trim().isNotEmpty) {
    // Matches a customer name, a phone number, or a typed document number.
    w.add('(c.name LIKE ? OR c.phone LIKE ? OR d.no = ?)');
    a..addAll([_like(q), _like(q)])..add(int.tryParse(q.trim().replaceAll('#', '')) ?? -1);
  }
  if (from != null) {
    w.add('d.created_at >= ?');
    a.add(from.millisecondsSinceEpoch);
  }
  if (to != null) {
    w.add('d.created_at <= ?');
    a.add(to.millisecondsSinceEpoch);
  }
  return (await db.rawQuery('''
      SELECT d.*, c.name customer_name, c.phone customer_phone, $_settled
      FROM docs d JOIN customers c ON c.id = d.customer_id
      ${w.isEmpty ? '' : 'WHERE ${w.join(' AND ')}'}
      ORDER BY d.created_at DESC LIMIT $limit''', a))
      .map(Doc.fromRow)
      .toList();
}

Future<Doc?> doc(String id) async {
  final r = await db.rawQuery('''
      SELECT d.*, c.name customer_name, c.phone customer_phone, $_settled
      FROM docs d JOIN customers c ON c.id = d.customer_id WHERE d.id = ?''', [id]);
  return r.isEmpty ? null : Doc.fromRow(r.first);
}

Future<List<DocItem>> docItems(String docId) async =>
    (await db.query('doc_items', where: 'doc_id = ?', whereArgs: [docId]))
        .map(DocItem.fromRow)
        .toList();

/// Creates a sale (`quote: false`) or a quotation (`quote: true`).
///
/// A quotation records intent only: no stock movement, no ledger entry.
/// A sale deducts each line from its own batch and writes the ledger entries,
/// all inside one transaction so stock and balance can never drift apart.
Future<String> saveDoc({
  required String customerId,
  required bool quote,
  required List<SellLine> lines,
  int paid = 0,
  String? fromQuote,
  String note = '',
}) async {
  if (lines.isEmpty) throw Exception('Add at least one item');
  for (final l in lines) {
    if (l.qty <= 0) throw Exception('Quantity must be more than zero');
    if (l.price < 0) throw Exception('Prices cannot be negative');
  }
  final total = lines.fold<int>(0, (s, l) => s + l.total);
  if (paid < 0) throw Exception('Payment cannot be negative');

  final id = uid();
  await db.transaction((tx) async {
    final now = _now();

    // Claim the quotation first: if another conversion already happened this
    // updates nothing and the whole transaction rolls back.
    if (fromQuote != null) {
      final claimed = await tx.rawUpdate(
          "UPDATE docs SET status = 'completed' WHERE id = ? AND kind = 'quote' AND status = 'pending'",
          [fromQuote]);
      if (claimed != 1) {
        throw Exception('This quotation was already converted or cancelled');
      }
    }

    await tx.insert('docs', {
      'id': id,
      'no': await _nextNo(tx, 'docs', "kind = '${quote ? 'quote' : 'sale'}'"),
      'kind': quote ? 'quote' : 'sale',
      'status': quote ? 'pending' : 'active',
      'customer_id': customerId,
      'total': total,
      'paid': quote ? 0 : paid,
      'from_quote': fromQuote,
      'note': note,
      'created_at': now,
    });

    for (final l in lines) {
      final b = await tx.query('batches',
          columns: ['cost', 'price'], where: 'id = ?', whereArgs: [l.batchId]);
      if (b.isEmpty) throw Exception('Batch not found');
      final cost = (b.first['cost'] as num).toInt();

      // Giving a regular a better price is the seller's call; going under what
      // the stock cost is not, because it reads as a sale and books as a loss.
      // A conversion is exempt: those prices were agreed when the quote was
      // written, and a later cost correction must not strand it at the counter.
      if (fromQuote == null && l.price < cost) {
        throw Exception('Price is below cost: ${l.name}');
      }

      await tx.insert('doc_items', {
        'id': uid(),
        'doc_id': id,
        'product_id': l.productId,
        'batch_id': l.batchId,
        'name': l.name,
        'qty': l.qty,
        'price': l.price,
        'list_price':
            l.listPrice > 0 ? l.listPrice : (b.first['price'] as num).toInt(),
      });

      if (!quote) {
        // The `qty_left >= ?` guard is what makes stock impossible to go negative.
        final ok = await tx.rawUpdate(
            'UPDATE batches SET qty_left = qty_left - ? WHERE id = ? AND qty_left >= ?',
            [l.qty, l.batchId, l.qty]);
        if (ok != 1) throw Exception('Not enough stock: ${l.name}');
      }
    }

    if (!quote) {
      await tx.insert('ledger', {
        'id': uid(),
        'customer_id': customerId,
        'type': 'sale',
        'amount': total,
        'ref_id': id,
        'note': '',
        'created_at': now,
      });
      if (paid > 0) {
        await tx.insert('ledger', {
          'id': uid(),
          'no': await _nextNo(tx, 'ledger', "type = 'payment'"),
          'customer_id': customerId,
          'type': 'payment',
          'amount': -paid,
          'ref_id': id,
          'note': '',
          'created_at': now,
        });
      }
    }
  });
  return id;
}

/// Turns a pending quotation into a real sale. Stock is checked and deducted
/// exactly once — a second attempt fails on the status guard inside [saveDoc].
Future<String> convertQuote(String quoteId, {int paid = 0}) async {
  final q = await doc(quoteId);
  if (q == null || !q.isQuote) throw Exception('Quotation not found');
  if (q.status != 'pending') {
    throw Exception('This quotation was already converted or cancelled');
  }
  final items = await docItems(quoteId);
  return saveDoc(
    customerId: q.customerId,
    quote: false,
    paid: paid,
    fromQuote: quoteId,
    lines: items
        .map((i) => SellLine(
            productId: i.productId,
            batchId: i.batchId,
            name: i.name,
            price: i.price,
            // Carried across so the bill shows the discount that was quoted,
            // not one re-derived from today's shelf price.
            listPrice: i.listPrice,
            qty: i.qty))
        .toList(),
  );
}

/// Cancels a sale or quotation.
///
/// For a sale: unsold stock goes back to its batch and the debit is reversed.
/// Money already received stays on the ledger as customer credit — it was
/// really received, so it shows up as an advance rather than vanishing.
Future<void> cancelDoc(String docId) async {
  final d = await doc(docId);
  if (d == null) throw Exception('Not found');
  if (d.isCancelled) throw Exception('Already cancelled');

  await db.transaction((tx) async {
    if (d.isQuote) {
      final ok = await tx.rawUpdate(
          "UPDATE docs SET status = 'cancelled' WHERE id = ? AND status = 'pending'", [docId]);
      if (ok != 1) throw Exception('This quotation was already converted or cancelled');
      return;
    }

    final ok = await tx.rawUpdate(
        "UPDATE docs SET status = 'cancelled' WHERE id = ? AND status = 'active'", [docId]);
    if (ok != 1) throw Exception('Already cancelled');

    for (final i in (await tx.query('doc_items', where: 'doc_id = ?', whereArgs: [docId]))
        .map(DocItem.fromRow)) {
      if (i.returnable == 0) continue; // already given back by a return
      await tx.rawUpdate(
          'UPDATE batches SET qty_left = qty_left + ? WHERE id = ?', [i.returnable, i.batchId]);
    }

    await tx.insert('ledger', {
      'id': uid(),
      'customer_id': d.customerId,
      'type': 'sale_cancelled',
      'amount': -d.total,
      'ref_id': docId,
      'note': 'Sale #${d.no} cancelled',
      'created_at': _now(),
    });
  });
}

// ============================================================ returns

/// Takes items back from a completed sale: stock returns to the exact batch it
/// came from and the customer is credited at the price they were charged.
Future<String> saveReturn(String docId, Map<String, int> qtyByItemId) async {
  final d = await doc(docId);
  if (d == null || d.isQuote) throw Exception('Sale not found');
  if (d.isCancelled) throw Exception('This sale is cancelled');

  final items = {for (final i in await docItems(docId)) i.id: i};
  final wanted = <String, int>{};
  qtyByItemId.forEach((k, v) {
    if (v > 0) wanted[k] = v;
  });
  if (wanted.isEmpty) throw Exception('Choose at least one item to return');

  for (final e in wanted.entries) {
    final i = items[e.key];
    if (i == null) throw Exception('Item not in this sale');
    if (e.value > i.returnable) {
      throw Exception('Can be returned at most: ${i.returnable} ${i.name}');
    }
  }

  final total = wanted.entries.fold(0, (s, e) => s + items[e.key]!.price * e.value);
  final id = uid();

  await db.transaction((tx) async {
    final now = _now();
    await tx.insert('returns', {
      'id': id,
      'no': await _nextNo(tx, 'returns'),
      'doc_id': docId,
      'customer_id': d.customerId,
      'total': total,
      'created_at': now,
    });

    for (final e in wanted.entries) {
      final i = items[e.key]!;
      final ok = await tx.rawUpdate(
          'UPDATE doc_items SET returned = returned + ? WHERE id = ? AND returned + ? <= qty',
          [e.value, i.id, e.value]);
      if (ok != 1) throw Exception('Return quantity is too high: ${i.name}');

      await tx.rawUpdate(
          'UPDATE batches SET qty_left = qty_left + ? WHERE id = ?', [e.value, i.batchId]);

      await tx.insert('return_items', {
        'id': uid(),
        'return_id': id,
        'item_id': i.id,
        'batch_id': i.batchId,
        'name': i.name,
        'qty': e.value,
        'price': i.price,
      });
    }

    await tx.insert('ledger', {
      'id': uid(),
      'customer_id': d.customerId,
      'type': 'return',
      'amount': -total,
      'ref_id': id,
      'note': 'Return from sale #${d.no}',
      'created_at': now,
    });
  });
  return id;
}

Future<List<SqlRow>> returns(
    {String? customerId, String q = '', DateTime? from, DateTime? to}) {
  final w = <String>[], a = <Object?>[];
  if (from != null) {
    w.add('r.created_at >= ?');
    a.add(from.millisecondsSinceEpoch);
  }
  if (to != null) {
    w.add('r.created_at <= ?');
    a.add(to.millisecondsSinceEpoch);
  }
  if (customerId != null) {
    w.add('r.customer_id = ?');
    a.add(customerId);
  }
  if (q.trim().isNotEmpty) {
    w.add('(c.name LIKE ? OR c.phone LIKE ? OR r.no = ?)');
    a..addAll([_like(q), _like(q)])..add(int.tryParse(q.trim().replaceAll('#', '')) ?? -1);
  }
  return db.rawQuery('''
      SELECT r.*, c.name customer_name, c.phone customer_phone, d.no sale_no
      FROM returns r JOIN customers c ON c.id = r.customer_id
      JOIN docs d ON d.id = r.doc_id
      ${w.isEmpty ? '' : 'WHERE ${w.join(' AND ')}'}
      ORDER BY r.created_at DESC''', a);
}

/// One return with everything a return note has to print.
Future<(SqlRow, List<SqlRow>)?> oneReturn(String id) async {
  final r = await db.rawQuery('''
      SELECT r.*, c.name customer_name, c.phone customer_phone, d.no sale_no
      FROM returns r JOIN customers c ON c.id = r.customer_id
      JOIN docs d ON d.id = r.doc_id WHERE r.id = ?''', [id]);
  if (r.isEmpty) return null;
  return (r.first, await returnItems(id));
}

Future<List<SqlRow>> returnItems(String id) =>
    db.query('return_items', where: 'return_id = ?', whereArgs: [id]);

// ============================================================ settings

/// Kept in memory because receipts and the app bar read them constantly.
final settings = <String, String>{};

String get businessName => settings['business_name'] ?? '';
String get businessPhone => settings['business_phone'] ?? '';

/// The shop's logo, printed at the top of every receipt. Kept base64 in
/// `settings` so it rides along in the backup like everything else, and decoded
/// once — receipts ask for it on every render.
String? _logoText;
Uint8List? _logoBytes;

Uint8List? get businessLogo {
  final raw = settings['business_logo'];
  if (raw == null || raw.isEmpty) return null;
  if (raw != _logoText) {
    _logoText = raw;
    try {
      _logoBytes = base64Decode(raw);
    } catch (_) {
      _logoBytes = null; // a damaged logo must not stop a receipt printing
    }
  }
  return _logoBytes;
}

Future<void> setBusinessLogo(Uint8List? bytes) =>
    setSetting('business_logo', bytes == null ? '' : base64Encode(bytes));

/// Photo cards by default — a picture is the fastest way to spot a product.
bool get productsAsCards => (settings['product_view'] ?? 'cards') == 'cards';

Future<void> loadSettings() async {
  settings
    ..clear()
    ..addEntries((await db.query('settings'))
        .map((r) => MapEntry(r['key'] as String, r['value'] as String)));
}

Future<void> setSetting(String key, String value) async {
  await db.insert('settings', {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace);
  settings[key] = value;
}

// ============================================================ home stats

/// Customers who owe money, biggest first — the home screen's main list.
Future<List<Customer>> debtors({int limit = 5}) async => (await db.rawQuery('''
      SELECT c.*, SUM(l.amount) balance
      FROM customers c JOIN ledger l ON l.customer_id = c.id
      GROUP BY c.id HAVING balance > 0
      ORDER BY balance DESC LIMIT ?''', [limit]))
    .map(Customer.fromRow)
    .toList();

Future<({int products, int stock, int customers, int owed, int cheques, int sales})>
    stats() async {
  final p = await db.rawQuery(
      'SELECT (SELECT COUNT(*) FROM products) p, (SELECT IFNULL(SUM(qty_left),0) FROM batches) s, (SELECT COUNT(*) FROM customers) c,'
      " (SELECT IFNULL(SUM(amount),0) FROM cheques WHERE status = 'pending') h,"
      " (SELECT COUNT(*) FROM docs WHERE kind = 'sale' AND status <> 'cancelled') d");
  final owed = await db.rawQuery('''
      SELECT IFNULL(SUM(b),0) o FROM
        (SELECT SUM(amount) b FROM ledger GROUP BY customer_id) WHERE b > 0''');
  final r = p.first;
  return (
    products: (r['p'] as num).toInt(),
    stock: (r['s'] as num).toInt(),
    customers: (r['c'] as num).toInt(),
    owed: (owed.first['o'] as num).toInt(),
    cheques: (r['h'] as num).toInt(),
    sales: (r['d'] as num).toInt(),
  );
}
