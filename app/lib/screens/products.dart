import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core.dart';
import '../models.dart';
import 'buy.dart' show NumField;
import '../photo.dart';
import '../store.dart' as s;

class ProductsScreen extends StatefulWidget {
  /// When true the screen returns the tapped product instead of opening it.
  final bool picking;
  const ProductsScreen({this.picking = false, super.key});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  String _q = '';
  late Future<List<Product>> _list = s.products();
  late Future<({int items, int cost, int retail})> _value = s.stockValue();

  void _reload() {
    if (!mounted) return;
    setState(() {
      _list = s.products(q: _q);
      _value = s.stockValue();
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          backgroundColor: C.products,
          title: Text(t(widget.picking ? 'Choose product' : 'Products')),
          actions: [
            IconButton(
              tooltip: t(s.productsAsCards ? 'Show as a list' : 'Show as cards'),
              icon: Icon(s.productsAsCards ? Icons.view_list : Icons.grid_view),
              onPressed: () async {
                await s.setSetting(
                    'product_view', s.productsAsCards ? 'list' : 'cards');
                _reload();
              },
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: C.products,
          foregroundColor: Colors.white,
          icon: const Icon(Icons.add),
          label: Text(t('Add')),
          onPressed: () async {
            final id = await Navigator.push<String>(
                context, MaterialPageRoute(builder: (_) => const ProductForm()));
            if (id == null) return;
            if (!widget.picking) return _reload();
            final created = await s.product(id);
            if (context.mounted) Navigator.pop(context, created);
          },
        ),
        body: Column(children: [
          // Not while picking a product for a sale: that is the middle of a
          // transaction, and what the shelf is worth is nobody's business then.
          if (!widget.picking) _StockValue(_value),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: TextField(
              decoration: InputDecoration(
                  hintText: t('Search'), prefixIcon: const Icon(Icons.search)),
              onChanged: (v) {
                _q = v;
                _reload();
              },
            ),
          ),
          Expanded(
            child: FutureBuilder(
              future: _list,
              builder: (_, snap) {
                final items = snap.data;
                if (items == null) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (items.isEmpty) {
                  return EmptyState(Icons.inventory_2, 'No products yet',
                      'Tap Add, or buy stock to create one.');
                }
                void open(Product p) async {
                  if (widget.picking) {
                    Navigator.pop(context, p);
                    return;
                  }
                  await Navigator.push(
                      context, MaterialPageRoute(builder: (_) => ProductScreen(p.id)));
                  _reload();
                }

                if (!s.productsAsCards) {
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 90),
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => ProductRow(items[i], onTap: open),
                  );
                }
                return GridView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 90),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 210,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.82,
                  ),
                  itemCount: items.length,
                  itemBuilder: (_, i) => ProductCard(items[i], onTap: open),
                );
              },
            ),
          ),
        ]),
      );
}

class ProductScreen extends StatefulWidget {
  final String id;
  const ProductScreen(this.id, {super.key});
  @override
  State<ProductScreen> createState() => _ProductScreenState();
}

class _ProductScreenState extends State<ProductScreen> {
  late Future<(Product?, List<Batch>, List<SqlRow>)> _data = _load();

  Future<(Product?, List<Batch>, List<SqlRow>)> _load() async => (
        await s.product(widget.id),
        await s.batches(widget.id),
        await s.adjustments(productId: widget.id),
      );

  void _reload() {
    if (!mounted) return;
    setState(() {
      _data = _load();
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(backgroundColor: C.products, title: Text(t('Products'))),
        body: FutureBuilder(
          future: _data,
          builder: (_, snap) {
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final (p, batches, fixes) = snap.data!;
            if (p == null) return Center(child: Text(t('Not found')));
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Center(child: Photo(p.image, size: 160)),
                const SizedBox(height: 14),
                Text(p.name,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                        color: C.buy.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(20)),
                    child: Text('${t('Stock')}: ${p.stock}',
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700, color: C.buy)),
                  ),
                ),
                const SizedBox(height: 20),
                Text(t('Batches'),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                if (batches.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Text(t('No stock yet. Use Buy to add stock.'),
                        style: const TextStyle(color: Colors.black54, fontSize: 16)),
                  ),
                for (var i = 0; i < batches.length; i++)
                  BatchCard(
                    batches[i],
                    i + 1,
                    onFix: () async {
                      final done = await Navigator.push<bool>(
                          context,
                          MaterialPageRoute(
                              builder: (_) => FixBatchScreen(batches[i], i + 1)));
                      if (done == true) _reload();
                    },
                  ),
                if (fixes.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Text(t('Corrections'),
                      style:
                          const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  for (final f in fixes) _FixRow(f),
                ],
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  icon: const Icon(Icons.edit),
                  label: Text(t('Edit')),
                  onPressed: () async {
                    final r = await Navigator.push<String>(context,
                        MaterialPageRoute(builder: (_) => ProductForm(product: p)));
                    if (r != null) _reload();
                  },
                ),
                const SizedBox(height: 10),
                TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: C.owe),
                  icon: const Icon(Icons.delete_outline),
                  label: Text(t('Delete')),
                  onPressed: () async {
                    if (!await ask(context, '${t('Delete')} "${p.name}"?', t('Delete'))) {
                      return;
                    }
                    if (!context.mounted) return;
                    final ok =
                        await guard(context, () => s.deleteProduct(p.id).then((_) => true));
                    if (ok == true && context.mounted) Navigator.pop(context);
                  },
                ),
              ],
            );
          },
        ),
      );
}

