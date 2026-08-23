import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karots_trade/db.dart';
import 'package:karots_trade/main.dart';
import 'package:karots_trade/screens/products.dart';
import 'package:karots_trade/store.dart' as s;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Batch;

/// Real SQLite work is real async, so tests drive frames by hand instead of
/// pumpAndSettle (a spinner would keep that spinning forever).
/// Phone-sized surface: this app is never used in an 800x600 desktop window.
Future<void> phone(WidgetTester t) =>
    t.binding.setSurfaceSize(const Size(420, 900));

Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 25; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await t.pump(const Duration(milliseconds: 20)); // also advances animations
  }
}

void main() {
  setUp(() async {
    await openDb(path: inMemoryDatabasePath);
    await s.loadSettings();
  });
  tearDown(closeDb);



  testWidgets('a new product shows up without leaving the screen', (tester) async {
    await phone(tester);
    await tester.runAsync(() async {
      await tester.pumpWidget(const MaterialApp(home: ProductsScreen()));
      await settle(tester);

      await tester.tap(find.byType(FloatingActionButton));
      await settle(tester);

      await tester.enterText(find.byType(TextField).last, 'Coca-Cola 1L');
      await tester.tap(find.text('Save'));
      await settle(tester);

      expect(find.text('Coca-Cola 1L'), findsOneWidget);
    });
  });

  testWidgets('home counters refresh after coming back', (tester) async {
    await phone(tester);
    await tester.runAsync(() async {
      await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
      await settle(tester);

      await tester.tap(find.byIcon(Icons.inventory_2).first);
      await settle(tester);

      await tester.tap(find.byType(FloatingActionButton));
      await settle(tester);
      await tester.enterText(find.byType(TextField).last, 'Soap');
      await tester.tap(find.text('Save'));
      await settle(tester);

      await tester.pageBack();
      await settle(tester);

      expect(find.text('1'), findsWidgets, reason: 'product counter went up');
    });
  });
}
