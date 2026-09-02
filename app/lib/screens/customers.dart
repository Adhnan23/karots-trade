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
      case 'outstanding':
        await showOutstanding(context, c.id);
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
        // Said plainly, because it is not undoable: the account has to be
        // square to get here, but the sales still go with the person.
        if (!await ask(
            context,
            '${t('Delete')} "${c.name}"? ${t('Their sales and payments go too.')}',
            t('Delete'))) {
          return;
        }
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
                      ('outstanding', Icons.request_quote, 'Outstanding'),
                      ('statement', Icons.receipt_long, 'Full statement'),
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
                icon: const Icon(Icons.request_quote),
                label: Fit(t('What they owe')),
                onPressed: () => showOutstanding(context, c.id),
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

/// What is still to be paid — the document that gets sent to a customer to
/// chase money.
///
/// It starts at the oldest bill that is not finished with, and from there
/// shows everything: the open bills, and every payment, return and cheque that
/// has landed in between them. Bills settled long ago are left out, because a
/// customer asking "what do I owe you" is not helped by a year of paid-off
/// sales. Everything before the starting point is folded into one brought
/// forward line, so the figures still add up to the balance exactly.
Future<void> showOutstanding(BuildContext context, String customerId) async {
  final c = await s.customer(customerId);
  if (c == null || !context.mounted) return;
  final r = outstandingReceipt(
    c,
    await s.outstanding(customerId),
    await s.ledger(customerId),
    await s.docs(customerId: customerId),
    await s.cheques(customerId: customerId, status: 'pending'),
  );
  if (!context.mounted) return;
  await showReceipt(context, r);
}

/// One line of a customer document: an entry, and the balance after it as the
/// customer will read it.
typedef AccountLine = ({LedgerEntry entry, int balance});

/// The account as a customer should see it, oldest first.
///
/// A cancelled sale is two entries that cancel each other out, and so is an
/// undone payment. Both belong on the shop's own screen, where the seller needs
/// to see that a correction happened. On a document sent to a customer they are
/// noise at best — "Sale #12" followed by "Sale #12 cancelled" reads as a
/// mistake rather than as a correction — so both halves come out together, and
/// the pair nets to nothing, which is what keeps the total right.
///
/// The balance is then re-run over what is left rather than taken from the
/// stored one. That is the whole point: every printed line adds up to the one
/// below it, so nothing on the page can be argued with.
List<AccountLine> forCustomer(List<LedgerEntry> newestFirst) {
  final cancelledSales = {
    for (final e in newestFirst)
      if (e.type == 'sale_cancelled') e.refId
  };
  final undonePayments = {
    for (final e in newestFirst)
      if (e.type == 'payment_cancelled') e.refId
  };
  bool show(LedgerEntry e) => switch (e.type) {
        'sale_cancelled' || 'payment_cancelled' => false,
        'sale' => !cancelledSales.contains(e.refId),
        _ => !undonePayments.contains(e.id),
      };

  var running = 0;
  return [
    for (final e in newestFirst.reversed)
      if (show(e)) (entry: e, balance: running += e.amount)
  ];
}

/// Builds the outstanding report. Top level and free of any screen, because
/// this is the document a customer is handed to ask them for money and its
/// figures have to be checkable on their own.
Receipt outstandingReceipt(
  Customer c,
  ({List<Doc> bills, int overdue, int total}) open,
  List<LedgerEntry> entries,
  List<Doc> docs,
  List<Cheque> waiting,
) {
  final now = DateTime.now();
  final oldest = open.bills.isEmpty ? null : open.bills.first;
  final byId = {for (final d in docs) d.id: d};
  final stillOpen = {for (final d in open.bills) d.id};

  // Oldest first, cut to start at the bill that is still owed for.
  final account = forCustomer(entries);
  final from = oldest == null
      ? account.length
      : account.indexWhere((r) => r.entry.type == 'sale' && r.entry.refId == oldest.id);
  final shown = from < 0 ? account : account.sublist(from);

  // Everything before that point nets to a single figure. Taking it from the
  // running balance rather than re-adding the entries is what guarantees the
  // report ends on the same number as the account itself.
  final broughtForward =
      shown.isEmpty ? open.total : shown.first.balance - shown.first.entry.amount;

  String detail(LedgerEntry e) {
    final base = entryDetail(e, byId);
    if (e.type != 'sale' || !stillOpen.contains(e.refId)) return base;
    final by = payBy(e.createdAt);
    return '$base  ·  due ${onDay(by)}${by.isBefore(now) ? '  (overdue)' : ''}';
  }

  return Receipt(
    kind: 'Outstanding',
    no: 0,
    date: now.millisecondsSinceEpoch,
    customer: c.name,
    customerPhone: c.phone,
    reference: 'Amounts still to be paid as on ${onDay(now)}',
    statement: [
      if (broughtForward != 0)
        (
          onDayMs(shown.isEmpty ? c.createdAt : shown.first.entry.createdAt),
          'Balance brought forward',
          broughtForward,
          broughtForward
        ),
      for (final r in shown)
        (onDayMs(r.entry.createdAt), detail(r.entry), r.entry.amount, r.balance)
    ],
    totals: [
      (open.total > 0 ? 'Total to pay' : 'Nothing outstanding', open.total.abs()),
      if (open.overdue > 0) ('Of that, overdue', open.overdue),
    ],
    notes: [
      for (final h in waiting)
        'Cheque ${h.chequeNo}${h.bank.isEmpty ? '' : ' (${h.bank})'} for '
            '${money(h.amount)} is listed above and has already been taken off '
            'this total. '
            '${h.daysLeft == 0 ? 'It can be banked now.' : 'It can be banked on ${onDayMs(h.dueAt)}, ${h.daysLeft} day${h.daysLeft == 1 ? '' : 's'} from now.'}',
      if (waiting.isNotEmpty)
        'If a cheque is returned unpaid, its amount comes back onto this total.',
      if (open.total <= 0) 'This account is fully settled. Thank you.',
    ],
    footnote: 'Bills settled before the first line above are not listed. '
        'Ask for a full statement to see every payment on the account.',
  );
}

