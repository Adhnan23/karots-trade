import 'package:flutter/material.dart';

import '../core.dart';
import '../models.dart';
import '../photo.dart';
import '../store.dart' as s;
import 'buy.dart' show NumField;
import 'customers.dart';
import 'history.dart';
import 'products.dart';

class SellScreen extends StatefulWidget {
  final Customer? customer;
  const SellScreen({this.customer, super.key});
  @override
  State<SellScreen> createState() => _SellScreenState();
}

class _SellScreenState extends State<SellScreen> {
  late Customer? _customer = widget.customer;
  bool _quote = false;
  final _lines = <SellLine>[];
  final _paid = TextEditingController();
  bool _saving = false;

  int get _total => _lines.fold(0, (a, l) => a + l.total);
  int get _paidAmount => parseMoney(_paid.text) ?? 0;

  @override
  void dispose() {
    _paid.dispose();
    super.dispose();
  }

  Future<void> _pickCustomer() async {
    final c = await Navigator.push<Customer>(context,
        MaterialPageRoute(builder: (_) => const CustomersScreen(picking: true)));
    if (c != null) setState(() => _customer = c);
  }

  Future<void> _addItem() async {
    final p = await Navigator.push<Product>(context,
        MaterialPageRoute(builder: (_) => const ProductsScreen(picking: true)));
    if (p == null || !mounted) return;

    // A quotation may be written for stock not bought yet, so it can use any
    // batch; a sale can only draw from batches that still have stock.
    final all = await s.batches(p.id, availableOnly: !_quote);
    if (!mounted) return;
    if (all.isEmpty) {
      toast(context, '${p.name}: ${t('no stock available')}', bad: true);
      return;
    }
    final line = await Navigator.push<SellLine>(
        context,
        MaterialPageRoute(
            builder: (_) => SellLineForm(product: p, batches: all, quote: _quote)));
    if (line != null) setState(() => _lines.add(line));
  }

  Future<void> _save() async {
    if (_customer == null) {
      toast(context, t('Choose a customer first'), bad: true);
      return;
    }
    setState(() => _saving = true);
    final id = await guard(
        context,
        () => s.saveDoc(
              customerId: _customer!.id,
              quote: _quote,
              lines: _lines,
              paid: _quote ? 0 : _paidAmount,
            ));
    if (!mounted) return;
    setState(() => _saving = false);
    if (id == null) return;
    await Navigator.pushReplacement(
        context, MaterialPageRoute(builder: (_) => DocScreen(id)));
  }

  @override
  Widget build(BuildContext context) {
    final due = _total - _paidAmount;
    return Scaffold(
      appBar: AppBar(
          backgroundColor: _quote ? C.quote : C.sell,
          title: Text(t(_quote ? 'Quote' : 'Sell'))),
      // Three-button navigation keeps a bar across the bottom of the screen.
      // Without this, Add item sits half under it and reaching for it presses
      // Home instead.
      body: SafeArea(
          child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: SegmentedButton<bool>(
            style: SegmentedButton.styleFrom(
                textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                selectedBackgroundColor: _quote ? C.quote : C.sell,
                selectedForegroundColor: Colors.white),
            segments: [
              ButtonSegment(
                  value: false, label: Fit(t('Sell')), icon: const Icon(Icons.sell)),
              ButtonSegment(
                  value: true,
                  label: Fit(t('Quote')),
                  icon: const Icon(Icons.description)),
            ],
            selected: {_quote},
            onSelectionChanged: (v) => setState(() => _quote = v.first),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: C.customers,
                child: Text(
                    _customer == null ? '?' : _customer!.name.characters.first.toUpperCase(),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
              title: Text(_customer?.name ?? t('Choose customer'),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              subtitle: _customer == null ? null : Text(_customer!.phone),
              trailing: const Icon(Icons.chevron_right),
              onTap: _pickCustomer,
            ),
          ),
        ),
        Expanded(
          child: _lines.isEmpty
              ? EmptyState(Icons.shopping_cart, 'Nothing here yet',
                  'Add the products you are selling.')
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: _lines.length,
                  itemBuilder: (_, i) {
                    final l = _lines[i];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        contentPadding: const EdgeInsets.fromLTRB(14, 6, 4, 6),
                        title: Text(l.name,
                            style: const TextStyle(
                                fontSize: 17, fontWeight: FontWeight.w600)),
                        subtitle: Text(
                            [
                              '${l.qty} × ${money(l.price)}',
                              if (l.listPrice > l.price)
                                '${t('Was')} ${money(l.listPrice)}',
                            ].join('   •   '),
                            style: const TextStyle(fontSize: 15)),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          Money(l.total),
                          IconButton(
                            icon: const Icon(Icons.close, color: C.owe),
                            onPressed: () => setState(() => _lines.removeAt(i)),
                          ),
                        ]),
                      ),
                    );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
                foregroundColor: _quote ? C.quote : C.sell),
            icon: const Icon(Icons.add),
            label: Text(t('Add item'), style: const TextStyle(fontSize: 18)),
            onPressed: _addItem,
          ),
        ),
      ])),
      bottomNavigationBar: _lines.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                    left: 12,
                    right: 12,
                    bottom: 12 + MediaQuery.viewInsetsOf(context).bottom),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text(t('Total'),
                        style:
                            const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                    Money(_total, size: 24, color: _quote ? C.quote : C.sell),
                  ]),
                  if (!_quote) ...[
                    const SizedBox(height: 10),
                    NumField(_paid, '${t('Paid')} (Rs.)', Icons.payments,
                        onChanged: (_) => setState(() {})),
                    const SizedBox(height: 8),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text(due > 0 ? t('Remaining') : t('Change / advance'),
                          style: const TextStyle(fontSize: 16)),
                      Money(due.abs(), size: 18, color: due > 0 ? C.owe : C.advance),
                    ]),
                  ],
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                        backgroundColor: _quote ? C.quote : C.sell),
                    icon: const Icon(Icons.check),
                    label: Text(t('Save')),
                    onPressed: _saving ? null : _save,
                  ),
                ]),
              ),
            ),
    );
  }
}

