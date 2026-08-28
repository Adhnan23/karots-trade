import 'package:flutter/material.dart';

import '../core.dart';
import '../files.dart';
import '../models.dart';
import '../store.dart' as s;
import 'buy.dart' show NumField, PurchasesList;
import 'cheques.dart';
import 'customers.dart';

/// Search text plus a date window, shared by all three tabs.
class Filters {
  final String q;
  final DateTimeRange? range;
  const Filters({this.q = '', this.range});

  DateTime? get from => range?.start;
  DateTime? get to => range == null
      ? null
      : DateTime(range!.end.year, range!.end.month, range!.end.day, 23, 59, 59);

  @override
  bool operator ==(Object other) =>
      other is Filters && other.q == q && other.range == range;

  @override
  int get hashCode => Object.hash(q, range);
}

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  Filters _f = const Filters();

  static final _presets = <String, DateTimeRange? Function()>{
    'All time': () => null,
    'Today': () {
      final n = DateTime.now();
      return DateTimeRange(start: DateTime(n.year, n.month, n.day), end: n);
    },
    'Last 7 days': () {
      final n = DateTime.now();
      return DateTimeRange(
          start: DateTime(n.year, n.month, n.day).subtract(const Duration(days: 6)),
          end: n);
    },
    'This month': () {
      final n = DateTime.now();
      return DateTimeRange(start: DateTime(n.year, n.month), end: n);
    },
  };

  String _rangeLabel() {
    final r = _f.range;
    if (r == null) return t('All time');
    String d(DateTime x) => '${x.day}/${x.month}';
    final same = r.start.year == r.end.year &&
        r.start.month == r.end.month &&
        r.start.day == r.end.day;
    return same ? d(r.start) : '${d(r.start)} – ${d(r.end)}';
  }

  Future<void> _pickRange() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final name in _presets.keys)
            ListTile(
              leading: const Icon(Icons.event, color: C.history),
              title: Text(t(name), style: const TextStyle(fontSize: 17)),
              onTap: () => Navigator.pop(context, name),
            ),
          ListTile(
            leading: const Icon(Icons.date_range, color: C.history),
            title: Text(t('Choose dates'), style: const TextStyle(fontSize: 17)),
            onTap: () => Navigator.pop(context, 'custom'),
          ),
        ]),
      ),
    );
    if (choice == null || !mounted) return;

    if (choice == 'custom') {
      final now = DateTime.now();
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(now.year - 5),
        lastDate: now,
        initialDateRange: _f.range,
      );
      if (picked != null && mounted) {
        setState(() => _f = Filters(q: _f.q, range: picked));
      }
      return;
    }
    setState(() => _f = Filters(q: _f.q, range: _presets[choice]!()));
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 4,
        child: Scaffold(
          appBar: AppBar(
            backgroundColor: C.history,
            title: Text(t('History')),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(110),
              child: Column(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                  child: Row(children: [
                    Expanded(
                      child: SizedBox(
                        height: 46,
                        child: TextField(
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: t('Search name or number'),
                            prefixIcon: const Icon(Icons.search),
                          ),
                          onChanged: (v) =>
                              setState(() => _f = Filters(q: v, range: _f.range)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: _pickRange,
                        child: Container(
                          height: 46,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          alignment: Alignment.center,
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.event, size: 20, color: C.history),
                            const SizedBox(width: 6),
                            Text(_rangeLabel(),
                                style: const TextStyle(
                                    fontSize: 14, fontWeight: FontWeight.w600)),
                          ]),
                        ),
                      ),
                    ),
                  ]),
                ),
                TabBar(
                  indicatorColor: Colors.white,
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white70,
                  labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                  labelStyle:
                      const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  tabs: [
                    Tab(child: Fit(t('Sales'))),
                    Tab(child: Fit(t('Cheques'))),
                    Tab(child: Fit(t('Returns'))),
                    Tab(child: Fit(t('Purchases'))),
                  ],
                ),
              ]),
            ),
          ),
          body: TabBarView(children: [
            DocList(_f),
            ChequesList(_f),
            ReturnsList(_f),
            PurchasesList(_f),
          ]),
        ),
      );
}

// ---------------------------------------------------------------- sales & quotes

class DocList extends StatefulWidget {
  final Filters filters;
  const DocList(this.filters, {super.key});
  @override
  State<DocList> createState() => _DocListState();
}

