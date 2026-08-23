import 'package:flutter/material.dart';

import '../core.dart';
import '../files.dart';
import '../models.dart';
import '../store.dart' as s;
import 'buy.dart' show NumField;
import 'history.dart';
import 'sell.dart';

class CustomersScreen extends StatefulWidget {
  final bool picking;
  const CustomersScreen({this.picking = false, super.key});
  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  String _q = '';
  late Future<List<Customer>> _list = s.customers();

  void _reload() {
    if (!mounted) return;
    setState(() {
      _list = s.customers(q: _q);
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            backgroundColor: C.customers,
            title: Text(t(widget.picking ? 'Choose customer' : 'Customers'))),
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: C.customers,
          foregroundColor: Colors.white,
          icon: const Icon(Icons.person_add),
          label: Text(t('Add')),
          onPressed: () async {
            final id = await Navigator.push<String>(
                context, MaterialPageRoute(builder: (_) => const CustomerForm()));
            if (id == null) return;
            if (!widget.picking) return _reload();
            final created = await s.customer(id);
            if (context.mounted) Navigator.pop(context, created);
          },
        ),
        body: Column(children: [
          Padding(
            padding: const EdgeInsets.all(12),
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
                  return EmptyState(Icons.people, 'No customers yet',
                      'Add a customer to start selling.');
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 90),
                  itemCount: items.length,
                  itemBuilder: (_, i) {
                    final c = items[i];
                    final b = balanceLabel(c.balance);
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        contentPadding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                        leading: CircleAvatar(
                          radius: 26,
                          backgroundColor: C.customers,
                          child: Text(c.name.characters.first.toUpperCase(),
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold)),
                        ),
                        title: Text(c.name,
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w600)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (c.phone.isNotEmpty)
                              Text(c.phone, style: const TextStyle(fontSize: 14)),
                            Text(b.text,
                                style: TextStyle(
                                    fontSize: 15,
                                    color: b.color,
                                    fontWeight: FontWeight.w700)),
                          ],
                        ),
                        onTap: () async {
                          if (widget.picking) {
                            Navigator.pop(context, c);
                            return;
                          }
                          await Navigator.push(context,
                              MaterialPageRoute(builder: (_) => CustomerScreen(c.id)));
                          _reload();
                        },
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ]),
      );
}

class CustomerScreen extends StatefulWidget {
  final String id;
  const CustomerScreen(this.id, {super.key});
  @override
  State<CustomerScreen> createState() => _CustomerScreenState();
}

class _CustomerScreenState extends State<CustomerScreen> {
  late Future<(Customer?, List<LedgerEntry>, List<Doc>)> _data = _load();

  Future<(Customer?, List<LedgerEntry>, List<Doc>)> _load() async => (
        await s.customer(widget.id),
        await s.ledger(widget.id),
        await s.docs(customerId: widget.id),
      );

  void _reload() {
    if (!mounted) return;
    setState(() {
      _data = _load();
    });
  }

  Future<void> _go(Widget page) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(backgroundColor: C.customers, title: Text(t('Customers'))),
        body: FutureBuilder(
          future: _data,
          builder: (_, snap) {
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final (c, entries, docs) = snap.data!;
            if (c == null) return Center(child: Text(t('Not found')));
            final b = balanceLabel(c.balance);
            return ListView(padding: const EdgeInsets.all(16), children: [
              Text(c.name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
              if (c.phone.isNotEmpty)
                Text(c.phone,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16, color: Colors.black54)),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                    color: b.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20)),
                child: Column(children: [
                  Text(t('Balance'),
                      style: const TextStyle(fontSize: 14, color: Colors.black54)),
                  const SizedBox(height: 4),
                  Text(b.text,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 24, fontWeight: FontWeight.w800, color: b.color)),
                ]),
              ),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: C.sell),
                    icon: const Icon(Icons.point_of_sale),
                    label: Text(t('Sell')),
                    onPressed: () => _go(SellScreen(customer: c)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: C.buy),
                    icon: const Icon(Icons.payments),
                    label: Text(t('Payment')),
                    onPressed: () => _go(PaymentScreen(c)),
                  ),
                ),
              ]),
              const SizedBox(height: 22),
              Text(t('Transaction history'),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              if (entries.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(t('Nothing here yet'),
                      style: const TextStyle(color: Colors.black54, fontSize: 16)),
                ),
              for (final e in entries) _LedgerRow(e, c, docs),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                icon: const Icon(Icons.edit),
                label: Text(t('Edit')),
                onPressed: () async {
                  final r = await Navigator.push<String>(context,
                      MaterialPageRoute(builder: (_) => CustomerForm(customer: c)));
                  if (r != null) _reload();
                },
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: C.owe),
                icon: const Icon(Icons.delete_outline),
                label: Text(t('Delete')),
                onPressed: () async {
                  if (!await ask(context, '${t('Delete')} "${c.name}"?', t('Delete'))) {
                    return;
                  }
                  if (!context.mounted) return;
                  final ok = await guard(
                      context, () => s.deleteCustomer(c.id).then((_) => true));
                  if (ok == true && context.mounted) Navigator.pop(context);
                },
              ),
            ]);
          },
        ),
      );
}

