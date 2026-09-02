import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Database? _db;
Database get db => _db!;

/// Android/iOS use the bundled SQLite; desktop (and tests) use the FFI build.
/// Same schema, same SQL, same business logic everywhere — no second adapter.
Future<Database> openDb({String? path}) async {
  if (!Platform.isAndroid && !Platform.isIOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  final file = path ??
      p.join((await getApplicationDocumentsDirectory()).path, 'karots_trade.db');
  _db = await databaseFactory.openDatabase(
    file,
    options: OpenDatabaseOptions(
      version: 7,
      onConfigure: (d) => d.execute('PRAGMA foreign_keys = ON'),
      onCreate: (d, _) async {
        for (final s in schema) {
          await d.execute(s);
        }
      },
      onUpgrade: (d, from, to) async {
        for (var v = from + 1; v <= to; v++) {
          for (final s in migrations[v] ?? const <String>[]) {
            await d.execute(s);
          }
        }
      },
    ),
  );
  return _db!;
}

Future<void> closeDb() async {
  await _db?.close();
  _db = null;
}

/// Wipes every row (used by backup import). Order respects foreign keys.
Future<void> wipe(DatabaseExecutor d) async {
  for (final tbl in tables.reversed) {
    await d.delete(tbl);
  }
}

const tables = [
  'products',
  'batches',
  'purchases',
  'purchase_items',
  'customers',
  'docs',
  'doc_items',
  'doc_edits',
  'returns',
  'return_items',
  'ledger',
  'adjustments',
  // After ledger and customers: a restore inserts in this order, and the
  // wipe before it deletes in reverse, so the references always hold.
  'cheques',
  'settings',
];

/// `docs` holds both sales and quotations — identical shape, one `kind` column.
/// A quotation never touches stock or the ledger; converting it creates a
/// second `docs` row of kind 'sale' that points back via `from_quote`.
const schema = [
  '''CREATE TABLE products(
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      image BLOB,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL)''',
  '''CREATE TABLE batches(
      id TEXT PRIMARY KEY,
      product_id TEXT NOT NULL REFERENCES products(id) ON DELETE CASCADE,
      cost INTEGER NOT NULL,
      price INTEGER NOT NULL,
      qty_in INTEGER NOT NULL,
      qty_left INTEGER NOT NULL,
      purchase_id TEXT,
      created_at INTEGER NOT NULL)''',
  'CREATE INDEX ix_batch_product ON batches(product_id)',
  '''CREATE TABLE purchases(
      id TEXT PRIMARY KEY,
      no INTEGER NOT NULL,
      total INTEGER NOT NULL,
      created_at INTEGER NOT NULL)''',
  '''CREATE TABLE purchase_items(
      id TEXT PRIMARY KEY,
      purchase_id TEXT NOT NULL REFERENCES purchases(id) ON DELETE CASCADE,
      product_id TEXT NOT NULL,
      batch_id TEXT NOT NULL,
      name TEXT NOT NULL,
      cost INTEGER NOT NULL,
      price INTEGER NOT NULL,
      qty INTEGER NOT NULL)''',
  '''CREATE TABLE customers(
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      phone TEXT NOT NULL DEFAULT '',
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL)''',
  '''CREATE TABLE docs(
      id TEXT PRIMARY KEY,
      no INTEGER NOT NULL,
      kind TEXT NOT NULL,               -- sale | quote
      status TEXT NOT NULL,             -- active | cancelled | pending | completed
      customer_id TEXT NOT NULL REFERENCES customers(id),
      total INTEGER NOT NULL,
      paid INTEGER NOT NULL DEFAULT 0,
      advance_used INTEGER NOT NULL DEFAULT 0,
      from_quote TEXT,
      note TEXT NOT NULL DEFAULT '',
      created_at INTEGER NOT NULL,
      -- Set when a sale was corrected after it was written, so the bill can
      -- say so. Null on every sale that was right the first time.
      edited_at INTEGER)''',
  'CREATE INDEX ix_docs_customer ON docs(customer_id)',
  '''CREATE TABLE doc_items(
      id TEXT PRIMARY KEY,
      doc_id TEXT NOT NULL REFERENCES docs(id) ON DELETE CASCADE,
      product_id TEXT NOT NULL,
      batch_id TEXT NOT NULL,
      name TEXT NOT NULL,               -- captured at sale time
      qty INTEGER NOT NULL,
      price INTEGER NOT NULL,           -- what was actually charged
      -- The normal price before any discount, so a receipt can show what the
      -- customer was let off. 0 on rows written before discounts existed.
      list_price INTEGER NOT NULL DEFAULT 0,
      returned INTEGER NOT NULL DEFAULT 0)''',
  'CREATE INDEX ix_items_doc ON doc_items(doc_id)',
  ..._docEdits,
  '''CREATE TABLE returns(
      id TEXT PRIMARY KEY,
      no INTEGER NOT NULL,
      doc_id TEXT NOT NULL REFERENCES docs(id),
      customer_id TEXT NOT NULL REFERENCES customers(id),
      total INTEGER NOT NULL,
      created_at INTEGER NOT NULL)''',
  '''CREATE TABLE return_items(
      id TEXT PRIMARY KEY,
      return_id TEXT NOT NULL REFERENCES returns(id) ON DELETE CASCADE,
      item_id TEXT NOT NULL,
      batch_id TEXT NOT NULL,
      name TEXT NOT NULL,
      qty INTEGER NOT NULL,
      price INTEGER NOT NULL)''',
  // Ledger sign: + customer owes more, - customer owes less.
  // Balance is always SUM(amount); no editable balance column exists.
  '''CREATE TABLE ledger(
      id TEXT PRIMARY KEY,
      no INTEGER NOT NULL DEFAULT 0,    -- receipt number, payments only
      customer_id TEXT NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
      type TEXT NOT NULL,               -- sale | payment | return | sale_cancelled
      amount INTEGER NOT NULL,
      ref_id TEXT,
      note TEXT NOT NULL DEFAULT '',
      -- How the money came in: cash | bank | cheque. Empty on a sale, and on
      -- payments taken before the app asked. Kept apart from `note`, which is
      -- whatever the seller typed.
      method TEXT NOT NULL DEFAULT '',
      created_at INTEGER NOT NULL)''',
  'CREATE INDEX ix_ledger_customer ON ledger(customer_id)',
  // A correction to a batch that was entered wrong, kept so the change is
  // never silent — stock that moves without a record is how books go bad.
  '''CREATE TABLE adjustments(
      id TEXT PRIMARY KEY,
      no INTEGER NOT NULL,
      product_id TEXT NOT NULL,
      batch_id TEXT NOT NULL,
      name TEXT NOT NULL,
      qty_before INTEGER NOT NULL,
      qty_after INTEGER NOT NULL,
      cost_before INTEGER NOT NULL,
      cost_after INTEGER NOT NULL,
      price_before INTEGER NOT NULL,
      price_after INTEGER NOT NULL,
      reason TEXT NOT NULL DEFAULT '',
      created_at INTEGER NOT NULL)''',
  'CREATE INDEX ix_adj_product ON adjustments(product_id)',
  ..._cheques,
  'CREATE TABLE settings(key TEXT PRIMARY KEY, value TEXT NOT NULL)',
];

/// What a bill said before it was corrected. Editing a sale rewrites its lines,
/// and a customer holding the earlier printout deserves an answer better than
/// "it must have been wrong" — so the old version is kept as it stood.
const _docEdits = [
  '''CREATE TABLE doc_edits(
      id TEXT PRIMARY KEY,
      doc_id TEXT NOT NULL REFERENCES docs(id) ON DELETE CASCADE,
      total_before INTEGER NOT NULL,
      paid_before INTEGER NOT NULL,
      lines TEXT NOT NULL,              -- the old lines, as JSON
      created_at INTEGER NOT NULL)''',
  'CREATE INDEX ix_edits_doc ON doc_edits(doc_id)',
];

/// A cheque credits the account the moment it is handed over — that is what
/// the counter actually expects — and `ledger_id` is the payment row it wrote.
/// Coming back unpaid is the unusual case, and it writes a reversal.
const _cheques = [
  '''CREATE TABLE cheques(
      id TEXT PRIMARY KEY,
      no INTEGER NOT NULL,
      customer_id TEXT NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
      cheque_no TEXT NOT NULL,          -- the number printed on the cheque
      bank TEXT NOT NULL DEFAULT '',
      amount INTEGER NOT NULL,
      due_at INTEGER NOT NULL,          -- the date written on it: bank it then
      status TEXT NOT NULL,             -- pending | cleared | bounced
      ledger_id TEXT,                   -- the payment row, only once cleared
      note TEXT NOT NULL DEFAULT '',
      created_at INTEGER NOT NULL,
      settled_at INTEGER)''',
  'CREATE INDEX ix_cheque_customer ON cheques(customer_id)',
];

/// Applied in order when an existing database is opened at an older version.
const migrations = <int, List<String>>{
  2: [
    'ALTER TABLE docs ADD COLUMN advance_used INTEGER NOT NULL DEFAULT 0',
    'ALTER TABLE ledger ADD COLUMN no INTEGER NOT NULL DEFAULT 0',
  ],
  3: [
    '''CREATE TABLE adjustments(
        id TEXT PRIMARY KEY,
        no INTEGER NOT NULL,
        product_id TEXT NOT NULL,
        batch_id TEXT NOT NULL,
        name TEXT NOT NULL,
        qty_before INTEGER NOT NULL,
        qty_after INTEGER NOT NULL,
        cost_before INTEGER NOT NULL,
        cost_after INTEGER NOT NULL,
        price_before INTEGER NOT NULL,
        price_after INTEGER NOT NULL,
        reason TEXT NOT NULL DEFAULT '',
        created_at INTEGER NOT NULL)''',
    'CREATE INDEX ix_adj_product ON adjustments(product_id)',
  ],
  4: [
    ..._cheques,
    'ALTER TABLE doc_items ADD COLUMN list_price INTEGER NOT NULL DEFAULT 0',
  ],
  // A cheque now comes off the balance as soon as it is taken in, so every
  // cheque still waiting needs the payment row it would have written today.
  // Additive: it inserts rows, and touches nothing that was already there.
  5: [
    '''INSERT INTO ledger(id, no, customer_id, type, amount, ref_id, note, created_at)
       SELECT 'chq' || h.id,
              (SELECT IFNULL(MAX(no),0) FROM ledger WHERE type = 'payment')
                + ROW_NUMBER() OVER (ORDER BY h.created_at, h.rowid),
              h.customer_id, 'payment', -h.amount, h.id,
              'Cheque ' || h.cheque_no, h.created_at
       FROM cheques h WHERE h.status = 'pending' ''',
    "UPDATE cheques SET ledger_id = 'chq' || id WHERE status = 'pending'",
  ],
  // Two new columns, both with a default, so every row already on the phone
  // stays exactly as it is: payments taken before today simply do not say how
  // the money arrived, and no sale claims to have been corrected.
  6: [
    "ALTER TABLE ledger ADD COLUMN method TEXT NOT NULL DEFAULT ''",
    'ALTER TABLE docs ADD COLUMN edited_at INTEGER',
    // Cheques always credited through a payment row; naming the method now
    // lets a statement tell a cheque from cash without reading the note.
    "UPDATE ledger SET method = 'cheque' "
        "WHERE type = 'payment' AND ref_id IN (SELECT id FROM cheques)",
  ],
  // A new table only. Bills corrected before today have no earlier version
  // recorded, which is simply what it is — from here on they do.
  7: _docEdits,
};