class _DocListState extends State<DocList> {
  String? _kind; // null = everything
  late Future<List<Doc>> _list = _load();

  Future<List<Doc>> _load() => s.docs(
      q: widget.filters.q,
      kind: _kind,
      from: widget.filters.from,
      to: widget.filters.to);

  void _reload() {
    if (!mounted) return;
    setState(() {
      _list = _load();
    });
  }

  @override
  void didUpdateWidget(DocList old) {
    super.didUpdateWidget(old);
    if (old.filters != widget.filters) _reload();
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          // Scrolls sideways: three chips fit in English but not always in
          // Tamil, and never at a large system font size.
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
            for (final (label, value) in [
              ('Everything', null),
              ('Sales', 'sale'),
              ('Quotes', 'quote')
            ])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(t(label)),
                  selected: _kind == value,
                  selectedColor: C.history.withValues(alpha: 0.18),
                  onSelected: (_) {
                    _kind = value;
                    _reload();
                  },
                ),
              ),
            ]),
          ),
        ),
        Expanded(
          child: FutureBuilder(
            future: _list,
            builder: (_, snap) {
              final docs = snap.data;
              if (docs == null) return const Center(child: CircularProgressIndicator());
              if (docs.isEmpty) {
                return EmptyState(Icons.receipt_long, 'Nothing here yet',
                    'Sales and quotes show up here.');
              }
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                itemCount: docs.length,
                itemBuilder: (_, i) => DocTile(docs[i], onChanged: _reload),
              );
            },
          ),
        ),
      ]);
}

class DocTile extends StatelessWidget {
  final Doc d;
  final VoidCallback? onChanged;
  const DocTile(this.d, {this.onChanged, super.key});

  @override
  Widget build(BuildContext context) {
    final color = d.isCancelled
        ? Colors.grey
        : d.isQuote
            ? C.quote
            : C.sell;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        leading: CircleAvatar(
          backgroundColor: color,
          child: Icon(d.isQuote ? Icons.description : Icons.point_of_sale,
              color: Colors.white),
        ),
        title: Text('${t(d.isQuote ? 'Quote' : 'Sale')} #${d.no}  •  ${d.customerName}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(when(d.createdAt), style: const TextStyle(fontSize: 13)),
          StatusChip(d),
        ]),
        trailing: Money(d.total, color: color),
        onTap: () async {
          await Navigator.push(
              context, MaterialPageRoute(builder: (_) => DocScreen(d.id)));
          onChanged?.call();
        },
      ),
    );
  }
}

class StatusChip extends StatelessWidget {
  final Doc d;
  const StatusChip(this.d, {super.key});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (d) {
      _ when d.isCancelled => ('Cancelled', Colors.grey),
      _ when d.isQuote && d.isConverted => ('Converted to sale', C.buy),
      _ when d.isQuote => ('Waiting', C.quote),
      _ when d.due <= 0 => ('Paid', C.buy),
      _ when d.settled > 0 => ('Part paid', C.sell),
      _ => ('Not paid', C.owe),
    };
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(top: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12)),
        child: Text(t(label),
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
      ),
    );
  }
}

// ---------------------------------------------------------------- one document

class DocScreen extends StatefulWidget {
  final String id;
  const DocScreen(this.id, {super.key});
  @override
  State<DocScreen> createState() => _DocScreenState();
}

class _DocScreenState extends State<DocScreen> {
  late Future<(Doc?, List<DocItem>, int)> _data = _load();

  /// The customer's whole balance comes along, so a bill can tell them what
  /// they owe altogether and not just for this one sale.
  Future<(Doc?, List<DocItem>, int)> _load() async {
    final d = await s.doc(widget.id);
    return (
      d,
      await s.docItems(widget.id),
      d == null ? 0 : await s.balance(d.customerId),
    );
  }

  void _reload() {
    if (!mounted) return;
    setState(() {
      _data = _load();
    });
  }