/// Reopens a payment receipt from the stored ledger entry, so a receipt can be
/// handed over again any time — not only in the seconds after taking the money.
Future<void> showPaymentReceipt(
    BuildContext context, Customer c, String ledgerId) async {
  final e = await s.ledgerEntry(ledgerId);
  if (e == null || !context.mounted) return;
  final after = e.balanceAfter;
  await showReceipt(
    context,
    Receipt(
      kind: 'Payment',
      no: e.no,
      date: e.createdAt,
      customer: c.name,
      customerPhone: c.phone,
      totals: [
        ('Payment received', -e.amount),
        (
          after > 0
              ? 'Still owing'
              : after < 0
                  ? 'Advance held'
                  : 'Account settled',
          after.abs()
        ),
      ],
      footnote: e.note.isEmpty ? 'Received with thanks.' : e.note,
    ),
  );
}

class _LedgerRow extends StatelessWidget {
  final LedgerEntry e;
  final Customer customer;
  final List<Doc> docs;
  const _LedgerRow(this.e, this.customer, this.docs);

  static const _look = {
    'sale': (Icons.point_of_sale, C.sell, 'Sale'),
    'payment': (Icons.payments, C.advance, 'Payment'),
    'return': (Icons.assignment_return, C.ret, 'Return'),
    'sale_cancelled': (Icons.cancel, Colors.grey, 'Sale cancelled'),
  };

  @override
  Widget build(BuildContext context) {
    final (icon, color, label) =
        _look[e.type] ?? (Icons.receipt, Colors.grey, e.type);
    Doc? doc;
    for (final d in docs) {
      if (d.id == e.refId) doc = d;
    }
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        leading: CircleAvatar(
            backgroundColor: color.withValues(alpha: 0.15),
            child: Icon(icon, color: color)),
        title: Text(t(label), style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
            [when(e.createdAt), if (e.note.isNotEmpty) e.note].join('\n'),
            style: const TextStyle(fontSize: 13)),
        isThreeLine: e.note.isNotEmpty,
        trailing: Text(
            '${e.amount > 0 ? '+' : '-'}${money(e.amount.abs())}',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: e.amount > 0 ? C.owe : C.advance)),
        onTap: switch (e.type) {
          'payment' when e.refId == null =>
            () => showPaymentReceipt(context, customer, e.id),
          'return' => () => showReturnReceipt(context, e.refId!),
          _ when doc != null =>
            () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => DocScreen(doc!.id))),
          _ => null,
        },
      ),
    );
  }
}

class CustomerForm extends StatefulWidget {
  final Customer? customer;
  const CustomerForm({this.customer, super.key});
  @override
  State<CustomerForm> createState() => _CustomerFormState();
}

class _CustomerFormState extends State<CustomerForm> {
  late final _name = TextEditingController(text: widget.customer?.name ?? '');
  late final _phone = TextEditingController(text: widget.customer?.phone ?? '');

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            backgroundColor: C.customers,
            title: Text(t(widget.customer == null ? 'New customer' : 'Edit'))),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          TextField(
            controller: _name,
            autofocus: widget.customer == null,
            textCapitalization: TextCapitalization.words,
            style: const TextStyle(fontSize: 20),
            decoration: InputDecoration(
                labelText: t('Name'), prefixIcon: const Icon(Icons.person)),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            style: const TextStyle(fontSize: 20),
            decoration: InputDecoration(
                labelText: t('Phone'), prefixIcon: const Icon(Icons.phone)),
          ),
          const SizedBox(height: 26),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: C.customers),
            icon: const Icon(Icons.check),
            label: Text(t('Save')),
            onPressed: () async {
              final id = await guard(
                  context,
                  () => s.saveCustomer(
                      id: widget.customer?.id, name: _name.text, phone: _phone.text));
              if (id != null && context.mounted) Navigator.pop(context, id);
            },
          ),
        ]),
      );
}

/// Recording money in. When nothing is owed this simply becomes an advance —
/// the ledger handles both cases with one entry, and the label says which.
class PaymentScreen extends StatefulWidget {
  final Customer customer;
  const PaymentScreen(this.customer, {super.key});
  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  final _amount = TextEditingController();
  final _note = TextEditingController();

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final owed = widget.customer.balance;
    final amount = parseMoney(_amount.text) ?? 0;
    final after = owed - amount;
    return Scaffold(
      appBar: AppBar(backgroundColor: C.buy, title: Text(t('Payment'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text(widget.customer.name,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Center(
          child: Text(balanceLabel(owed).text,
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: balanceLabel(owed).color)),
        ),
        const SizedBox(height: 22),
        NumField(_amount, '${t('Amount')} (Rs.)', Icons.payments,
            autofocus: true, onChanged: (_) => setState(() {})),
        if (owed > 0 && amount != owed) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => setState(() => _amount.text = (owed / 100).toString()),
              child: Text('${t('Pay full')} ${money(owed)}'),
            ),
          ),
        ],
        const SizedBox(height: 10),
        TextField(
          controller: _note,
          decoration: InputDecoration(labelText: t('Note (optional)')),
        ),
        const SizedBox(height: 18),
        if (amount > 0)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: balanceLabel(after).color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16)),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(t('After payment'), style: const TextStyle(fontSize: 16)),
              Text(balanceLabel(after).text,
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: balanceLabel(after).color)),
            ]),
          ),
        const SizedBox(height: 20),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: C.buy),
          icon: const Icon(Icons.check),
          label: Text(t('Save')),
          onPressed: () async {
            final id = await guard(
                context,
                () => s.recordPayment(widget.customer.id, parseMoney(_amount.text) ?? 0,
                    note: _note.text.trim()));
            if (id == null || !context.mounted) return;
            final nav = Navigator.of(context);
            await showPaymentReceipt(context, widget.customer, id);
            nav.pop(true);
          },
        ),
      ]),
    );
  }
}