class BatchCard extends StatelessWidget {
  final Batch b;
  final int index;
  final VoidCallback? onFix;
  const BatchCard(this.b, this.index, {this.onFix, super.key});

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text('${t('Batch')} $index',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                    color: (b.qtyLeft > 0 ? C.buy : Colors.grey).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12)),
                child: Text('${b.qtyLeft} / ${b.qtyIn}',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: b.qtyLeft > 0 ? C.buy : Colors.grey)),
              ),
              if (onFix != null)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: t('Fix this batch'),
                  icon: const Icon(Icons.tune, color: C.products),
                  onPressed: onFix,
                ),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              _kv(t('Cost'), money(b.cost), Colors.black54),
              const SizedBox(width: 20),
              _kv(t('Selling price'), money(b.price), C.sell),
            ]),
            const SizedBox(height: 4),
            Text(when(b.createdAt),
                style: const TextStyle(fontSize: 12, color: Colors.black38)),
          ]),
        ),
      );

  Widget _kv(String k, String v, Color c) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(k, style: const TextStyle(fontSize: 12, color: Colors.black45)),
          Text(v, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: c)),
        ],
      );
}

class ProductForm extends StatefulWidget {
  final Product? product;
  const ProductForm({this.product, super.key});
  @override
  State<ProductForm> createState() => _ProductFormState();
}

class _ProductFormState extends State<ProductForm> {
  late final _name = TextEditingController(text: widget.product?.name ?? '');
  late Uint8List? _image = widget.product?.image;
  bool _imageChanged = false;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            backgroundColor: C.products,
            title: Text(t(widget.product == null ? 'New product' : 'Edit'))),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          Center(
            child: GestureDetector(
              onTap: () async {
                final b = await pickPhoto(context);
                if (b != null) setState(() => (_image = b, _imageChanged = true));
              },
              child: Column(children: [
                Photo(_image, size: 150),
                TextButton.icon(
                  icon: const Icon(Icons.photo_camera),
                  label: Text(t('Photo')),
                  onPressed: () async {
                    final b = await pickPhoto(context);
                    if (b != null) setState(() => (_image = b, _imageChanged = true));
                  },
                ),
              ]),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _name,
            autofocus: widget.product == null,
            textCapitalization: TextCapitalization.words,
            style: const TextStyle(fontSize: 18),
            decoration: InputDecoration(labelText: t('Name')),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: C.products),
            icon: const Icon(Icons.check),
            label: Text(t('Save')),
            onPressed: _saving
                ? null
                : () async {
                    if (_saving) return;
                    setState(() => _saving = true);
                    final id = await guard(
                        context,
                        () => s.saveProduct(
                              id: widget.product?.id,
                              name: _name.text,
                              image: _imageChanged ? _image : null,
                            ));
                    if (!context.mounted) return;
                    setState(() => _saving = false);
                    if (id != null) Navigator.pop(context, id);
                  },
          ),
        ]),
      );
}

/// Photo-first tile. Big picture, name, stock badge — recognisable at a glance.
class ProductCard extends StatelessWidget {
  final Product p;
  final void Function(Product) onTap;
  const ProductCard(this.p, {required this.onTap, super.key});

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => onTap(p),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(
              child: Stack(fit: StackFit.expand, children: [
                Photo(p.image, fill: true),
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: p.stock > 0 ? C.buy : C.owe,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text('${p.stock}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w800)),
                  ),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(t(p.stock > 0 ? 'In stock' : 'Out of stock'),
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: p.stock > 0 ? C.buy : C.owe)),
              ]),
            ),
          ]),
        ),
      );
}

class ProductRow extends StatelessWidget {
  final Product p;
  final void Function(Product) onTap;
  const ProductRow(this.p, {required this.onTap, super.key});

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          contentPadding: const EdgeInsets.all(10),
          leading: Photo(p.image, size: 56),
          title: Text(p.name,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
          subtitle: Text('${t('Stock')}: ${p.stock}',
              style: TextStyle(
                  fontSize: 15,
                  color: p.stock > 0 ? C.buy : C.owe,
                  fontWeight: FontWeight.w600)),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => onTap(p),
        ),
      );
}

class _FixRow extends StatelessWidget {
  final SqlRow f;
  const _FixRow(this.f);