  Future<void> _convert(Doc d) async {
    final paid = await showDialog<int>(
      context: context,
      builder: (_) => _PaidDialog(total: d.total),
    );
    if (paid == null || !mounted) return;
    final id = await guard(context, () => s.convertQuote(d.id, paid: paid));
    if (id == null || !mounted) return;
    toast(context, t('Sale created'));
    await Navigator.pushReplacement(
        context, MaterialPageRoute(builder: (_) => DocScreen(id)));
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
        future: _data,
        builder: (_, snap) {
          if (!snap.hasData) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          final (d, items, owing) = snap.data!;
          if (d == null) {
            return Scaffold(appBar: AppBar(), body: Center(child: Text(t('Not found'))));
          }
          final color = d.isCancelled
              ? Colors.grey
              : d.isQuote
                  ? C.quote
                  : C.sell;
          final canReturn =
              !d.isQuote && !d.isCancelled && items.any((i) => i.returnable > 0);
          final saved = items.fold(0, (a, i) => a + i.discount);

          return Scaffold(
            appBar: AppBar(
              backgroundColor: color,
              title: Text('${t(d.isQuote ? 'Quote' : 'Sale')} #${d.no}'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.receipt_long),
                  tooltip: t('Receipt'),
                  onPressed: () => showReceipt(context, saleReceipt(d, items, owing)),
                ),
              ],
            ),
            body: ListView(padding: const EdgeInsets.all(16), children: [
              Card(
                child: ListTile(
                  leading: const CircleAvatar(
                      backgroundColor: C.customers,
                      child: Icon(Icons.person, color: Colors.white)),
                  title: Text(d.customerName,
                      style:
                          const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  subtitle: Text([d.customerPhone, when(d.createdAt)]
                      .where((e) => e.isNotEmpty)
                      .join('\n')),
                  isThreeLine: d.customerPhone.isNotEmpty,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => CustomerScreen(d.customerId))),
                ),
              ),
              const SizedBox(height: 10),
              StatusChip(d),
              const SizedBox(height: 14),
              for (final i in items)
                Card(
                  margin: const EdgeInsets.only(bottom: 6),
                  child: ListTile(
                    title: Text(i.name,
                        style:
                            const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                    subtitle: Text([
                      '${i.qty} × ${money(i.price)}',
                      if (i.discount > 0)
                        '${t('Was')} ${money(i.listPrice)}',
                      if (i.returned > 0) '${t('Returned')}: ${i.returned}',
                    ].join('   •   ')),
                    trailing: Money(i.total),
                  ),
                ),
              const SizedBox(height: 10),
              _TotalRow(t('Total'), d.total, big: true, color: color),
              if (saved > 0) _TotalRow(t('You saved'), saved, color: C.quote),
              if (!d.isQuote) ...[
                _TotalRow(t('Paid'), d.settled, color: C.advance),
                if (d.settledLater)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                        '${t('Includes')} ${money(d.settled - d.paid)} ${t('paid after the sale')}',
                        style: const TextStyle(fontSize: 13, color: Colors.black45)),
                  ),
                _TotalRow(d.due > 0 ? t('Balance due') : t('Settled'), d.due.abs(),
                    color: d.due > 0 ? C.owe : C.advance),
              ],
              const SizedBox(height: 22),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: color),
                icon: const Icon(Icons.receipt_long),
                label: Text(t('Receipt')),
                onPressed: () => showReceipt(context, saleReceipt(d, items, owing)),
              ),
              if (d.isQuote && d.status == 'pending') ...[
                const SizedBox(height: 10),
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: C.buy),
                  icon: const Icon(Icons.check_circle),
                  label: Text(t('Convert to sale')),
                  onPressed: () => _convert(d),
                ),
              ],
              if (canReturn) ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(56), foregroundColor: C.ret),
                  icon: const Icon(Icons.assignment_return),
                  label: Text(t('Return items'), style: const TextStyle(fontSize: 18)),
                  onPressed: () async {
                    final done = await Navigator.push<bool>(context,
                        MaterialPageRoute(builder: (_) => ReturnScreen(d, items)));
                    if (done == true) _reload();
                  },
                ),
              ],
              if (!d.isCancelled && d.status != 'completed') ...[
                const SizedBox(height: 8),
                TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: C.owe),
                  icon: const Icon(Icons.cancel_outlined),
                  label: Text(t(d.isQuote ? 'Cancel quote' : 'Cancel sale')),
                  onPressed: () async {
                    if (!await ask(
                        context,
                        t(d.isQuote
                            ? 'Cancel this quote?'
                            : 'Cancel this sale? Stock goes back and the charge is reversed.'),
                        t('Yes'))) {
                      return;
                    }
                    if (!context.mounted) return;
                    final ok =
                        await guard(context, () => s.cancelDoc(d.id).then((_) => true));
                    if (ok == true) _reload();
                  },
                ),
              ],
            ]),
          );
        },
      );
}

