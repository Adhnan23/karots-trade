import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

// ---------------------------------------------------------------- money
// All money is stored as integer cents. Never use double for money.

final _grp = NumberFormat('#,##0');
final _grp2 = NumberFormat('#,##0.00');

String money(int cents) =>
    'Rs. ${cents % 100 == 0 ? _grp.format(cents ~/ 100) : _grp2.format(cents / 100)}';

/// null when the text is not a valid non-negative amount.
int? parseMoney(String s) {
  final v = double.tryParse(s.trim().replaceAll(',', ''));
  if (v == null || v < 0 || v.isNaN || v.isInfinite) return null;
  return (v * 100).round();
}

final dateFmt = DateFormat('d MMM yyyy, h:mm a');
String when(int ms) => dateFmt.format(DateTime.fromMillisecondsSinceEpoch(ms));

// ---------------------------------------------------------------- identity

const appName = 'Karots Trade';
const author = 'Adhnan';
const authorEmail = 'adhnanmsa@gmail.com';
const authorPhone = '0769626396';

/// Printed on every receipt and shown in Settings.
const credit = 'App made by $author  ·  $authorEmail  ·  $authorPhone';

// ---------------------------------------------------------------- i18n
// Keys are the English strings. Missing translation falls back to the key,
// so English always works and Tamil can be filled in gradually.

final locale = ValueNotifier<String>('en');

String t(String key) => locale.value == 'en' ? key : (_ta[key] ?? key);

const _ta = <String, String>{
  'Home': 'முகப்பு',
  'Products': 'பொருட்கள்',
  'Customers': 'வாடிக்கையாளர்கள்',
  'Buy': 'வாங்கு',
  'Sell / Quote': 'விற்பனை / மதிப்பீடு',
  'Sell': 'விற்பனை',
  'Quote': 'மதிப்பீடு',
  'History': 'வரலாறு',
  'Settings': 'அமைப்புகள்',
  'Returns': 'திரும்பப் பெறுதல்',
  'Return': 'திரும்பப் பெறு',
  'Payment': 'பணம் செலுத்து',
  'Save': 'சேமி',
  'Cancel': 'ரத்து',
  'Delete': 'நீக்கு',
  'Add': 'சேர்',
  'Edit': 'திருத்து',
  'Search': 'தேடு',
  'Name': 'பெயர்',
  'Phone': 'தொலைபேசி',
  'Quantity': 'எண்ணிக்கை',
  'Cost': 'விலை (வாங்கிய)',
  'Selling price': 'விற்பனை விலை',
  'Total': 'மொத்தம்',
  'Paid': 'செலுத்தியது',
  'Balance': 'இருப்பு',
  'Owes you': 'உங்களுக்கு தர வேண்டியது',
  'Advance': 'முன்பணம்',
  'Settled': 'தீர்க்கப்பட்டது',
  'Stock': 'இருப்பு',
  'Batch': 'தொகுதி',
  'Batches': 'தொகுதிகள்',
  'Business name': 'வணிகப் பெயர்',
  'Business phone': 'வணிக தொலைபேசி',
  'Export backup': 'காப்புப்பிரதி எடு',
  'Import backup': 'காப்புப்பிரதி மீட்டெடு',
  'Language': 'மொழி',
  'Share PDF': 'PDF பகிர்',
  'No products yet': 'பொருட்கள் இல்லை',
  'No customers yet': 'வாடிக்கையாளர்கள் இல்லை',
  'Nothing here yet': 'இதுவரை எதுவும் இல்லை',
};

// ---------------------------------------------------------------- colours
// One colour per area of the app so screens are recognisable at a glance.
class C {
  static const buy = Color(0xFF16A34A);
  static const sell = Color(0xFFF97316);
  static const products = Color(0xFF2563EB);
  static const customers = Color(0xFF9333EA);
  static const history = Color(0xFF0891B2);
  static const settings = Color(0xFF64748B);
  static const owe = Color(0xFFDC2626);
  static const advance = Color(0xFF16A34A);
  static const quote = Color(0xFFCA8A04);
  static const ret = Color(0xFFE11D48);
}

ThemeData appTheme() {
  final base = ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: C.products),
    useMaterial3: true,
  );
  return base.copyWith(
    scaffoldBackgroundColor: const Color(0xFFF6F7FB),
    appBarTheme: const AppBarTheme(
      centerTitle: false,
      elevation: 0,
      foregroundColor: Colors.white,
      titleTextStyle: TextStyle(
          fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(14))),
    ),
    cardTheme: base.cardTheme.copyWith(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(56),
        textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
  );
}

// ---------------------------------------------------------------- widgets

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title, hint;
  const EmptyState(this.icon, this.title, this.hint, {super.key});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 84, color: Colors.black26),
              const SizedBox(height: 16),
              Text(t(title),
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w700, color: Colors.black54)),
              const SizedBox(height: 6),
              Text(t(hint),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16, color: Colors.black45)),
            ],
          ),
        ),
      );
}

void toast(BuildContext c, String msg, {bool bad = false}) {
  ScaffoldMessenger.of(c)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontSize: 16)),
      backgroundColor: bad ? C.owe : Colors.black87,
      behavior: SnackBarBehavior.floating,
    ));
}

Future<bool> ask(BuildContext c, String title, String yes) async =>
    await showDialog<bool>(
      context: c,
      builder: (_) => AlertDialog(
        title: Text(title, style: const TextStyle(fontSize: 20)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false), child: Text(t('Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(yes)),
        ],
      ),
    ) ??
    false;

/// Runs [f], showing any business-rule error to the user instead of crashing.
Future<T?> guard<T>(BuildContext c, Future<T> Function() f) async {
  try {
    return await f();
  } catch (e) {
    if (c.mounted) toast(c, e.toString().replaceFirst('Exception: ', ''), bad: true);
    return null;
  }
}

/// Balance label that never leaves the user guessing which way the money goes.
({String text, Color color}) balanceLabel(int cents) {
  if (cents > 0) return (text: '${t('Owes you')} ${money(cents)}', color: C.owe);
  if (cents < 0) return (text: '${t('Advance')} ${money(-cents)}', color: C.advance);
  return (text: t('Settled'), color: Colors.black54);
}

class Money extends StatelessWidget {
  final int cents;
  final double size;
  final Color? color;
  const Money(this.cents, {this.size = 16, this.color, super.key});
  @override
  Widget build(BuildContext context) => Text(money(cents),
      style: TextStyle(
          fontSize: size, fontWeight: FontWeight.w700, color: color));
}
