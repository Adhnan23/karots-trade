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

final dayFmt = DateFormat('d MMM yyyy');
String onDay(DateTime d) => dayFmt.format(d);
String onDayMs(int ms) => onDay(DateTime.fromMillisecondsSinceEpoch(ms));

/// How long a customer has to settle a bill taken on credit. Printed on the
/// receipt as a real date, because "within a week" starts an argument and
/// "by 3 Sep 2026" does not.
const creditDays = 7;

DateTime payBy(int soldAt) =>
    DateTime.fromMillisecondsSinceEpoch(soldAt).add(const Duration(days: creditDays));

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

/// Exposed so a test can prove every string the app can show has a Tamil
/// entry, rather than finding out on a customer's phone.
Set<String> get tamilKeys => _ta.keys.toSet();

/// Business-rule errors read like 'Not enough stock: Coca-Cola 1L'. Translate
/// the sentence and leave the name alone.
String tMessage(String message) {
  if (locale.value == 'en') return message;
  final cut = message.indexOf(': ');
  if (cut < 0) return t(message);
  return '${t(message.substring(0, cut))}: ${message.substring(cut + 2)}';
}

/// Kept deliberately short. A phone screen has no room for a literal
/// translation, and a clipped word is worse than a terse one.
const _ta = <String, String>{
  // Navigation and the home screen
  'Home': 'முகப்பு',
  'Products': 'பொருட்கள்',
  'Products screen': 'பொருட்கள் திரை',
  'Customers': 'வாடிக்கையாளர்',
  'Buy': 'வாங்கு',
  'Sell': 'விற்பனை',
  'Sell / Quote': 'விற்பனை / மதிப்பீடு',
  'Quote': 'மதிப்பீடு',
  'Quotes': 'மதிப்பீடுகள்',
  'Sale': 'விற்பனை',
  'Sales': 'விற்பனைகள்',
  'History': 'வரலாறு',
  'Settings': 'அமைப்புகள்',
  'stock in': 'இருப்பு சேர்',
  'or quote': 'அல்லது மதிப்பீடு',
  'OUT ON CREDIT': 'கடனில்',
  'WHO OWES YOU': 'யார் தர வேண்டும்',
  'Everyone is settled up.': 'அனைவரும் தீர்த்துவிட்டனர்.',
  'customer owes you': 'வாடிக்கையாளர் தர வேண்டும்',
  'customers owe you': 'வாடிக்கையாளர்கள் தர வேண்டும்',
  'Add a customer, then buy some stock to sell.':
      'வாடிக்கையாளரைச் சேர்த்து, பின் இருப்பு வாங்கவும்.',

  // Common actions
  'Add': 'சேர்',
  'Add item': 'பொருள் சேர்',
  'All': 'எல்லாம்',
  'Save': 'சேமி',
  'Cancel': 'ரத்து',
  'Delete': 'நீக்கு',
  'Edit': 'திருத்து',
  'Search': 'தேடு',
  'Search name or number': 'பெயர் அல்லது எண்',
  'Yes': 'ஆம்',
  'Import': 'மீட்டெடு',
  'Fix': 'சரிசெய்',
  'Not found': 'கிடைக்கவில்லை',
  'Nothing here yet': 'இதுவரை எதுவும் இல்லை',

  // Fields
  'Name': 'பெயர்',
  'Phone': 'தொலைபேசி',
  'Quantity': 'அளவு',
  'Amount': 'தொகை',
  'Cost': 'கொள்விலை',
  'Selling price': 'விற்பனை விலை',
  'Total': 'மொத்தம்',
  'Paid': 'செலுத்தியது',
  'Balance': 'நிலுவை',
  'Balance due': 'நிலுவைத் தொகை',
  'Remaining': 'மீதம்',
  'Owes you': 'தர வேண்டியது',
  'Advance': 'முன்பணம்',
  'Settled': 'தீர்ந்தது',
  'Change / advance': 'மீதம் / முன்பணம்',
  'Note (optional)': 'குறிப்பு (விருப்பம்)',
  'Photo': 'புகைப்படம்',

  // Stock
  'Stock': 'இருப்பு',
  'Batch': 'தொகுதி',
  'Batches': 'தொகுதிகள்',
  'Available': 'உள்ளது',
  'available': 'உள்ளது',
  'Only': 'மட்டும்',
  'In stock': 'இருப்பில் உள்ளது',
  'Out of stock': 'இருப்பு இல்லை',
  'no stock available': 'இருப்பு இல்லை',
  'No stock yet. Use Buy to add stock.':
      'இருப்பு இல்லை. வாங்கு மூலம் சேர்க்கவும்.',
  'No products yet': 'பொருட்கள் இல்லை',
  'No customers yet': 'வாடிக்கையாளர் இல்லை',
  'New product': 'புதிய பொருள்',
  'New customer': 'புதிய வாடிக்கையாளர்',
  'Choose product': 'பொருளைத் தேர்வு',
  'Choose customer': 'வாடிக்கையாளரைத் தேர்வு',
  'Choose batch': 'தொகுதியைத் தேர்வு',
  'Choose a customer first': 'முதலில் வாடிக்கையாளரைத் தேர்வு செய்யவும்',
  'Tap Add, or buy stock to create one.':
      'சேர் தட்டவும், அல்லது இருப்பு வாங்கவும்.',
  'Add a customer to start selling.':
      'விற்பனை தொடங்க வாடிக்கையாளரைச் சேர்க்கவும்.',
  'Add the products you bought.': 'வாங்கிய பொருட்களைச் சேர்க்கவும்.',
  'Add the products you are selling.': 'விற்கும் பொருட்களைச் சேர்க்கவும்.',
  'Show as a list': 'பட்டியலாகக் காட்டு',
  'Show as cards': 'கார்டுகளாகக் காட்டு',
  'Photo cards': 'படக் கார்டு',
  'Compact list': 'சுருக்கப் பட்டியல்',
  'Take photo': 'படம் எடு',
  'Choose from gallery': 'கேலரியில் தேர்வு',

  // Buying
  'Purchase': 'கொள்முதல்',
  'Purchases': 'கொள்முதல்கள்',
  'Purchase saved': 'கொள்முதல் சேமிக்கப்பட்டது',
  'Purchases show up here.': 'கொள்முதல்கள் இங்கே தெரியும்.',

  // Selling, quoting, status
  'Everything': 'அனைத்தும்',
  'Convert to sale': 'விற்பனையாக மாற்று',
  'Sale created': 'விற்பனை உருவானது',
  'How much did they pay?': 'எவ்வளவு செலுத்தினார்?',
  'Cancelled': 'ரத்து',
  'Converted to sale': 'விற்பனையானது',
  'Waiting': 'காத்திருக்கிறது',
  'Part paid': 'பகுதி செலுத்தியது',
  'Not paid': 'செலுத்தவில்லை',
  'Cancel sale': 'விற்பனையை ரத்து செய்',
  'Cancel quote': 'மதிப்பீட்டை ரத்து செய்',
  'Cancel this quote?': 'இந்த மதிப்பீட்டை ரத்து செய்யவா?',
  'Cancel this sale? Stock goes back and the charge is reversed.':
      'விற்பனையை ரத்து செய்யவா? இருப்பு திரும்பும், கட்டணமும் நீங்கும்.',
  'Sales and quotes show up here.':
      'விற்பனைகளும் மதிப்பீடுகளும் இங்கே தெரியும்.',
  'Includes': 'இதில்',
  'paid after the sale': 'விற்பனைக்குப் பின் செலுத்தியது',

  // Discounts
  'Discount': 'தள்ளுபடி',
  'Price each': 'ஒன்றின் விலை',
  'Normal': 'வழக்கமான',
  'Was': 'இருந்தது',
  'You saved': 'மிச்சம்',
  'Price cannot be less than the cost': 'விலை கொள்விலையை விடக் குறையக்கூடாது',
  'Price is below cost': 'விலை கொள்விலைக்கும் குறைவு',

  // Cheques
  'Cash': 'ரொக்கம்',
  'Cheque': 'காசோலை',
  'Cheques': 'காசோலைகள்',
  'Cheque number': 'காசோலை எண்',
  'Bank (optional)': 'வங்கி (விருப்பம்)',
  'Date on the cheque': 'காசோலைத் தேதி',
  'Due': 'தேதி',
  'Banked': 'வங்கியில் வந்தது',
  'Returned unpaid': 'திரும்பியது',
  'Ready to bank': 'வங்கிக்குத் தயார்',
  'Cheques waiting': 'காத்திருக்கும் காசோலை',
  'Waiting on the bank': 'வங்கியில் காத்திருப்பு',
  'waiting on cheques': 'காசோலைகளில் காத்திருப்பு',
  'Mark banked': 'வந்தது எனக் குறி',
  'Mark returned': 'திரும்பியது எனக் குறி',
  'Mark as banked?': 'வங்கியில் வந்ததா?',
  'The balance goes down now.': 'இப்போது நிலுவை குறையும்.',
  'Mark this cheque as returned unpaid?': 'இந்தக் காசோலை திரும்பியதா?',
  'Cheque banked': 'காசோலை வங்கியில் வந்தது',
  'Cheque marked returned': 'காசோலை திரும்பியது எனக் குறிக்கப்பட்டது',
  'Balance stays at': 'நிலுவை இதுவே',
  'It goes down when you mark the cheque banked.':
      'காசோலை வந்ததும் நிலுவை குறையும்.',
  'Not counted in the balance until the bank pays.':
      'வங்கி பணம் தரும் வரை நிலுவையில் சேராது.',
  'Cheques show up here.': 'காசோலைகள் இங்கே தெரியும்.',
  'Cheque number is required': 'காசோலை எண் தேவை',
  'Cheque not found': 'காசோலை கிடைக்கவில்லை',
  'This cheque is already banked': 'இந்தக் காசோலை ஏற்கனவே வங்கியில் வந்தது',
  'Only a waiting cheque can be marked returned':
      'காத்திருக்கும் காசோலையை மட்டுமே திரும்பியது எனக் குறிக்கலாம்',

  // Money in
  'Payment': 'பணம்',
  'Pay full': 'முழுவதும் செலுத்து',
  'After payment': 'செலுத்திய பின்',
  'Transaction history': 'பரிவர்த்தனை வரலாறு',
  'Sale cancelled': 'விற்பனை ரத்து',

  // Returns
  'Return': 'திரும்பப் பெறு',
  'Returns': 'திரும்பியவை',
  'Return items': 'பொருட்கள் திரும்ப',
  'Returned': 'திரும்பியது',
  'Can return': 'திரும்பலாம்',
  'How many are coming back?': 'எத்தனை திரும்புகிறது?',
  'Credit to customer': 'வாடிக்கையாளருக்கு வரவு',
  'From sale': 'விற்பனையிலிருந்து',
  'Returned items show up here.': 'திரும்பிய பொருட்கள் இங்கே தெரியும்.',

  // Corrections
  'Corrections': 'திருத்தங்கள்',
  'Fix this batch': 'இந்தத் தொகுதியைச் சரிசெய்',
  'Batch corrected': 'தொகுதி சரிசெய்யப்பட்டது',
  'Stock on the shelf now': 'இப்போதுள்ள இருப்பு',
  'Received': 'பெறப்பட்டது',
  'Gone out': 'வெளியே சென்றது',
  'What happened? (optional)': 'என்ன நடந்தது? (விருப்பம்)',
  'Miscount, damaged, typo…': 'எண்ணிக்கை தவறு, சேதம், பிழை…',
  'Sales already made keep the price they were charged.':
      'ஏற்கனவே நடந்த விற்பனைகளின் விலை மாறாது.',

  // Dates and filters
  'All time': 'எல்லா நேரமும்',
  'Today': 'இன்று',
  'Last 7 days': 'கடந்த 7 நாட்கள்',
  'This month': 'இந்த மாதம்',
  'Choose dates': 'தேதிகளைத் தேர்வு',

  // Receipts
  'Receipt': 'ரசீது',
  'Quotation': 'மதிப்பீடு',

  // Settings
  'Business name': 'வணிகப் பெயர்',
  'Business phone': 'வணிக தொலைபேசி',
  'These appear on your receipts': 'இவை ரசீதுகளில் தெரியும்',
  'Language': 'மொழி',
  'Backup': 'காப்புப்பிரதி',
  'Export backup': 'காப்புப்பிரதி சேமி',
  'Import backup': 'காப்புப்பிரதி மீட்டெடு',
  'Backup saved': 'காப்புப்பிரதி சேமிக்கப்பட்டது',
  'Backup restored': 'காப்புப்பிரதி மீட்கப்பட்டது',
  'Keeps everything, including product photos.':
      'படங்கள் உட்பட அனைத்தும் சேமிக்கப்படும்.',
  'Importing replaces everything currently in the app. Continue?':
      'இப்போதுள்ள அனைத்தும் மாற்றப்படும். தொடரவா?',
  'About': 'பற்றி',
  'App made by': 'செயலி உருவாக்கியவர்',
  'All your data stays on this phone.':
      'தகவல்கள் இந்த தொலைபேசியிலேயே இருக்கும்.',

  // Things that go wrong
  'Enter a valid amount': 'சரியான தொகையை உள்ளிடவும்',
  'Enter a valid cost': 'சரியான கொள்விலையை உள்ளிடவும்',
  'Enter a valid quantity': 'சரியான அளவை உள்ளிடவும்',
  'Enter a valid selling price': 'சரியான விற்பனை விலையை உள்ளிடவும்',
  'Quantity must be more than zero': 'அளவு பூஜ்ஜியத்தை விட அதிகமாக இருக்க வேண்டும்',
  'Product name is required': 'பொருளின் பெயர் தேவை',
  'Customer name is required': 'வாடிக்கையாளர் பெயர் தேவை',
  'Add at least one item': 'குறைந்தது ஒரு பொருளையாவது சேர்க்கவும்',
  'Prices cannot be negative': 'விலை எதிர்மறையாக இருக்கக்கூடாது',
  'Quantity cannot be negative': 'அளவு எதிர்மறையாக இருக்கக்கூடாது',
  'Payment must be more than zero': 'தொகை பூஜ்ஜியத்தை விட அதிகமாக இருக்க வேண்டும்',
  'Payment cannot be negative': 'தொகை எதிர்மறையாக இருக்கக்கூடாது',
  'Not enough stock': 'போதிய இருப்பு இல்லை',
  'This quotation was already converted or cancelled':
      'இந்த மதிப்பீடு ஏற்கனவே மாற்றப்பட்டது அல்லது ரத்தானது',
  'Quotation not found': 'மதிப்பீடு கிடைக்கவில்லை',
  'Sale not found': 'விற்பனை கிடைக்கவில்லை',
  'Batch not found': 'தொகுதி கிடைக்கவில்லை',
  'Already cancelled': 'ஏற்கனவே ரத்தானது',
  'This sale is cancelled': 'இந்த விற்பனை ரத்தானது',
  'Choose at least one item to return':
      'திரும்பப் பெற ஒரு பொருளையாவது தேர்வு செய்யவும்',
  'Item not in this sale': 'இந்தப் பொருள் இந்த விற்பனையில் இல்லை',
  'Nothing changed': 'எதுவும் மாறவில்லை',
  'This file is not a valid backup': 'இது சரியான காப்புப்பிரதி கோப்பு அல்ல',
  'Can be returned at most': 'அதிகபட்சம் திரும்பப் பெறலாம்',
  'Return quantity is too high': 'திரும்பப் பெறும் அளவு அதிகம்',
  'This product has been bought or sold and cannot be deleted':
      'இந்தப் பொருள் வாங்கப்பட்டது அல்லது விற்கப்பட்டது, நீக்க முடியாது',
  'This customer has transactions and cannot be deleted':
      'இந்த வாடிக்கையாளருக்கு பரிவர்த்தனைகள் உள்ளன, நீக்க முடியாது',
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

/// A label that shrinks instead of clipping. Tamil renders longer than
/// English, and a tab or a segmented button cannot grow to meet it.
class Fit extends StatelessWidget {
  final String text;
  const Fit(this.text, {super.key});

  @override
  Widget build(BuildContext context) => FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(text, maxLines: 1, softWrap: false),
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
    if (c.mounted) {
      toast(c, tMessage(e.toString().replaceFirst('Exception: ', '')), bad: true);
    }
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
