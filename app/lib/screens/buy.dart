import 'package:flutter/material.dart';

import '../core.dart';
import '../files.dart';
import '../models.dart';
import '../photo.dart';
import '../store.dart' as s;
import 'history.dart' show Filters;
import 'products.dart';

class BuyScreen extends StatefulWidget {
  const BuyScreen({super.key});
  @override
  State<BuyScreen> createState() => _BuyScreenState();
}

class _BuyScreenState extends State<BuyScreen> {
  final _lines = <BuyLine>[];
  bool _saving = false;

  int get _total => _lines.fold(0, (a, l) => a + l.total);

  Future<void> _addItem() async {
    final p = await Navigator.push<Product>(context,
        MaterialPageRoute(builder: (_) => const ProductsScreen(picking: true)));
    if (p == null || !mounted) return;

    // Pre-fill from the most recent batch so repeat purchases are two taps.
    final prev = await s.batches(p.id);
    if (!mounted) return;
    final line = await Navigator.push<BuyLine>(
      context,
      MaterialPageRoute(
        builder: (_) => BuyLineForm(
          product: p,
          cost: prev.isEmpty ? 0 : prev.last.cost,
          price: prev.isEmpty ? 0 : prev.last.price,
        ),
      ),
    );
    if (line != null) setState(() => _lines.add(line));
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final id = await guard(context, () => s.savePurchase(_lines));
    if (!mounted) return;
    setState(() => _saving = false);
    if (id == null) return;
    toast(context, t('Purchase saved'));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(backgroundColor: C.buy, title: Text(t('Buy'))),
        // Keeps Add item clear of the system navigation bar on a phone using
        // three buttons rather than gestures.
        body: SafeArea(
            child: Column(children: [
          Expanded(
            child: _lines.isEmpty
                ? EmptyState(Icons.add_shopping_cart, 'Nothing here yet',
                    'Add the products you bought.')
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                    itemCount: _lines.length,
                    itemBuilder: (_, i) {
                      final l = _lines[i];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          contentPadding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
                          leading: Photo(l.image, size: 48),
                          title: Text(l.name,
                              style: const TextStyle(
                                  fontSize: 17, fontWeight: FontWeight.w600)),
                          subtitle: Text(
                              '${l.qty} × ${money(l.cost)}   →   ${t('Selling price')} ${money(l.price)}',
                              style: const TextStyle(fontSize: 14)),
                          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                            Money(l.total, size: 16),
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
                  minimumSize: const Size.fromHeight(56), foregroundColor: C.buy),
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
                  padding: const EdgeInsets.all(12),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text(t('Total'),
                          style: const TextStyle(
                              fontSize: 20, fontWeight: FontWeight.w700)),
                      Money(_total, size: 24, color: C.buy),
                    ]),
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: C.buy),
                      icon: const Icon(Icons.check),
                      label: Text(t('Save')),
                      onPressed: _saving ? null : _save,
                    ),
                  ]),
                ),
              ),
      );
}

class BuyLineForm extends StatefulWidget {
  final Product product;
  final int cost, price;
  const BuyLineForm(
      {required this.product, this.cost = 0, this.price = 0, super.key});
  @override
  State<BuyLineForm> createState() => _BuyLineFormState();
}

class _BuyLineFormState extends State<BuyLineForm> {
  late final _cost =
      TextEditingController(text: widget.cost == 0 ? '' : (widget.cost / 100).toString());
  late final _price = TextEditingController(
      text: widget.price == 0 ? '' : (widget.price / 100).toString());
  final _qty = TextEditingController(text: '1');

  @override
  void dispose() {
    _cost.dispose();
    _price.dispose();
    _qty.dispose();
    super.dispose();
  }

  void _submit() {
    final cost = parseMoney(_cost.text);
    final price = parseMoney(_price.text);
    final qty = int.tryParse(_qty.text.trim()) ?? 0;
    if (cost == null) return toast(context, t('Enter a valid cost'), bad: true);
    if (price == null) return toast(context, t('Enter a valid selling price'), bad: true);
    if (qty <= 0) return toast(context, t('Quantity must be more than zero'), bad: true);
    Navigator.pop(
        context,
        BuyLine(
          productId: widget.product.id,
          name: widget.product.name,
          image: widget.product.image,
          cost: cost,
          price: price,
          qty: qty,
        ));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(backgroundColor: C.buy, title: Text(widget.product.name)),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          Center(child: Photo(widget.product.image, size: 110)),
          const SizedBox(height: 20),
          NumField(_qty, t('Quantity'), Icons.numbers, decimal: false, autofocus: true),
          const SizedBox(height: 14),
          NumField(_cost, '${t('Cost')} (Rs.)', Icons.shopping_bag),
          const SizedBox(height: 14),
          NumField(_price, '${t('Selling price')} (Rs.)', Icons.sell),
          const SizedBox(height: 26),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: C.buy),
            icon: const Icon(Icons.add),
            label: Text(t('Add')),
            onPressed: _submit,
          ),
        ]),
      );
}

/// Big, keyboard-appropriate number input — used everywhere money or a
/// quantity is typed so the fields always look and behave the same.
class NumField extends StatelessWidget {
  final TextEditingController c;
  final String label;
  final IconData icon;
  final bool decimal, autofocus;
  final void Function(String)? onChanged;
  const NumField(this.c, this.label, this.icon,
      {this.decimal = true, this.autofocus = false, this.onChanged, super.key});

  @override
  Widget build(BuildContext context) => TextField(
        controller: c,
        autofocus: autofocus,
        onChanged: onChanged,
        keyboardType: TextInputType.numberWithOptions(decimal: decimal),
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
        decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
      );
}

/// Purchase history, shown as a tab inside the History screen.
class PurchasesList extends StatefulWidget {
  final Filters filters;
  const PurchasesList(this.filters, {super.key});
  @override
  State<PurchasesList> createState() => _PurchasesListState();
}

class _PurchasesListState extends State<PurchasesList> {
  late Future<List<SqlRow>> _list = _load();

  Future<List<SqlRow>> _load() =>
      s.purchases(q: widget.filters.q, from: widget.filters.from, to: widget.filters.to);

  @override
  void didUpdateWidget(PurchasesList old) {
    super.didUpdateWidget(old);
    if (old.filters != widget.filters && mounted) {
      setState(() {
        _list = _load();
      });
    }
  }

  Future<void> _open(SqlRow r) async {
    final items = await s.purchaseItems(r['id'] as String);
    if (!mounted) return;
    await showReceipt(
      context,
      Receipt(
        kind: 'Purchase',
        no: r['no'] as int,
        date: r['created_at'] as int,
        lines: [
          for (final i in items)
            (i['name'] as String, i['qty'] as int, i['cost'] as int)
        ],
        totals: [('Total cost', r['total'] as int)],
        footnote: 'Stock record. No supplier account is kept.',
      ),
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
        future: _list,
        builder: (_, snap) {
          final rows = snap.data;
          if (rows == null) return const Center(child: CircularProgressIndicator());
          if (rows.isEmpty) {
            return EmptyState(
                Icons.add_shopping_cart, 'Nothing here yet', 'Purchases show up here.');
          }
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: rows.length,
            itemBuilder: (_, i) {
              final r = rows[i];
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: const CircleAvatar(
                      backgroundColor: C.buy,
                      child: Icon(Icons.shopping_bag, color: Colors.white)),
                  title: Text('${t('Purchase')} #${r['no']}',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(when(r['created_at'] as int)),
                  trailing: Money(r['total'] as int, color: C.buy),
                  onTap: () => _open(r),
                ),
              );
            },
          );
        },
      );
}