class _TotalRow extends StatelessWidget {
  final String label;
  final int amount;
  final bool big;
  final Color? color;
  const _TotalRow(this.label, this.amount, {this.big = false, this.color});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label,
              style: TextStyle(
                  fontSize: big ? 20 : 16,
                  fontWeight: big ? FontWeight.w700 : FontWeight.w500)),
          Money(amount, size: big ? 24 : 18, color: color),
        ]),
      );
}

class _PaidDialog extends StatefulWidget {
  final int total;
  const _PaidDialog({required this.total});
  @override
  State<_PaidDialog> createState() => _PaidDialogState();
}

class _PaidDialogState extends State<_PaidDialog> {
  late final _c = TextEditingController(text: (widget.total / 100).toString());

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(t('How much did they pay?')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('${t('Total')}: ${money(widget.total)}',
              style: const TextStyle(fontSize: 16)),
          const SizedBox(height: 12),
          NumField(_c, '${t('Paid')} (Rs.)', Icons.payments, autofocus: true),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(t('Cancel'))),
          FilledButton(
            onPressed: () {
              final v = parseMoney(_c.text);
              if (v == null) {
                toast(context, t('Enter a valid amount'), bad: true);
                return;
              }
              Navigator.pop(context, v);
            },
            child: Text(t('Save')),
          ),
        ],
      );
}

// ---------------------------------------------------------------- returns

class ReturnScreen extends StatefulWidget {
  final Doc doc;
  final List<DocItem> items;
  const ReturnScreen(this.doc, this.items, {super.key});
  @override
  State<ReturnScreen> createState() => _ReturnScreenState();
}

class _ReturnScreenState extends State<ReturnScreen> {
  final _qty = <String, int>{};
  bool _saving = false;

  List<DocItem> get _returnable =>
      widget.items.where((i) => i.returnable > 0).toList();

  int get _total => _qty.entries.fold(
      0, (a, e) => a + widget.items.firstWhere((i) => i.id == e.key).price * e.value);

  Future<void> _save() async {
    setState(() => _saving = true);
    final id = await guard(context, () => s.saveReturn(widget.doc.id, _qty));
    if (!mounted) return;
    setState(() => _saving = false);
    if (id == null) return;
    final nav = Navigator.of(context);
    await showReturnReceipt(context, id);
    nav.pop(true);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(backgroundColor: C.ret, title: Text(t('Return items'))),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          Text(t('How many are coming back?'),
              style: const TextStyle(fontSize: 17, color: Colors.black54)),
          const SizedBox(height: 12),
          for (final i in _returnable)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
                child: Row(children: [
                  Expanded(
                    child:
                        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(i.name,
                          style: const TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w600)),
                      Text('${money(i.price)}  •  ${t('Can return')}: ${i.returnable}',
                          style: const TextStyle(fontSize: 14, color: Colors.black54)),
                    ]),
                  ),
                  _Stepper(
                    value: _qty[i.id] ?? 0,
                    max: i.returnable,
                    onChanged: (v) => setState(() => _qty[i.id] = v),
                  ),
                ]),
              ),
            ),
        ]),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(t('Credit to customer'),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                Money(_total, size: 22, color: C.ret),
              ]),
              const SizedBox(height: 10),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: C.ret),
                icon: const Icon(Icons.check),
                label: Text(t('Save')),
                onPressed: _total == 0 || _saving ? null : _save,
              ),
            ]),
          ),
        ),
      );
}

/// Built from the stored return, so a reprint months later says exactly what
/// the original said.
Future<void> showReturnReceipt(BuildContext context, String returnId) async {
  final data = await s.oneReturn(returnId);
  if (data == null || !context.mounted) return;
  final (r, items) = data;
  await showReceipt(
    context,
    Receipt(
      kind: 'Return',
      no: r['no'] as int,
      date: r['created_at'] as int,
      customer: r['customer_name'] as String?,
      customerPhone: r['customer_phone'] as String?,
      reference: 'Against Sale #${r['sale_no']}',
      lines: [
        for (final i in items) (i['name'] as String, i['qty'] as int, i['price'] as int)
      ],
      totals: [
        ('Returned value', r['total'] as int),
        ('Credited to account', r['total'] as int),
      ],
      footnote: 'Stock taken back and the customer account credited.',
    ),
  );
}

