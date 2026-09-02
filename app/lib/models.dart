import 'dart:typed_data';

typedef SqlRow = Map<String, Object?>;

/// How long a customer has to settle a bill taken on credit. Printed on the
/// receipt as a real date, because "within a week" starts an argument and
/// "by 3 Sep 2026" does not. It lives here rather than with the widgets
/// because it is a term of trade, and the store has to reason about it too.
const creditDays = 7;

DateTime payBy(int soldAt) =>
    DateTime.fromMillisecondsSinceEpoch(soldAt).add(const Duration(days: creditDays));

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
  final int no, total, createdAt;

  /// Cash taken at the counter when the sale was written. Kept as a record of
  /// that moment; it is [settled] that says whether the bill is clear.
  final int paid;

  /// How much of this sale the customer's account has covered, counting every
  /// payment before and since. Derived by the store, never stored.
  final int settled;

  /// When the sale was last corrected, or null if it never was. A sale that
  /// was put right is still the same sale, so it keeps its number.
  final int? editedAt;

  bool get isQuote => kind == 'quote';
  bool get isCancelled => status == 'cancelled';
  bool get isConverted => status == 'completed';
  int get due => total - settled;

  /// True when money that arrived after the sale finished paying it off.
  bool get settledLater => settled > paid;

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
        settled = _i(r['settled']),
        editedAt = (r['edited_at'] as num?)?.toInt(),
        createdAt = _i(r['created_at']);
}

class DocItem {
  final String id, productId, batchId, name;
  final int qty, price, returned;

  /// The normal price before the seller knocked anything off. 0 on lines
  /// written before discounts existed, which simply reads as "no discount".
  final int listPrice;

  int get total => qty * price;
  int get returnable => qty - returned;

  /// What the customer was let off on this line, in total.
  int get discount => listPrice > price ? (listPrice - price) * qty : 0;

  DocItem.fromRow(SqlRow r)
      : id = _s(r['id']),
        productId = _s(r['product_id']),
        batchId = _s(r['batch_id']),
        name = _s(r['name']),
        qty = _i(r['qty']),
        price = _i(r['price']),
        listPrice = _i(r['list_price']),
        returned = _i(r['returned']);
}

/// A cheque handed over as payment. It credits the account straight away; the
/// status here says whether the bank has since confirmed it or sent it back.
class Cheque {
  final String id, customerId, customerName, customerPhone;
  final String chequeNo, bank, status, note;
  final String? ledgerId;
  final int no, amount, dueAt, createdAt;
  final int? settledAt;

  bool get isPending => status == 'pending';
  bool get isCleared => status == 'cleared';
  bool get isBounced => status == 'bounced';

  /// The date on the cheque has arrived, so it can be taken to the bank.
  bool get isDue => isPending && dueAt <= DateTime.now().millisecondsSinceEpoch;

  /// Days until it can be banked, never negative. 0 means today or overdue,
  /// which is what a statement prints as "ready to bank".
  int get daysLeft {
    final ms = dueAt - DateTime.now().millisecondsSinceEpoch;
    return ms <= 0 ? 0 : (ms / Duration.millisecondsPerDay).ceil();
  }

  Cheque.fromRow(SqlRow r)
      : id = _s(r['id']),
        customerId = _s(r['customer_id']),
        customerName = _s(r['customer_name']),
        customerPhone = _s(r['customer_phone']),
        chequeNo = _s(r['cheque_no']),
        bank = _s(r['bank']),
        status = _s(r['status']),
        note = _s(r['note']),
        ledgerId = r['ledger_id'] as String?,
        no = _i(r['no']),
        amount = _i(r['amount']),
        dueAt = _i(r['due_at']),
        createdAt = _i(r['created_at']),
        settledAt = (r['settled_at'] as num?)?.toInt();
}

/// How the money came in. Empty for a sale, and for payments taken before the
/// app started asking — those simply read as "Payment received".
String methodLabel(String method) => switch (method) {
      'cash' => 'Cash in hand',
      'bank' => 'Bank transfer',
      'cheque' => 'Cheque',
      _ => '',
    };

class LedgerEntry {
  final String id, customerId, type, note;

  /// cash | bank | cheque, or empty. See [methodLabel].
  final String method;
  final String? refId;
  final int no, amount, createdAt;

  /// Running customer balance immediately after this entry, for receipts.
  final int balanceAfter;

  bool get isPayment => type == 'payment';

  LedgerEntry.fromRow(SqlRow r)
      : id = _s(r['id']),
        customerId = _s(r['customer_id']),
        no = _i(r['no']),
        balanceAfter = _i(r['balance_after']),
        type = _s(r['type']),
        note = _s(r['note']),
        method = _s(r['method']),
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

  /// What this customer is being charged, which may be less than the batch's
  /// usual price.
  final int price;

  /// The usual price, kept so the receipt can show the discount. 0 means take
  /// whatever the batch says.
  final int listPrice;

  int qty;
  SellLine({
    required this.productId,
    required this.batchId,
    required this.name,
    required this.price,
    this.listPrice = 0,
    this.qty = 1,
  });
  int get total => price * qty;
}
