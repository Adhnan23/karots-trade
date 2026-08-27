import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karots_trade/core.dart';
import 'package:karots_trade/db.dart';
import 'package:karots_trade/main.dart';
import 'package:karots_trade/models.dart';
import 'package:karots_trade/screens/customers.dart';
import 'package:karots_trade/screens/history.dart';
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
      first ??= c;
      await s.saveDoc(customerId: c, quote: false, lines: [
        SellLine(
            productId: b.productId,
            batchId: b.id,
            name: 'Rice 5kg',
            price: b.price - rs(50), // a discount, so that row renders too
            listPrice: b.price,
            qty: qty)
      ]);
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
        expect(find.text('Rs. 19,000'), findsOneWidget, reason: 'owed total');
        expect(find.byType(HomeScreen), findsOneWidget);
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
