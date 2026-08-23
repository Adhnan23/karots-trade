import 'dart:typed_data';

typedef SqlRow = Map<String, Object?>;

int _i(Object? v) => (v as num?)?.toInt() ?? 0;
String _s(Object? v) => (v as String?) ?? '';

class Product {
  final String id, name;
  final Uint8List? image;
  final int stock; // total remaining across batches
  final int createdAt, updatedAt;

  Product.fromRow(SqlRow r)
      : id = _s(r['id']),
        name = _s(r['name']),
        image = r['image'] as Uint8List?,
        stock = _i(r['stock']),
        createdAt = _i(r['created_at']),
        updatedAt = _i(r['updated_at']);
}

class Batch {
  final String id, productId, productName;
  final int cost, price, qtyIn, qtyLeft, createdAt;

  Batch.fromRow(SqlRow r)
      : id = _s(r['id']),
        productId = _s(r['product_id']),
        productName = _s(r['name']),
        cost = _i(r['cost']),
        price = _i(r['price']),
        qtyIn = _i(r['qty_in']),
        qtyLeft = _i(r['qty_left']),
        createdAt = _i(r['created_at']);
}

class Customer {
  final String id, name, phone;
  final int balance; // + owes you, - has advance
  final int createdAt;

  Customer.fromRow(SqlRow r)
      : id = _s(r['id']),
        name = _s(r['name']),
        phone = _s(r['phone']),
        balance = _i(r['balance']),
        createdAt = _i(r['created_at']);
}

/// A sale or a quotation. Same shape, different `kind`.
class Doc {
  final String id, kind, status, customerId, customerName, customerPhone, note;
  final String? fromQuote;
  final int no, total, paid, advanceUsed, createdAt;

  bool get isQuote => kind == 'quote';
  bool get isCancelled => status == 'cancelled';
  bool get isConverted => status == 'completed';

  /// Money the customer already had on account when this sale was made counts
  /// as settled — otherwise a sale covered by an advance reads as "Not paid".
  int get settled => paid + advanceUsed;
  int get due => total - settled;

  Doc.fromRow(SqlRow r)
      : id = _s(r['id']),
        kind = _s(r['kind']),
        status = _s(r['status']),
        customerId = _s(r['customer_id']),
        customerName = _s(r['customer_name']),
        customerPhone = _s(r['customer_phone']),
        note = _s(r['note']),
        fromQuote = r['from_quote'] as String?,
        no = _i(r['no']),
        total = _i(r['total']),
        paid = _i(r['paid']),
        advanceUsed = _i(r['advance_used']),
        createdAt = _i(r['created_at']);
}

class DocItem {
  final String id, productId, batchId, name;
  final int qty, price, returned;

  int get total => qty * price;
  int get returnable => qty - returned;

  DocItem.fromRow(SqlRow r)
      : id = _s(r['id']),
        productId = _s(r['product_id']),
        batchId = _s(r['batch_id']),
        name = _s(r['name']),
        qty = _i(r['qty']),
        price = _i(r['price']),
        returned = _i(r['returned']);
}

class LedgerEntry {
  final String id, type, note;
  final String? refId;
  final int no, amount, createdAt;

  /// Running customer balance immediately after this entry, for receipts.
  final int balanceAfter;

  bool get isPayment => type == 'payment';

  LedgerEntry.fromRow(SqlRow r)
      : id = _s(r['id']),
        no = _i(r['no']),
        balanceAfter = _i(r['balance_after']),
        type = _s(r['type']),
        note = _s(r['note']),
        refId = r['ref_id'] as String?,
        amount = _i(r['amount']),
        createdAt = _i(r['created_at']);
}

/// One line being entered on the Buy screen.
class BuyLine {
  String? productId;
  String name;
  Uint8List? image;
  int cost, price, qty;
  BuyLine({this.productId, this.name = '', this.image, this.cost = 0, this.price = 0, this.qty = 1});
  int get total => cost * qty;
}

/// One line being entered on the Sell / Quote screen.
class SellLine {
  final String productId, batchId, name;
  final int price;
  int qty;
  SellLine({
    required this.productId,
    required this.batchId,
    required this.name,
    required this.price,
    this.qty = 1,
  });
  int get total => price * qty;
}
