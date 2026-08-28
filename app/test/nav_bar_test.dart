import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karots_trade/core.dart';
import 'package:karots_trade/db.dart';
import 'package:karots_trade/models.dart';
import 'package:karots_trade/screens/buy.dart';
import 'package:karots_trade/screens/customers.dart';
import 'package:karots_trade/screens/history.dart';
import 'package:karots_trade/screens/products.dart';
import 'package:karots_trade/screens/sell.dart';
import 'package:karots_trade/screens/settings.dart';
import 'package:karots_trade/store.dart' as s;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Batch;

import 'ui_test.dart' show settle;

int rs(num v) => (v * 100).round();

/// The client's phone uses three-button navigation, not gestures, so the
/// system keeps a bar across the bottom of the screen. Anything the app draws
/// under it is unreachable, and reaching for it presses Home instead.
///
/// These tests put that bar back — it is absent from a bare test surface —
/// and check that nothing you are meant to tap ends up beneath it.
const navBar = 48.0;
const screen = Size(400, 800);

void main() {
  setUp(() async {
    await openDb(path: inMemoryDatabasePath);
    await s.loadSettings();
  });
  tearDown(() async {
    locale.value = 'en';
    await closeDb();
  });

  Future<String> shop() async {
    await s.savePurchase(
        [BuyLine(name: 'Rice 5kg', cost: rs(1000), price: rs(1300), qty: 40)]);
    final c = await s.saveCustomer(name: 'Nimal Stores', phone: '0771234567');
    final b = (await s.batches((await s.products()).single.id)).single;
    await s.saveDoc(customerId: c, quote: false, lines: [
      SellLine(
          productId: b.productId, batchId: b.id, name: 'Rice 5kg',
          price: b.price, qty: 4)
    ]);
    return c;
  }

  /// Pumps [screen] with a three-button navigation bar in place.
  Future<void> withNavBar(WidgetTester t, Widget home) async {
    await t.binding.setSurfaceSize(screen);
    await t.pumpWidget(MaterialApp(
      theme: appTheme(),
      home: home,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          padding: const EdgeInsets.only(bottom: navBar),
          viewPadding: const EdgeInsets.only(bottom: navBar),
        ),
        child: child!,
      ),
    ));
    await settle(t);
  }

  /// Every button on screen has to sit clear of the system bar.
  void expectClearOfNavBar(WidgetTester t) {
    final safeBottom = screen.height - navBar;
    for (final type in [
      FilledButton,
      OutlinedButton,
      TextButton,
      FloatingActionButton,
    ]) {
      for (final e in find.byType(type).evaluate()) {
        final r = t.getRect(find.byWidget(e.widget));
        if (r.top > screen.height || r.height == 0) continue; // off-screen
        expect(r.bottom, lessThanOrEqualTo(safeBottom),
            reason: '$type at $r runs under the navigation bar');
      }
    }
  }

  testWidgets('Sell: Add item stays above the navigation bar', (t) async {
    await t.runAsync(() async {
      await shop();
      await withNavBar(t, const SellScreen());
    });
    expectClearOfNavBar(t);
  });

  testWidgets('Sell with items: Save stays above the navigation bar',
      (t) async {
    await t.runAsync(() async {
      await shop();
      await withNavBar(t, const SellScreen());
    });
    expectClearOfNavBar(t);
  });

  testWidgets('Buy: Add item stays above the navigation bar', (t) async {
    await t.runAsync(() async {
      await shop();
      await withNavBar(t, const BuyScreen());
    });
    expectClearOfNavBar(t);
  });

  testWidgets('Products: the Add button stays above the navigation bar',
      (t) async {
    await t.runAsync(() async {
      await shop();
      await withNavBar(t, const ProductsScreen());
    });
    expectClearOfNavBar(t);
  });

  testWidgets('Customers: the Add button stays above the navigation bar',
      (t) async {
    await t.runAsync(() async {
      await shop();
      await withNavBar(t, const CustomersScreen());
    });
    expectClearOfNavBar(t);
  });

  testWidgets('Customer page: the bottom of the account clears the bar',
      (t) async {
    late String cid;
    await t.runAsync(() async {
      cid = await shop();
      await withNavBar(t, CustomerScreen(cid));
    });
    await t.drag(find.byType(ListView), const Offset(0, -2000));
    await t.pump(const Duration(milliseconds: 20));
    expectClearOfNavBar(t);
  });

  testWidgets('Customer page: Edit and Delete are a tap away, not a scroll',
      (t) async {
    late String cid;
    await t.runAsync(() async {
      cid = await shop();
      // Enough history that anything below the list would be out of reach.
      for (var i = 0; i < 40; i++) {
        await s.recordPayment(cid, rs(1));
      }
      await withNavBar(t, CustomerScreen(cid));
    });

    expect(find.text('Delete'), findsNothing, reason: 'not under the history');

    await t.tap(find.byIcon(Icons.more_vert));
    await t.pumpAndSettle();

    for (final label in [
      'Outstanding', 'Full statement', 'Adjust balance', 'Edit', 'Delete'
    ]) {
      expect(find.text(label), findsOneWidget, reason: '$label is in the menu');
    }
    expectClearOfNavBar(t);
  });

  testWidgets('Adjust balance: Save stays above the navigation bar', (t) async {
    late Customer c;
    await t.runAsync(() async {
      c = (await s.customer(await shop()))!;
      await withNavBar(t, AdjustScreen(c));
    });
    expectClearOfNavBar(t);
  });

  testWidgets('Settings: the last control stays above the navigation bar',
      (t) async {
    await t.runAsync(() async {
      await withNavBar(t, const SettingsScreen());
    });
    await t.drag(find.byType(ListView), const Offset(0, -2000));
    await t.pump(const Duration(milliseconds: 20));
    expectClearOfNavBar(t);
  });

  testWidgets('History: the list clears the navigation bar', (t) async {
    await t.runAsync(() async {
      await shop();
      await withNavBar(t, const HistoryScreen());
    });
    expectClearOfNavBar(t);
  });
}
