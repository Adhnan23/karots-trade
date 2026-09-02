import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karots_trade/core.dart';
import 'package:karots_trade/db.dart';
import 'package:karots_trade/main.dart';
import 'package:karots_trade/models.dart';
import 'package:karots_trade/screens/customers.dart';
import 'package:karots_trade/screens/history.dart';
import 'package:karots_trade/screens/products.dart';
import 'package:karots_trade/screens/sell.dart';
import 'package:karots_trade/store.dart' as s;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Batch;

import 'ui_test.dart' show settle;

int rs(num v) => (v * 100).round();

/// Screens are built for a phone held at arm's length, in a language whose
/// words run longer than the English ones they were laid out with. Anything
/// that overflows throws during a pump, so simply rendering every main screen
/// on a small screen in Tamil is the check.
void main() {
  setUp(() async {
    await openDb(path: inMemoryDatabasePath);
    await s.loadSettings();
    await s.setSetting('business_name', 'Karots Traders');
  });
  tearDown(() async {
    locale.value = 'en';
    await closeDb();
  });

  Future<String> shop() async {
    await s.savePurchase([
      BuyLine(name: 'Rice 5kg', cost: rs(1000), price: rs(1300), qty: 40),
      BuyLine(name: 'Coca-Cola 1L', cost: rs(150), price: rs(180), qty: 96),
    ]);
    final b = (await s.batches((await s.products(q: 'Rice')).single.id)).single;
    String? first;
    for (final (name, qty) in [('Nimal Stores', 4), ('ABC Trading', 12)]) {
      final c = await s.saveCustomer(name: name, phone: '0771234567');
      final sale = await s.saveDoc(customerId: c, quote: false, lines: [
        SellLine(
            productId: b.productId,
            batchId: b.id,
            name: 'Rice 5kg',
            price: b.price - rs(50), // a discount, so that row renders too
            listPrice: b.price,
            qty: qty)
      ]);
      // The first customer's bill is old enough to be late, so the screens
      // that call that out have something to draw.
      if (first == null) {
        final at = DateTime.now()
            .subtract(const Duration(days: 20))
            .millisecondsSinceEpoch;
        await db.update('docs', {'created_at': at},
            where: 'id = ?', whereArgs: [sale]);
        await db.update('ledger', {'created_at': at},
            where: 'ref_id = ?', whereArgs: [sale]);
      }
      first ??= c;
      await s.recordPayment(c, rs(500));
      await s.saveCheque(
          customerId: c, chequeNo: '400123', bank: 'Sampath', amount: rs(2500),
          dueAt: DateTime.now().millisecondsSinceEpoch);
    }
    return first!;
  }

  // A small phone and a very small one; both are sold in Sri Lanka.
  for (final size in [const Size(420, 900), const Size(320, 640)]) {
    for (final lang in ['en', 'ta']) {
      testWidgets('home fits ${size.width.toInt()}px in $lang', (t) async {
        await t.binding.setSurfaceSize(size);
        await t.runAsync(() async {
          await shop();
          locale.value = lang;
          await t.pumpWidget(
              MaterialApp(theme: appTheme(), home: const HomeScreen()));
          await settle(t);
        });

        expect(tester_(t), isEmpty, reason: 'nothing overflowed');
        expect(find.text('Rs. 14,000'), findsOneWidget,
            reason: 'owed total, with both cheques already credited');
        expect(find.byType(HomeScreen), findsOneWidget);

        // The late-payer section is below the fold on a small phone, and a
        // ListView does not build what it cannot show.
        await t.runAsync(() async {
          await t.drag(find.byType(ListView).first, const Offset(0, -500));
          await settle(t);
        });
        expect(tester_(t), isEmpty, reason: 'nor further down the page');
        expect(find.byIcon(Icons.alarm), findsOneWidget,
            reason: 'the customer whose bill ran past its date');
      });

      testWidgets('products fits ${size.width.toInt()}px in $lang', (t) async {
        await t.binding.setSurfaceSize(size);
        await t.runAsync(() async {
          await shop();
          locale.value = lang;
          await t.pumpWidget(
              MaterialApp(theme: appTheme(), home: const ProductsScreen()));
          await settle(t);
        });

        expect(tester_(t), isEmpty, reason: 'nothing overflowed');
        // Both stock figures side by side is the row most likely to run out
        // of width: two long Tamil labels over two big numbers.
        // 24 rice at 1,000 and 96 bottles at 150 are still on the shelf.
        expect(find.text('Rs. 38,400'), findsOneWidget, reason: 'what it cost');
        expect(find.text('Rs. 48,480'), findsOneWidget, reason: 'what it sells for');
      });

      testWidgets('selling to a late payer fits ${size.width.toInt()}px in $lang',
          (t) async {
        await t.binding.setSurfaceSize(size);
        late Customer c;
        await t.runAsync(() async {
          c = (await s.customer(await shop()))!;
          locale.value = lang;
          await t.pumpWidget(
              MaterialApp(theme: appTheme(), home: SellScreen(customer: c)));
          await settle(t);
        });

        expect(tester_(t), isEmpty, reason: 'nothing overflowed');
        expect(find.byIcon(Icons.warning_amber), findsOneWidget,
            reason: 'they already owe, and some of it is late');
      });

      testWidgets('giving money back fits ${size.width.toInt()}px in $lang',
          (t) async {
        await t.binding.setSurfaceSize(size);
        late Customer c;
        await t.runAsync(() async {
          c = (await s.customer(await shop()))!;
          locale.value = lang;
          await t.pumpWidget(
              MaterialApp(theme: appTheme(), home: PaymentScreen(c, out: true)));
          await settle(t);
        });

        expect(tester_(t), isEmpty, reason: 'nothing overflowed');
        expect(find.byType(SegmentedButton<bool>), findsNothing,
            reason: 'no cheque to take in when money is going out');
        expect(find.byType(SegmentedButton<String>), findsOneWidget);
      });

      testWidgets('customer page fits ${size.width.toInt()}px in $lang',
          (t) async {
        await t.binding.setSurfaceSize(size);
        late String cid;
        await t.runAsync(() async {
          cid = await shop();
          locale.value = lang;
          await t.pumpWidget(
              MaterialApp(theme: appTheme(), home: CustomerScreen(cid)));
          await settle(t);
        });

        expect(tester_(t), isEmpty, reason: 'nothing overflowed');
        // The waiting cheque and its two actions are all reachable.
        expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
        expect(find.byIcon(Icons.undo), findsWidgets);
      });

      testWidgets('adjust balance fits ${size.width.toInt()}px in $lang',
          (t) async {
        await t.binding.setSurfaceSize(size);
        late Customer c;
        await t.runAsync(() async {
          c = (await s.customer(await shop()))!;
          locale.value = lang;
          await t.pumpWidget(
              MaterialApp(theme: appTheme(), home: AdjustScreen(c)));
          await settle(t);
        });

        expect(tester_(t), isEmpty, reason: 'nothing overflowed');
        expect(find.byType(SegmentedButton<bool>), findsOneWidget,
            reason: 'owes more / owes less');
      });

      testWidgets('payment fits ${size.width.toInt()}px in $lang', (t) async {
        await t.binding.setSurfaceSize(size);
        late Customer c;
        await t.runAsync(() async {
          c = (await s.customer(await shop()))!;
          locale.value = lang;
          await t.pumpWidget(
              MaterialApp(theme: appTheme(), home: PaymentScreen(c)));
          await settle(t);
        });

        expect(tester_(t), isEmpty, reason: 'nothing overflowed');
        // Cash or cheque, and — for cash — by hand or by bank.
        expect(find.byType(SegmentedButton<bool>), findsOneWidget);
        expect(find.byType(SegmentedButton<String>), findsOneWidget);
        // The one date tile on a cash payment: when the money came in.
        expect(find.byIcon(Icons.event), findsOneWidget);
      });

      testWidgets('history fits ${size.width.toInt()}px in $lang', (t) async {
        await t.binding.setSurfaceSize(size);
        await t.runAsync(() async {
          await shop();
          locale.value = lang;
          await t.pumpWidget(
              const MaterialApp(home: HistoryScreen()));
          await settle(t);
        });

        expect(tester_(t), isEmpty, reason: 'four tabs still fit');
      });
    }
  }
}

/// Any exception Flutter recorded while laying the screen out — an overflow
/// reports itself this way rather than by failing the pump.
List<Object> tester_(WidgetTester t) {
  final errors = <Object>[];
  while (true) {
    final e = t.takeException();
    if (e == null) break;
    errors.add(e as Object);
  }
  return errors;
}