/// How one ledger entry reads on paper. English only, like every other
/// receipt: the PDF has no Tamil font.
String entryDetail(LedgerEntry e, Map<String, Doc> byId) {
  final ref = byId[e.refId];
  final tag = ref == null ? '' : ' #${ref.no}';
  return switch (e.type) {
    'sale' => 'Sale$tag',
    'sale_cancelled' => 'Sale$tag cancelled',
    'return' => 'Goods returned$tag',
    'payment' => paymentDetail(e),
    'payment_cancelled' => e.note.isEmpty ? 'Payment undone' : e.note,
    'opening' => e.note.isEmpty ? 'Balance brought forward' : e.note,
    'adjustment' => e.note.isEmpty ? 'Adjustment' : e.note,
    _ => e.type,
  };
}

/// A payment reads as whatever was typed against it — a cheque writes its own
/// number there — with how the money arrived added, unless the note has already
/// said it.
String paymentDetail(LedgerEntry e) {
  final how = e.method == 'cheque' ? '' : methodLabel(e.method);
  final base = e.note.isEmpty ? 'Payment received' : e.note;
  return how.isEmpty ? base : '$base  ·  $how';
}

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
  // Cancelled sales and undone payments are left out here too: a statement is
  // the long document, not the raw one, and the pairs it drops net to nothing.
  final account = forCustomer(entries);
  var billed = 0, paid = 0;
  for (final r in account) {
    if (r.entry.amount > 0) {
      billed += r.entry.amount;
    } else {
      paid += -r.entry.amount;
    }
  }

  String detail(LedgerEntry e) => entryDetail(e, byId);

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
        for (final r in account)
          (onDayMs(r.entry.createdAt), detail(r.entry), r.entry.amount, r.balance)
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
      footnote: 'Every entry on the account to date. Sales and payments that '
          'were cancelled are left out, along with the entries that reversed them.',
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
  final entries = await s.ledger(c.id);
  final docs = await s.docs(customerId: c.id);
  final r = paymentReceipt(c, ledgerId, entries, docs);
  if (r == null || !context.mounted) return;
  await showReceipt(context, r);
}

/// How much of the account a payment receipt carries with it.
const _paymentContext = 8;