  @override
  Widget build(BuildContext context) {
    final qb = f['qty_before'] as int, qa = f['qty_after'] as int;
    final parts = <String>[
      if (qb != qa) '${t('Stock')} $qb → $qa',
      if (f['cost_before'] != f['cost_after'])
        '${t('Cost')} ${money(f['cost_before'] as int)} → ${money(f['cost_after'] as int)}',
      if (f['price_before'] != f['price_after'])
        '${t('Selling price')} ${money(f['price_before'] as int)} → ${money(f['price_after'] as int)}',
    ];
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        dense: true,
        leading: const Icon(Icons.tune, color: C.products),
        title: Text(parts.join('\n'), style: const TextStyle(fontSize: 14)),
        subtitle: Text(
            [when(f['created_at'] as int), if ((f['reason'] as String).isNotEmpty) f['reason']]
                .join('  •  '),
            style: const TextStyle(fontSize: 12)),
      ),
    );
  }
}

/// Correcting a batch after the fact: a miscount on the shelf, a typo in the
/// cost, breakage. Everything that changes is written down.
class FixBatchScreen extends StatefulWidget {
  final Batch batch;
  final int index;
  const FixBatchScreen(this.batch, this.index, {super.key});
  @override
  State<FixBatchScreen> createState() => _FixBatchScreenState();
}

class _FixBatchScreenState extends State<FixBatchScreen> {
  late final _qty = TextEditingController(text: '${widget.batch.qtyLeft}');
  late final _cost =
      TextEditingController(text: (widget.batch.cost / 100).toString());
  late final _price =
      TextEditingController(text: (widget.batch.price / 100).toString());
  final _reason = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _qty.dispose();
    _cost.dispose();
    _price.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final qty = int.tryParse(_qty.text.trim());
    final cost = parseMoney(_cost.text);
    final price = parseMoney(_price.text);
    if (qty == null || qty < 0) {
      return toast(context, t('Enter a valid quantity'), bad: true);
    }
    if (cost == null) return toast(context, t('Enter a valid cost'), bad: true);
    if (price == null) {
      return toast(context, t('Enter a valid selling price'), bad: true);
    }
    setState(() => _saving = true);
    final id = await guard(
        context,
        () => s.fixBatch(widget.batch.id,
            qty: qty, cost: cost, price: price, reason: _reason.text));
    if (!mounted) return;
    setState(() => _saving = false);
    if (id == null) return;
    toast(context, t('Batch corrected'));
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final sold = widget.batch.qtyIn - widget.batch.qtyLeft;
    return Scaffold(
      appBar: AppBar(
          backgroundColor: C.products,
          title: Text('${t('Fix')} ${t('Batch')} ${widget.index}')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: C.products.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(16)),
          child: Text(
              '${widget.batch.productName}\n'
              '${t('Received')}: ${widget.batch.qtyIn}   •   ${t('Gone out')}: $sold',
              style: const TextStyle(fontSize: 15, height: 1.5)),
        ),
        const SizedBox(height: 18),
        NumField(_qty, t('Stock on the shelf now'), Icons.inventory_2, decimal: false),
        const SizedBox(height: 14),
        NumField(_cost, '${t('Cost')} (Rs.)', Icons.shopping_bag),
        const SizedBox(height: 14),
        NumField(_price, '${t('Selling price')} (Rs.)', Icons.sell),
        const SizedBox(height: 14),
        TextField(
          controller: _reason,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
              labelText: t('What happened? (optional)'),
              hintText: t('Miscount, damaged, typo…')),
        ),
        const SizedBox(height: 10),
        Text(t('Sales already made keep the price they were charged.'),
            style: const TextStyle(fontSize: 13, color: Colors.black45)),
        const SizedBox(height: 22),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: C.products),
          icon: const Icon(Icons.check),
          label: Text(t('Save')),
          onPressed: _saving ? null : _save,
        ),
      ]),
    );
  }
}

/// What is on the shelf, and what it is worth — the question a shopkeeper asks
/// about once a month and has no way of answering by counting.
///
/// Two figures, because they answer different things: what the stock cost to
/// buy is money already spent and sitting there, and what it will sell for is
/// what it turns back into.
class _StockValue extends StatelessWidget {
  final Future<({int items, int cost, int retail})> value;
  const _StockValue(this.value);

  @override
  Widget build(BuildContext context) => FutureBuilder(
        future: value,
        builder: (_, snap) {
          final v = snap.data;
          if (v == null || v.items == 0) return const SizedBox.shrink();
          return Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            decoration: BoxDecoration(
                color: C.products.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(18)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${t('Stock on hand')}  ·  ${v.items}',
                  style: const TextStyle(fontSize: 13, color: Colors.black54)),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(child: _Figure(t('What it cost'), v.cost, Colors.black87)),
                Expanded(child: _Figure(t('What it sells for'), v.retail, C.sell)),
              ]),
            ]),
          );
        },
      );
}

class _Figure extends StatelessWidget {
  final String label;
  final int amount;
  final Color color;
  const _Figure(this.label, this.amount, this.color);

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(money(amount),
                maxLines: 1,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: color,
                  fontFeatures: const [FontFeature.tabularFigures()],
                )),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(label,
                maxLines: 1,
                softWrap: false,
                style: const TextStyle(fontSize: 12, color: Colors.black54)),
          ),
        ],
      );
}
