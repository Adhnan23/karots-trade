import 'package:flutter/material.dart';

import 'core.dart';
import 'db.dart';
import 'models.dart';
import 'screens/buy.dart';
import 'screens/customers.dart';
import 'screens/history.dart';
import 'screens/products.dart';
import 'screens/sell.dart';
import 'screens/settings.dart';
import 'store.dart' as s;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const Boot());
}

class Boot extends StatefulWidget {
  const Boot({super.key});
  @override
  State<Boot> createState() => _BootState();
}

class _BootState extends State<Boot> {
  // Held in a field so a rebuild never reopens the database.
  late final Future<void> _ready = _init();

  Future<void> _init() async {
    await openDb();
    await s.loadSettings();
    locale.value = s.settings['language'] ?? 'en';
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
        future: _ready,
        builder: (_, snap) {
          if (snap.hasError) {
            return MaterialApp(
              home: Scaffold(
                body: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.error_outline, size: 72, color: C.owe),
                      const SizedBox(height: 12),
                      const Text('Could not open the database',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Text('${snap.error}', textAlign: TextAlign.center),
                    ]),
                  ),
                ),
              ),
            );
          }
          if (snap.connectionState != ConnectionState.done) {
            return const MaterialApp(
                home: Scaffold(body: Center(child: CircularProgressIndicator())));
          }
          return ValueListenableBuilder(
            valueListenable: locale,
            builder: (_, _, _) => MaterialApp(
              title: 'Karots Trade',
              debugShowCheckedModeBanner: false,
              theme: appTheme(),
              home: const HomeScreen(),
            ),
          );
        },
      );
}

typedef Stats = ({
  int products,
  int stock,
  int customers,
  int owed,
  int cheques,
  int sales
});

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  late Future<(Stats, List<Customer>)> _data = _load();

  Future<(Stats, List<Customer>)> _load() async => (await s.stats(), await s.debtors());

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Coming back from another app can mean the numbers moved.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _reload();
  }

  void _reload() {
    if (!mounted) return;
    setState(() {
      _data = _load();
    });
  }

  Future<void> _go(Widget page) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final name = s.businessName.isEmpty ? 'Karots Trade' : s.businessName;
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async => _reload(),
          child: FutureBuilder(
            future: _data,
            builder: (_, snap) {
              final stats = snap.data?.$1;
              final debtors = snap.data?.$2 ?? const <Customer>[];
              return ListView(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
                children: [
                  Row(children: [
                    Expanded(
                      child: Text(name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 20, fontWeight: FontWeight.w700, height: 1.1)),
                    ),
                    IconButton(
                      iconSize: 26,
                      icon: const Icon(Icons.settings, color: C.settings),
                      onPressed: () => _go(const SettingsScreen()),
                    ),
                  ]),
                  const SizedBox(height: 6),

                  // The one number this business actually runs on.
                  _OwedCard(
                    owed: stats?.owed,
                    people: debtors.length,
                    cheques: stats?.cheques ?? 0,
                    onTap: () => _go(const CustomersScreen()),
                    onCheques: () => _go(const HistoryScreen()),
                  ),
                  const SizedBox(height: 12),

                  Row(children: [
                    Expanded(
                      child: _Action(t('Buy'), t('stock in'), Icons.add_shopping_cart,
                          C.buy, () => _go(const BuyScreen())),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _Action(t('Sell'), t('or quote'), Icons.point_of_sale,
                          C.sell, () => _go(const SellScreen())),
                    ),
                  ]),
                  const SizedBox(height: 12),

                  // Two across rather than four: a shopkeeper reads these at
                  // arm's length, and four in a row leaves nothing legible.
                  Row(children: [
                    _Tile(t('Products'), '${stats?.products ?? '–'}', Icons.inventory_2,
                        C.products, () => _go(const ProductsScreen())),
                    const SizedBox(width: 12),
                    _Tile(t('Stock'), '${stats?.stock ?? '–'}', Icons.layers, C.buy,
                        () => _go(const ProductsScreen())),
                  ]),
                  const SizedBox(height: 12),
                  Row(children: [
                    _Tile(t('Customers'), '${stats?.customers ?? '–'}', Icons.people,
                        C.customers, () => _go(const CustomersScreen())),
                    const SizedBox(width: 12),
                    _Tile(t('History'), '${stats?.sales ?? '–'}', Icons.receipt_long, C.history,
                        () => _go(const HistoryScreen())),
                  ]),
                  const SizedBox(height: 20),

                  if (debtors.isNotEmpty) ...[
                    Row(children: [
                      Text(t('WHO OWES YOU'),
                          style: const TextStyle(
                              fontSize: 11,
                              letterSpacing: 1.6,
                              fontWeight: FontWeight.w700,
                              color: Colors.black45)),
                      const Spacer(),
                      TextButton(
                        onPressed: () => _go(const CustomersScreen()),
                        child: Text(t('All')),
                      ),
                    ]),
                    for (final c in debtors)
                      _DebtorRow(c, onTap: () => _go(CustomerScreen(c.id))),
                  ] else if (stats != null && stats.customers == 0) ...[
                    const SizedBox(height: 20),
                    Center(
                      child: Text(t('Add a customer, then buy some stock to sell.'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 15, color: Colors.black45)),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Hero: outstanding money, set in tabular figures so the digits line up the
/// way they would in a bill book.
class _OwedCard extends StatelessWidget {
  final int? owed;
  final int people, cheques;
  final VoidCallback onTap, onCheques;
  const _OwedCard(
      {required this.owed,
      required this.people,
      required this.cheques,
      required this.onTap,
      required this.onCheques});

  @override
  Widget build(BuildContext context) => Material(
        color: const Color(0xFF181C2E),
        borderRadius: BorderRadius.circular(22),
        child: Column(children: [
          InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t('OUT ON CREDIT'),
                    style: const TextStyle(
                        fontSize: 11,
                        letterSpacing: 1.8,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF8B93B5))),
                const SizedBox(height: 6),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(owed == null ? '—' : money(owed!),
                      style: const TextStyle(
                        fontSize: 40,
                        height: 1.0,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: -1,
                        fontFeatures: [FontFeature.tabularFigures()],
                      )),
                ),
                const SizedBox(height: 6),
                Text(
                    owed == null
                        ? ''
                        : owed == 0
                            ? t('Everyone is settled up.')
                            : '$people ${t(people == 1 ? 'customer owes you' : 'customers owe you')}',
                    style: const TextStyle(fontSize: 14, color: Color(0xFFB6BCD4))),
              ]),
            ),
          ),
          // Already inside the figure above — this line says how much of it is
          // riding on cheques the bank has not confirmed yet.
          if (cheques > 0)
            InkWell(
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(22)),
              onTap: onCheques,
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: Color(0xFF2C3149))),
                ),
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
                child: Row(children: [
                  const Icon(Icons.account_balance, size: 18, color: Color(0xFF8B93B5)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(t('waiting on cheques'),
                        style:
                            const TextStyle(fontSize: 13, color: Color(0xFFB6BCD4))),
                  ),
                  Text(money(cheques),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        fontFeatures: [FontFeature.tabularFigures()],
                      )),
                ]),
              ),
            ),
        ]),
      );
}