/// The receipt for one payment, with the run-up to it.
///
/// "Paid 5,000, still owing 3,000" on its own is a figure the customer has to
/// take on trust. The same receipt with the bills and payments that led to it
/// answers the question before it is asked, which is the whole reason the
/// customer keeps the slip.
///
/// Null when the payment is no longer on the account — it was undone, and there
/// is no receipt to give for money that went back.
Receipt? paymentReceipt(
    Customer c, String ledgerId, List<LedgerEntry> entries, List<Doc> docs) {
  final account = forCustomer(entries);
  final at = account.indexWhere((r) => r.entry.id == ledgerId);
  if (at < 0) return null;

  final e = account[at].entry, after = account[at].balance;
  final byId = {for (final d in docs) d.id: d};
  final from = at - _paymentContext < 0 ? 0 : at - _paymentContext;
  final shown = account.sublist(from, at + 1);
  final broughtForward = shown.first.balance - shown.first.entry.amount;
  final how = methodLabel(e.method);

  return Receipt(
    kind: 'Payment',
    no: e.no,
    date: e.createdAt,
    customer: c.name,
    customerPhone: c.phone,
    reference: how.isEmpty ? null : 'Received by $how',
    statement: [
      if (broughtForward != 0)
        (
          onDayMs(shown.first.entry.createdAt),
          'Balance brought forward',
          broughtForward,
          broughtForward
        ),
      for (final r in shown)
        (onDayMs(r.entry.createdAt), entryDetail(r.entry, byId), r.entry.amount, r.balance)
    ],
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
    notes: [
      if (from > 0)
        'The account before ${onDayMs(shown.first.entry.createdAt)} is shown as one '
            'brought forward line. Ask for a full statement to see all of it.',
    ],
    footnote: e.note.isEmpty ? 'Received with thanks.' : e.note,
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
            [
              when(e.createdAt),
              [
                if (methodLabel(e.method).isNotEmpty) t(methodLabel(e.method)),
                if (e.note.isNotEmpty) e.note,
              ].join('   •   '),
            ].where((x) => x.isNotEmpty).join('\n'),
            style: const TextStyle(fontSize: 13)),
        isThreeLine: e.note.isNotEmpty || e.method.isNotEmpty,
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

  /// How the cash arrived. Cheques say so themselves.
  String _method = 'cash';

  /// The day the money came in. Money is often entered days late, so this can
  /// be moved back; left alone it is today, which is the normal case.
  DateTime? _taken;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    _chequeNo.dispose();
    _bank.dispose();
    super.dispose();
  }

  Future<DateTime?> _pickDay(DateTime initial, {bool future = false}) async {
    final now = DateTime.now();
    return showDatePicker(
      context: context,
      initialDate: initial,
      // A post-dated cheque is normal here; an old one still needs entering.
      firstDate: DateTime(now.year - 1),
      lastDate: future ? DateTime(now.year + 2) : now,
    );
  }

  /// Midday on the chosen day, so an entry moved back cannot land before a
  /// bill written that same morning.
  int? get _takenAt => _taken == null
      ? null
      : DateTime(_taken!.year, _taken!.month, _taken!.day, 12).millisecondsSinceEpoch;

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
                at: _takenAt,
              ));
      if (id == null || !mounted) return;
      await showChequeReceipt(context, id);
      nav.pop(true);
      return;
    }

    final id = await guard(
        context,
        () => s.recordPayment(widget.customer.id, amount,
            note: _note.text.trim(), method: _method, at: _takenAt));
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
        if (!_byCheque) ...[
          const SizedBox(height: 12),
          SegmentedButton<String>(
            style: SegmentedButton.styleFrom(
                textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                selectedBackgroundColor: color,
                selectedForegroundColor: Colors.white),
            segments: [
              ButtonSegment(
                  value: 'cash',
                  label: Fit(t('By hand')),
                  icon: const Icon(Icons.wallet)),
              ButtonSegment(
                  value: 'bank',
                  label: Fit(t('Bank')),
                  icon: const Icon(Icons.account_balance)),
            ],
            selected: {_method},
            onSelectionChanged: (v) => setState(() => _method = v.first),
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
          _DayTile(
            label: 'Date on the cheque',
            day: _due,
            color: C.quote,
            onPick: () async {
              final d = await _pickDay(_due, future: true);
              if (d != null && mounted) setState(() => _due = d);
            },
          ),
        ],
        const SizedBox(height: 10),
        // Money is often written up days after it came in, so the date can be
        // moved back. Left alone it is today, which is what usually happens.
        _DayTile(
          label: 'Date received',
          day: _taken ?? DateTime.now(),
          color: color,
          hint: _taken == null ? 'Today' : null,
          onPick: () async {
            final d = await _pickDay(_taken ?? DateTime.now());
            if (d != null && mounted) setState(() => _taken = d);
          },
        ),
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

/// A date the seller can move, shown big enough to read at a glance and to hit
/// with a thumb.
class _DayTile extends StatelessWidget {
  final String label;
  final DateTime day;
  final Color color;

  /// Shown beside the date when it is still the default — "Today", so nobody
  /// wonders whether they were meant to set something.
  final String? hint;
  final VoidCallback onPick;
  const _DayTile(
      {required this.label,
      required this.day,
      required this.color,
      required this.onPick,
      this.hint});

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          leading: Icon(Icons.event, color: color),
          title: Text(t(label),
              style: const TextStyle(fontSize: 14, color: Colors.black54)),
          subtitle: Text(
              [onDay(day), if (hint != null) '(${t(hint!)})'].join('  '),
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w700, color: Colors.black87)),
          trailing: const Icon(Icons.chevron_right),
          onTap: onPick,
        ),
      );
}