/// Batch choice + quantity. Every sale line is tied to one specific batch,
/// so the price the customer pays is always the price of real stock on hand.
class SellLineForm extends StatefulWidget {
  final Product product;
  final List<Batch> batches;

  /// A quotation may be written for stock not on the shelf yet, so it is not
  /// held to what is currently available.
  final bool quote;

  const SellLineForm(
      {required this.product,
      required this.batches,
      this.quote = false,
      super.key});
  @override
  State<SellLineForm> createState() => _SellLineFormState();
}

class _SellLineFormState extends State<SellLineForm> {
  late Batch _batch = widget.batches.first;
  final _qty = TextEditingController(text: '1');
  late final _price = TextEditingController(text: _asText(_batch.price));

  static String _asText(int cents) =>
      cents % 100 == 0 ? '${cents ~/ 100}' : (cents / 100).toStringAsFixed(2);

  @override
  void dispose() {
    _qty.dispose();
    _price.dispose();
    super.dispose();
  }

  int get _q => int.tryParse(_qty.text.trim()) ?? 0;
  int get _p => parseMoney(_price.text) ?? -1;

  /// Money knocked off the whole line, only when there really is a discount.
  int get _off =>
      _p >= 0 && _p < _batch.price && _q > 0 ? (_batch.price - _p) * _q : 0;

  void _pickBatch(Batch b) {
    setState(() {
      _batch = b;
      // The price field follows the batch, otherwise it silently keeps the
      // price of a batch the customer is no longer buying from.
      _price.text = _asText(b.price);
    });
  }

  void _submit() {
    if (_q <= 0) return toast(context, t('Quantity must be more than zero'), bad: true);
    if (!widget.quote && _q > _batch.qtyLeft) {
      return toast(context, '${t('Only')} ${_batch.qtyLeft} ${t('available')}', bad: true);
    }
    if (_p < 0) return toast(context, t('Enter a valid selling price'), bad: true);
    if (_p < _batch.cost) {
      return toast(context, t('Price cannot be less than the cost'), bad: true);
    }
    Navigator.pop(
        context,
        SellLine(
          productId: widget.product.id,
          batchId: _batch.id,
          name: widget.product.name,
          price: _p,
          listPrice: _batch.price,
          qty: _q,
        ));
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.quote ? C.quote : C.sell;
    return Scaffold(
      appBar: AppBar(backgroundColor: color, title: Text(widget.product.name)),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Center(child: Photo(widget.product.image, size: 110)),
        const SizedBox(height: 18),
        if (widget.batches.length > 1) ...[
          Text(t('Choose batch'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
        ],
        for (var i = 0; i < widget.batches.length; i++)
          _BatchOption(
            batch: widget.batches[i],
            index: i + 1,
            selected: _batch.id == widget.batches[i].id,
            onTap: () => _pickBatch(widget.batches[i]),
          ),
        const SizedBox(height: 18),
        NumField(_qty, t('Quantity'), Icons.numbers,
            decimal: false, autofocus: true, onChanged: (_) => setState(() {})),
        const SizedBox(height: 14),
        NumField(_price, '${t('Price each')} (Rs.)', Icons.local_offer,
            onChanged: (_) => setState(() {})),
        const SizedBox(height: 6),
        Text(
            '${t('Normal')} ${money(_batch.price)}   •   ${t('Cost')} ${money(_batch.cost)}',
            style: const TextStyle(fontSize: 14, color: Colors.black54)),
        if (_p >= 0 && _p < _batch.cost)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(t('Price cannot be less than the cost'),
                style: const TextStyle(
                    fontSize: 14, color: C.owe, fontWeight: FontWeight.w600)),
          )
        else if (_off > 0)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('${t('Discount')} ${money(_off)}',
                style: const TextStyle(
                    fontSize: 15, color: C.quote, fontWeight: FontWeight.w700)),
          ),
        const SizedBox(height: 16),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(t('Total'),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          Money((_p < 0 ? 0 : _p) * (_q < 0 ? 0 : _q), size: 24, color: color),
        ]),
        const SizedBox(height: 20),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: color),
          icon: const Icon(Icons.add),
          label: Text(t('Add')),
          onPressed: _submit,
        ),
      ]),
    );
  }
}

class _BatchOption extends StatelessWidget {
  final Batch batch;
  final int index;
  final bool selected;
  final VoidCallback onTap;
  const _BatchOption(
      {required this.batch,
      required this.index,
      required this.selected,
      required this.onTap});

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 8),
        color: selected ? C.sell.withValues(alpha: 0.12) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
              color: selected ? C.sell : Colors.black12, width: selected ? 2 : 1),
        ),
        child: ListTile(
          onTap: onTap,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          leading: Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected ? C.sell : Colors.black38, size: 28),
          title: Text('${t('Batch')} $index   •   ${money(batch.price)}',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          subtitle: Text('${t('Available')}: ${batch.qtyLeft}',
              style: const TextStyle(fontSize: 15)),
        ),
      );
}
