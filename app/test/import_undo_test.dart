import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:karots_trade/db.dart';
import 'package:karots_trade/files.dart';
import 'package:karots_trade/models.dart';
import 'package:karots_trade/store.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Batch;

int rs(num v) => (v * 100).round();

/// Stands in for the phone's app-private storage.
class _FakePaths extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePaths(this.dir);
  final String dir;
  @override
  Future<String?> getApplicationDocumentsPath() async => dir;
}

void main() {
  late Directory tmp;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tmp = await Directory.systemTemp.createTemp('karots-undo');
    PathProviderPlatform.instance = _FakePaths(tmp.path);
    await openDb(path: inMemoryDatabasePath);
  });
  tearDown(() async {
    await closeDb();
    await tmp.delete(recursive: true);
  });

  /// The books as they stand, in a form two databases can be compared by.
  Future<List<Object?>> shape() async => [
        (await products()).map((p) => '${p.name}:${p.stock}').toList(),
        (await customers()).map((c) => '${c.name}:${c.balance}').toList(),
        (await docs()).map((d) => '${d.no}:${d.total}').toList(),
      ];

  Future<void> realShop() async {
    await savePurchase(
        [BuyLine(name: 'Rice 5kg', cost: rs(1000), price: rs(1300), qty: 40)]);
    final c = await saveCustomer(name: 'ABC Shop', phone: '0712345678');
    final b = (await batches((await products()).single.id)).single;
    await saveDoc(customerId: c, quote: false, lines: [
      SellLine(
          productId: b.productId, batchId: b.id, name: 'Rice 5kg',
          price: rs(1300), qty: 5)
    ]);
    await recordPayment(c, rs(2000));
  }

  test('a wrong import can be put back', () async {
    await realShop();
    final mine = await shape();

    // Someone else's backup — the wrong file entirely.
    await closeDb();
    await openDb(path: inMemoryDatabasePath);
    await saveCustomer(name: 'Not my shop');
    final theirs = await exportBackup();
    await closeDb();

    // Back to the real books, then the mistake.
    await openDb(path: inMemoryDatabasePath);
    await realShop();
    expect(await shape(), mine);

    await importBackupSafely(theirs);
    expect((await customers()).single.name, 'Not my shop',
        reason: 'the wrong data really did land');
    expect(await products(), isEmpty);

    expect(await lastImportUndoPoint(), isNotNull, reason: 'a way back exists');
    await undoLastImport();

    expect(await shape(), mine, reason: 'every last row is back');
  });

  test('there is nothing to undo until an import happens', () async {
    await realShop();
    expect(await lastImportUndoPoint(), isNull);
    expect(() => undoLastImport(), throwsA(isA<Exception>()));
  });

  group('the copy the app takes by itself', () {
    test('it happens without being asked, and can be put back', () async {
      await realShop();
      final mine = await shape();

      expect(await lastAutoBackup(), isNull, reason: 'nothing yet');
      await autoBackup();
      expect(await lastAutoBackup(), isNotNull);

      // Everything goes wrong: the books are replaced with someone else's.
      await closeDb();
      await openDb(path: inMemoryDatabasePath);
      await saveCustomer(name: 'Not my shop');
      expect(await products(), isEmpty);

      await restoreAutoBackup();
      expect(await shape(), mine, reason: 'every row came back');
    });

    test('it does not take a second copy the same day', () async {
      await realShop();
      await autoBackup();
      final first = await lastAutoBackup();

      await saveCustomer(name: 'Added after the copy');
      await autoBackup();

      expect(await lastAutoBackup(), first, reason: 'the file was left alone');

      // Until enough time has passed, which is what the next start would see.
      await autoBackup(every: Duration.zero);
      expect(await lastAutoBackup(), isNot(first));
    });

    test('there is nothing to put back before the first copy', () async {
      await realShop();
      expect(() => restoreAutoBackup(), throwsA(isA<Exception>()));
    });

    test('the streamed file says exactly what the in-memory one says',
        () async {
      await realShop();
      final f = File('${tmp.path}/streamed.json');
      await writeBackup(f);

      // Same format, byte for byte, apart from the timestamp inside it.
      String strip(String s) => s.replaceAll(RegExp(r'"at":"[^"]*"'), '"at":""');
      expect(strip(await f.readAsString()),
          strip(utf8.decode(await exportBackup())));
    });
  });

  test('a broken file leaves the books alone and takes no undo point',
      () async {
    await realShop();
    final mine = await shape();

    expect(() => importBackupSafely(Uint8List.fromList('rubbish'.codeUnits)),
        throwsA(isA<Object>()));

    expect(await shape(), mine, reason: 'the import never got past parsing');
  });
}
