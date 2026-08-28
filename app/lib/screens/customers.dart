import 'package:flutter/material.dart';

import '../core.dart';
import '../files.dart';
import '../models.dart';
import '../store.dart' as s;
import 'buy.dart' show NumField;
import 'cheques.dart';
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

typedef _CustomerData = (Customer?, List<LedgerEntry>, List<Doc>, List<Cheque>);

class _CustomerScreenState extends State<CustomerScreen> {
  late Future<_CustomerData> _data = _load();

  Future<_CustomerData> _load() async => (
        await s.customer(widget.id),
        await s.ledger(widget.id),
        await s.docs(customerId: widget.id),
        await s.cheques(customerId: widget.id, status: 'pending'),
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

  /// Everything that is not day-to-day counter work. It lives in the app bar
  /// menu because it used to live under the transaction list, where a customer
  /// with a year of history had to be scrolled past to reach Delete.
  Future<void> _menu(String choice, Customer c) async {
    switch (choice) {
      case 'statement':
        await showStatement(context, c.id);
      case 'adjust':
      case 'opening':
        final done = await Navigator.push<bool>(
            context,
            MaterialPageRoute(
                builder: (_) => AdjustScreen(c, opening: choice == 'opening')));
        if (done == true) _reload();
      case 'edit':
        final r = await Navigator.push<String>(
            context, MaterialPageRoute(builder: (_) => CustomerForm(customer: c)));
        if (r != null) _reload();
      case 'delete':
        if (!await ask(context, '${t('Delete')} "${c.name}"?', t('Delete'))) return;
        if (!mounted) return;
        final ok =
            await guard(context, () => s.deleteCustomer(c.id).then((_) => true));
        if (ok == true && mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          backgroundColor: C.customers,
          title: Text(t('Customers')),
          actions: [
            FutureBuilder(
              future: _data,
              builder: (_, snap) {
                final c = snap.data?.$1;
                if (c == null) return const SizedBox.shrink();
                return PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  tooltip: t('More'),
                  onSelected: (v) => _menu(v, c),
                  itemBuilder: (_) => [
                    for (final (value, icon, text) in const [
                      ('statement', Icons.receipt_long, 'Statement'),
                      ('adjust', Icons.tune, 'Adjust balance'),
                      ('opening', Icons.history_edu, 'Balance before this app'),
                      ('edit', Icons.edit, 'Edit'),
                      ('delete', Icons.delete_outline, 'Delete'),
                    ])
                      PopupMenuItem(
                        value: value,
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(icon,
                              color: value == 'delete' ? C.owe : C.customers),
                          title: Text(t(text)),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
        // Three-button navigation keeps a bar across the bottom of the screen,
        // and the last row of the account would otherwise sit under it.
        body: SafeArea(
            child: FutureBuilder(
          future: _data,
          builder: (_, snap) {
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final (c, entries, docs, waiting) = snap.data!;
            if (c == null) return Center(child: Text(t('Not found')));
            final reversed = {
              for (final x in entries)
                if (x.type == 'payment_cancelled') x.refId
            };
            final b = balanceLabel(c.balance);
            // Only the recent end of the account is drawn. A customer with a
            // thousand entries would otherwise build a thousand cards to show
            // the twenty that matter; the statement is where the rest lives.
            final shown = entries.take(_historyShown).toList();
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
              const SizedBox(height: 10),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    foregroundColor: C.history),
                icon: const Icon(Icons.receipt_long),
                label: Fit(t('Statement')),
                onPressed: () => showStatement(context, c.id),
              ),
              if (waiting.isNotEmpty) ...[
                const SizedBox(height: 22),
                Row(children: [
                  // The heading gives way to the amount, never the other way
                  // round — Tamil runs long and a big font setting runs longer.
                  Expanded(
                    child: Text(t('Cheques waiting'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(width: 8),
                  Money(waiting.fold(0, (a, h) => a + h.amount), color: C.quote),
                ]),
                Text(t('Already taken off the balance above.'),
                    style: const TextStyle(fontSize: 13, color: Colors.black54)),
                const SizedBox(height: 8),
                for (final h in waiting)
                  ChequeCard(h, showCustomer: false, onChanged: _reload),
              ],
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
              for (final e in shown)
                _LedgerRow(e, c, docs,
                    undone: reversed.contains(e.id), onChanged: _reload),
              if (entries.length > shown.length)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                      '${t('Showing the latest')} ${shown.length} / ${entries.length}. '
                      '${t('The statement has everything.')}',
                      style: const TextStyle(fontSize: 13, color: Colors.black54)),
                ),
              const SizedBox(height: 24),
            ]);
          },
        )),
      );
}

/// How much of the account is drawn on the customer page itself.
const _historyShown = 50;

/// The whole account on one document: what was billed, what was paid, when, and
/// what is left. Cheques already credited but not yet at the bank are called
/// out by name, because the customer will otherwise wonder where the money went.
Future<void> showStatement(BuildContext context, String customerId) async {
  final c = await s.customer(customerId);
  if (c == null || !context.mounted) return;
  final entries = await s.ledger(customerId);
  final docs = await s.docs(customerId: customerId);
  final waiting = await s.cheques(customerId: customerId, status: 'pending');
  if (!context.mounted) return;

  final byId = {for (final d in docs) d.id: d};
  var billed = 0, paid = 0;
  for (final e in entries) {
    if (e.amount > 0) {
      billed += e.amount;
    } else {
      paid += -e.amount;
    }
  }

  // English only, like every other receipt: the PDF has no Tamil font.
  String detail(LedgerEntry e) {
    final ref = byId[e.refId];
    final tag = ref == null ? '' : ' #${ref.no}';
    return switch (e.type) {
      'sale' => 'Sale$tag',
      'sale_cancelled' => 'Sale$tag cancelled',
      'return' => 'Goods returned$tag',
      'payment' => e.note.isEmpty ? 'Payment received' : e.note,
      'payment_cancelled' => e.note.isEmpty ? 'Payment undone' : e.note,
      'opening' => e.note.isEmpty ? 'Balance brought forward' : e.note,
      'adjustment' => e.note.isEmpty ? 'Adjustment' : e.note,
      _ => e.type,
    };
  }

  await showReceipt(
    context,
    Receipt(
      kind: 'Statement',
      no: 0,
      date: DateTime.now().millisecondsSinceEpoch,
      customer: c.name,
      customerPhone: c.phone,
      reference: 'Account as it stands on ${onDay(DateTime.now())}',
      // Oldest first: a statement is read downwards, the way it was built up.
      statement: [
        for (final e in entries.reversed)
          (onDayMs(e.createdAt), detail(e), e.amount, e.balanceAfter)
      ],
      totals: [
        (
          c.balance > 0
              ? 'Balance due'
              : c.balance < 0
                  ? 'Advance held'
                  : 'Account settled',
          c.balance.abs()
        ),
        ('Total billed', billed),
        ('Total paid', paid),
      ],
      notes: [
        for (final h in waiting)
          'Cheque ${h.chequeNo}${h.bank.isEmpty ? '' : ' (${h.bank})'} for '
              '${money(h.amount)} is already taken off this balance. '
              '${h.daysLeft == 0 ? 'It can be banked now.' : 'It can be banked on ${onDayMs(h.dueAt)}, ${h.daysLeft} day${h.daysLeft == 1 ? '' : 's'} from now.'}',
        if (waiting.isNotEmpty)
          'If a cheque is returned unpaid, its amount goes back onto the balance.',
        if (c.balance > 0)
          'Please settle ${money(c.balance)} at your earliest convenience.',
      ],
      footnote: 'This statement lists every entry on the account to date.',
    ),
  );
}

/// A correction made by hand. Two doors into the same ledger entry: a general
/// adjustment, and the balance a customer already owed before this app existed.
class AdjustScreen extends StatefulWidget {
  final Customer customer;
  final bool opening;
  const AdjustScreen(this.customer, {this.opening = false, super.key});
  @override
  State<AdjustScreen> createState() => _AdjustScreenState();
}

class _AdjustScreenState extends State<AdjustScreen> {
  final _amount = TextEditingController();
  late final _note = TextEditingController(
      text: widget.opening ? t('Owed before this app') : '');

  /// True when the entry makes the customer owe more.
  bool _owesMore = true;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final v = parseMoney(_amount.text) ?? 0;
    final id = await guard(
        context,
        () => s.adjustBalance(widget.customer.id, _owesMore ? v : -v,
            note: _note.text.trim(), opening: widget.opening));
    if (id == null || !mounted) return;
    toast(context, t('Saved'));
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final v = parseMoney(_amount.text) ?? 0;
    final after = widget.customer.balance + (_owesMore ? v : -v);
    final title = widget.opening ? 'Balance before this app' : 'Adjust balance';

    return Scaffold(
      appBar: AppBar(backgroundColor: C.settings, title: Text(t(title))),
      body: SafeArea(
          child: ListView(padding: const EdgeInsets.all(16), children: [
        Text(widget.customer.name,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text(
            t(widget.opening
                ? 'What this customer already owed you before you started using this app.'
                : 'Use this only to correct the books. Every adjustment stays on the account.'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, color: Colors.black54)),
        const SizedBox(height: 18),
        if (!widget.opening) ...[
          SegmentedButton<bool>(
            style: SegmentedButton.styleFrom(
                textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                selectedBackgroundColor: _owesMore ? C.owe : C.advance,
                selectedForegroundColor: Colors.white),
            segments: [
              ButtonSegment(
                  value: true,
                  label: Fit(t('Owes more')),
                  icon: const Icon(Icons.arrow_upward)),
              ButtonSegment(
                  value: false,
                  label: Fit(t('Owes less')),
                  icon: const Icon(Icons.arrow_downward)),
            ],
            selected: {_owesMore},
            onSelectionChanged: (x) => setState(() => _owesMore = x.first),
          ),
          const SizedBox(height: 16),
        ],
        NumField(_amount, '${t('Amount')} (Rs.)', Icons.tune,
            autofocus: true, onChanged: (_) => setState(() {})),
        const SizedBox(height: 14),
        TextField(
          controller: _note,
          decoration: InputDecoration(labelText: t('Reason')),
        ),
        const SizedBox(height: 18),
        if (v > 0)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: balanceLabel(after).color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16)),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Flexible(child: Text(t('Becomes'), style: const TextStyle(fontSize: 16))),
              const SizedBox(width: 8),
              Flexible(
                child: Text(balanceLabel(after).text,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: balanceLabel(after).color)),
              ),
            ]),
          ),
        const SizedBox(height: 20),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: C.settings),
          icon: const Icon(Icons.check),
          label: Text(t('Save')),
          onPressed: _save,
        ),
      ])),
    );
  }
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

  /// True when a reversal for this payment is already on the account.
  final bool undone;
  final VoidCallback onChanged;
  const _LedgerRow(this.e, this.customer, this.docs,
      {required this.undone, required this.onChanged});

  static const _look = {
    'sale': (Icons.point_of_sale, C.sell, 'Sale'),
    'payment': (Icons.payments, C.advance, 'Payment'),
    'return': (Icons.assignment_return, C.ret, 'Return'),
    'sale_cancelled': (Icons.cancel, Colors.grey, 'Sale cancelled'),
    'payment_cancelled': (Icons.undo, Colors.grey, 'Payment undone'),
    'opening': (Icons.history_edu, C.owe, 'Balance before this app'),
    'adjustment': (Icons.tune, C.settings, 'Adjustment'),
  };

  Future<void> _undo(BuildContext context) async {
    if (!await ask(
        context,
        '${t('Undo this payment?')} ${t('The money goes back on their account.')}',
        t('Undo'))) {
      return;
    }
    if (!context.mounted) return;
    final id = await guard(context, () => s.undoPayment(e.id));
    if (id == null || !context.mounted) return;
    toast(context, t('Payment undone'));
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final (icon, color, label) =
        _look[e.type] ?? (Icons.receipt, Colors.grey, e.type);
    Doc? doc;
    for (final d in docs) {
      if (d.id == e.refId) doc = d;
    }
    // Cash taken with a sale is part of that sale, so it is undone by
    // cancelling the sale rather than on its own.
    final canUndo = e.isPayment && doc == null && !undone;
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        leading: CircleAvatar(
            backgroundColor: color.withValues(alpha: 0.15),
            child: Icon(icon, color: color)),
        // The document number is what turns a row into something the customer
        // can be answered about — "the 4,000 on the 3rd" is Sale #12.
        title: Text('${t(label)}${doc == null ? '' : ' #${doc.no}'}',
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
            [when(e.createdAt), if (e.note.isNotEmpty) e.note].join('\n'),
            style: const TextStyle(fontSize: 13)),
        isThreeLine: e.note.isNotEmpty,
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          Text('${e.amount > 0 ? '+' : '-'}${money(e.amount.abs())}',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: e.amount > 0 ? C.owe : C.advance)),
          // Deliberately compact: a full-size IconButton is 48px wide and
          // pushes the amount off the edge of a small phone.
          if (canUndo)
            IconButton(
              icon: const Icon(Icons.undo, color: C.owe),
              iconSize: 20,
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints.tightFor(width: 32, height: 32),
              padding: EdgeInsets.zero,
              tooltip: t('Undo this payment?'),
              onPressed: () => _undo(context),
            ),
        ]),
        // A payment tied to a sale opens the sale; any other payment — taken at
        // the counter, or a cheque that finally cleared — opens its receipt.
        onTap: switch (e.type) {
          'return' => () => showReturnReceipt(context, e.refId!),
          _ when doc != null =>
            () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => DocScreen(doc!.id))),
          'payment' => () => showPaymentReceipt(context, customer, e.id),
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
  final _chequeNo = TextEditingController();
  final _bank = TextEditingController();

  bool _byCheque = false;
  DateTime _due = DateTime.now();

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    _chequeNo.dispose();
    _bank.dispose();
    super.dispose();
  }

  Future<void> _pickDue() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _due,
      // A post-dated cheque is normal here; an old one still needs entering.
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
    );
    if (picked != null && mounted) setState(() => _due = picked);
  }

  Future<void> _save() async {
    final amount = parseMoney(_amount.text) ?? 0;
    final nav = Navigator.of(context);

    if (_byCheque) {
      final id = await guard(
          context,
          () => s.saveCheque(
                customerId: widget.customer.id,
                chequeNo: _chequeNo.text,
                amount: amount,
                dueAt: _due.millisecondsSinceEpoch,
                bank: _bank.text,
                note: _note.text.trim(),
              ));
      if (id == null || !mounted) return;
      await showChequeReceipt(context, id);
      nav.pop(true);
      return;
    }

    final id = await guard(context,
        () => s.recordPayment(widget.customer.id, amount, note: _note.text.trim()));
    if (id == null || !mounted) return;
    await showPaymentReceipt(context, widget.customer, id);
    nav.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final owed = widget.customer.balance;
    final amount = parseMoney(_amount.text) ?? 0;
    final after = owed - amount;
    final color = _byCheque ? C.quote : C.buy;

    return Scaffold(
      appBar: AppBar(backgroundColor: color, title: Text(t('Payment'))),
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
        const SizedBox(height: 18),
        SegmentedButton<bool>(
          style: SegmentedButton.styleFrom(
              textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              selectedBackgroundColor: color,
              selectedForegroundColor: Colors.white),
          segments: [
            ButtonSegment(
                value: false, label: Fit(t('Cash')), icon: const Icon(Icons.payments)),
            ButtonSegment(
                value: true,
                label: Fit(t('Cheque')),
                icon: const Icon(Icons.account_balance)),
          ],
          selected: {_byCheque},
          onSelectionChanged: (v) => setState(() => _byCheque = v.first),
        ),
        const SizedBox(height: 18),
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
        if (_byCheque) ...[
          const SizedBox(height: 10),
          TextField(
            controller: _chequeNo,
            keyboardType: TextInputType.number,
            style: const TextStyle(fontSize: 20),
            decoration: InputDecoration(
                labelText: t('Cheque number'),
                prefixIcon: const Icon(Icons.tag)),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _bank,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
                labelText: t('Bank (optional)'),
                prefixIcon: const Icon(Icons.account_balance)),
          ),
          const SizedBox(height: 10),
          Card(
            child: ListTile(
              leading: const Icon(Icons.event, color: C.quote),
              title: Text(t('Date on the cheque'),
                  style: const TextStyle(fontSize: 14, color: Colors.black54)),
              subtitle: Text(onDay(_due),
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w700, color: Colors.black87)),
              trailing: const Icon(Icons.chevron_right),
              onTap: _pickDue,
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
                color: (_byCheque ? C.quote : balanceLabel(after).color)
                    .withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Flexible(
                    child: Text(t('After payment'),
                        style: const TextStyle(fontSize: 16))),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(balanceLabel(after).text,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: balanceLabel(after).color)),
                ),
              ]),
              // A cheque comes off the balance now, so the one thing left to
              // say is what happens on the day it does not clear.
              if (_byCheque) ...[
                const SizedBox(height: 4),
                Text(t('If the cheque comes back unpaid, mark it returned and the amount goes back on.'),
                    style: const TextStyle(fontSize: 13, color: Colors.black54)),
              ],
            ]),
          ),
        const SizedBox(height: 20),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: color),
          icon: const Icon(Icons.check),
          label: Text(t('Save')),
          onPressed: _save,
        ),
      ]),
    );
  }
}