class _Stepper extends StatelessWidget {
  final int value, max;
  final ValueChanged<int> onChanged;
  const _Stepper({required this.value, required this.max, required this.onChanged});

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          iconSize: 34,
          icon: const Icon(Icons.remove_circle_outline),
          onPressed: value <= 0 ? null : () => onChanged(value - 1),
        ),
        SizedBox(
          width: 34,
          child: Text('$value',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
        ),
        IconButton(
          iconSize: 34,
          color: C.ret,
          icon: const Icon(Icons.add_circle),
          onPressed: value >= max ? null : () => onChanged(value + 1),
        ),
      ]);
}

class ReturnsList extends StatefulWidget {
  final Filters filters;
  const ReturnsList(this.filters, {super.key});
  @override
  State<ReturnsList> createState() => _ReturnsListState();
}

class _ReturnsListState extends State<ReturnsList> {
  late Future<List<SqlRow>> _list = _load();

  Future<List<SqlRow>> _load() =>
      s.returns(q: widget.filters.q, from: widget.filters.from, to: widget.filters.to);

  @override
  void didUpdateWidget(ReturnsList old) {
    super.didUpdateWidget(old);
    if (old.filters != widget.filters && mounted) {
      setState(() {
        _list = _load();
      });
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
        future: _list,
        builder: (_, snap) {
          final rows = snap.data;
          if (rows == null) return const Center(child: CircularProgressIndicator());
          if (rows.isEmpty) {
            return EmptyState(Icons.assignment_return, 'Nothing here yet',
                'Returned items show up here.');
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
                      backgroundColor: C.ret,
                      child: Icon(Icons.assignment_return, color: Colors.white)),
                  title: Text('${t('Return')} #${r['no']}  •  ${r['customer_name']}',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                      '${t('From sale')} #${r['sale_no']}\n${when(r['created_at'] as int)}'),
                  isThreeLine: true,
                  trailing: Money(r['total'] as int, color: C.ret),
                  onTap: () => showReturnReceipt(context, r['id'] as String),
                ),
              );
            },
          );
        },
      );
}

/// The bill or quotation itself. Top level so the figures on it — what this
/// sale came to, and what the customer owes altogether — can be checked
/// without driving a screen.
///
/// Receipts print in English, so this text is deliberately not translated.
String _line(DocItem i) => i.discount == 0
    ? i.name
    : '${i.name}\nWas ${money(i.listPrice)} each  -  saved ${money(i.discount)}';

Receipt saleReceipt(Doc d, List<DocItem> items, int owing) {
  final saved = items.fold(0, (a, i) => a + i.discount);
  // What the customer owes on everything except this bill. A quotation is
  // not a bill, and a cancelled sale is not owed, so neither carries it.
  final earlier =
      d.isQuote || d.isCancelled ? 0 : (owing - d.due < 0 ? 0 : owing - d.due);
  return Receipt(
    kind: d.isQuote ? 'Quotation' : 'Sale',
    no: d.no,
    date: d.createdAt,
    customer: d.customerName,
    customerPhone: d.customerPhone,
    reference: d.fromQuote == null ? null : 'Converted from a quotation',
    lines: [for (final i in items) (_line(i), i.qty, i.price)],
    totals: [
      ('Total', d.total),
      if (saved > 0) ('You saved', saved),
      if (!d.isQuote) ('Paid', d.settled),
      if (!d.isQuote) (d.due > 0 ? 'Balance due' : 'Settled', d.due),
      // Old debt belongs on the new bill: the customer is being asked for
      // one figure at the counter, not two.
      if (earlier > 0) ('Earlier dues', earlier),
      if (earlier > 0) ('Total to pay', owing),
    ],
    footnote: switch (d) {
      _ when d.isCancelled => 'This sale was cancelled.',
      _ when d.isQuote => 'Prices held while stock lasts. This is not a bill.',
      // A due date beats "within a week": it is the thing to point at later.
      _ when d.due > 0 =>
        'Please settle ${money(d.due)} by ${onDay(payBy(d.createdAt))} '
            '(within $creditDays days).',
      _ => null,
    },
  );
}
