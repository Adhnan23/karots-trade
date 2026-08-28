import 'package:flutter/material.dart';

import '../core.dart';
import '../files.dart';
import '../models.dart';
import '../store.dart' as s;
import 'history.dart' show Filters;

/// Colours a cheque by where it stands: credited and waiting on its date,
/// ready to bank, confirmed, or sent back.
({Color color, IconData icon, String label}) chequeLook(Cheque c) => switch (c) {
      _ when c.isCleared => (color: C.buy, icon: Icons.check_circle, label: 'Banked'),
      _ when c.isBounced =>
        (color: C.owe, icon: Icons.error_outline, label: 'Returned unpaid'),
      _ when c.isDue => (color: C.sell, icon: Icons.schedule, label: 'Ready to bank'),
      _ => (color: C.quote, icon: Icons.schedule, label: 'Waiting'),
    };

/// One cheque, with the two things that can happen to it. Used on the customer
/// page and in the History tab, so both offer exactly the same actions.
class ChequeCard extends StatelessWidget {
  final Cheque cheque;
  final bool showCustomer;
  final VoidCallback onChanged;
  const ChequeCard(this.cheque,
      {this.showCustomer = true, required this.onChanged, super.key});

  Future<void> _bank(BuildContext context) async {
    if (!await ask(
        context,
        '${t('Mark as banked?')} ${t('The balance already came down when you took it.')}',
        t('Mark banked'))) {
      return;
    }
    if (!context.mounted) return;
    final ok =
        await guard(context, () => s.clearCheque(cheque.id).then((_) => true));
    if (ok != true || !context.mounted) return;
    toast(context, t('Cheque banked'));
    onChanged();
  }

  Future<void> _bounce(BuildContext context) async {
    if (!await ask(
        context,
        '${t('Mark this cheque as returned unpaid?')} ${t('The amount goes back on their account.')}',
        t('Mark returned'))) {
      return;
    }
    if (!context.mounted) return;
    final ok =
        await guard(context, () => s.bounceCheque(cheque.id).then((_) => true));
    if (ok != true || !context.mounted) return;
    toast(context, t('Cheque marked returned'));
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final look = chequeLook(cheque);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(
                backgroundColor: look.color.withValues(alpha: 0.15),
                child: Icon(look.icon, color: look.color)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                    showCustomer
                        ? '${t('Cheque')} ${cheque.chequeNo}  •  ${cheque.customerName}'
                        : '${t('Cheque')} ${cheque.chequeNo}',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                Text(
                    [
                      if (cheque.bank.isNotEmpty) cheque.bank,
                      '${t('Due')} ${onDayMs(cheque.dueAt)}',
                      if (cheque.isPending && cheque.daysLeft > 0)
                        '${cheque.daysLeft} ${t(cheque.daysLeft == 1 ? 'day left' : 'days left')}',
                    ].join('  •  '),
                    style: const TextStyle(fontSize: 13, color: Colors.black54)),
              ]),
            ),
            Money(cheque.amount, color: look.color),
          ]),
          const SizedBox(height: 6),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            // The status word gives way before the receipt button does; in
            // Tamil 'returned unpaid' is a good deal longer than in English.
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                    color: look.color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12)),
                child: Text(t(look.label),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: look.color)),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.receipt_long),
              tooltip: t('Receipt'),
              onPressed: () => showChequeReceipt(context, cheque.id),
            ),
          ]),
          // Only a cheque still in play has anything left to decide. Once it is
          // banked or returned, its money has already moved and re-deciding
          // would move it twice.
          if (cheque.isPending)
            Row(children: [
              Expanded(
                child: TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: C.buy),
                  icon: const Icon(Icons.check_circle_outline),
                  label: Fit(t('Mark banked')),
                  onPressed: () => _bank(context),
                ),
              ),
              Expanded(
                child: TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: C.owe),
                  icon: const Icon(Icons.undo),
                  label: Fit(t('Mark returned')),
                  onPressed: () => _bounce(context),
                ),
              ),
            ]),
        ]),
      ),
    );
  }
}