class _Action extends StatelessWidget {
  final String label, hint;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _Action(this.label, this.hint, this.icon, this.color, this.onTap);

  @override
  Widget build(BuildContext context) => Material(
        color: color,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(icon, size: 30, color: Colors.white),
              const SizedBox(height: 14),
              Text(label,
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white)),
              Text(hint,
                  style: const TextStyle(fontSize: 13, color: Color(0xCCFFFFFF))),
            ]),
          ),
        ),
      );
}

class _Tile extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _Tile(this.label, this.value, this.icon, this.color, this.onTap);

  @override
  Widget build(BuildContext context) => Expanded(
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            // A fixed height so a tile with a number and one without still sit
            // level next to each other.
            child: SizedBox(
              height: 92,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
                child: Row(children: [
                  Icon(icon, size: 34, color: color),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (value.isNotEmpty)
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(value,
                                maxLines: 1,
                                style: TextStyle(
                                  fontSize: 28,
                                  height: 1.1,
                                  fontWeight: FontWeight.w800,
                                  color: color,
                                  fontFeatures: const [FontFeature.tabularFigures()],
                                )),
                          ),
                        // Tamil labels run longer than English; shrinking to
                        // fit beats a word cut off mid-letter.
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(label,
                              maxLines: 1,
                              softWrap: false,
                              style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.black54)),
                        ),
                      ],
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      );
}

class _DebtorRow extends StatelessWidget {
  final Customer c;
  final VoidCallback onTap;
  const _DebtorRow(this.c, {required this.onTap});

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              Expanded(
                child: Text(c.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
              Text(money(c.balance),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: C.owe,
                    fontFeatures: [FontFeature.tabularFigures()],
                  )),
            ]),
          ),
        ),
      );
}