/// Rebuilt from the stored cheque, so it can be handed over again at any time.
Future<void> showChequeReceipt(BuildContext context, String chequeId) async {
  final c = await s.oneCheque(chequeId);
  if (c == null || !context.mounted) return;
  final owing = await s.balance(c.customerId);
  if (!context.mounted) return;

  await showReceipt(
    context,
    Receipt(
      kind: 'Cheque',
      no: c.no,
      date: c.createdAt,
      customer: c.customerName,
      customerPhone: c.customerPhone,
      reference: [
        'Cheque ${c.chequeNo}',
        if (c.bank.isNotEmpty) c.bank,
        'dated ${onDayMs(c.dueAt)}',
      ].join('  ·  '),
      totals: [
        ('Cheque amount', c.amount),
        (
          // A cheque that covers more than was owed leaves an advance, which
          // happens often enough now that it credits on arrival.
          owing > 0
              ? 'Account balance'
              : owing < 0
                  ? 'Advance held'
                  : 'Account settled',
          owing.abs()
        ),
      ],
      footnote: switch (c) {
        _ when c.isCleared =>
          'Banked on ${onDayMs(c.settledAt ?? c.createdAt)}. The account has been credited.',
        _ when c.isBounced =>
          'This cheque was returned unpaid, so the amount has gone back onto the account.',
        _ =>
          'The account has been credited. Bankable from ${onDayMs(c.dueAt)}; if it is returned unpaid the amount goes back on.',
      },
    ),
  );
}

/// Cheques as a History tab. Waiting ones come first because they are the only
/// ones that still need doing something about.
class ChequesList extends StatefulWidget {
  final Filters filters;
  const ChequesList(this.filters, {super.key});
  @override
  State<ChequesList> createState() => _ChequesListState();
}

class _ChequesListState extends State<ChequesList> {
  String? _status; // null = everything
  late Future<List<Cheque>> _list = _load();

  Future<List<Cheque>> _load() => s.cheques(
      q: widget.filters.q,
      status: _status,
      from: widget.filters.from,
      to: widget.filters.to);

  void _reload() {
    if (!mounted) return;
    setState(() {
      _list = _load();
    });
  }

  @override
  void didUpdateWidget(ChequesList old) {
    super.didUpdateWidget(old);
    if (old.filters != widget.filters) _reload();
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final (label, value) in [
                ('Everything', null),
                ('Waiting', 'pending'),
                ('Banked', 'cleared'),
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(t(label)),
                    selected: _status == value,
                    selectedColor: C.history.withValues(alpha: 0.18),
                    onSelected: (_) {
                      _status = value;
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
              final rows = snap.data;
              if (rows == null) return const Center(child: CircularProgressIndicator());
              if (rows.isEmpty) {
                return EmptyState(Icons.account_balance, 'Nothing here yet',
                    'Cheques show up here.');
              }
              final waiting = rows
                  .where((c) => c.isPending)
                  .fold<int>(0, (a, c) => a + c.amount);
              return ListView(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                children: [
                  if (waiting > 0) ...[
                    _WaitingBanner(waiting),
                    const SizedBox(height: 10),
                  ],
                  for (final c in rows) ChequeCard(c, onChanged: _reload),
                ],
              );
            },
          ),
        ),
      ]);
}

class _WaitingBanner extends StatelessWidget {
  final int amount;
  const _WaitingBanner(this.amount);

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: C.quote.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(16)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t('Waiting on the bank'),
              style: const TextStyle(fontSize: 14, color: Colors.black54)),
          const SizedBox(height: 2),
          Money(amount, size: 22, color: C.quote),
          Text(t('Already taken off customer balances.'),
              style: const TextStyle(fontSize: 13, color: Colors.black54)),
        ]),
      );
}
