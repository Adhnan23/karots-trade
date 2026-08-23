import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:karots_trade/core.dart';

/// Literals that reach `t()` indirectly, through a widget that translates its
/// own arguments (EmptyState, StatusChip, the ledger row, filter chips).
const indirect = [
  'Sale', 'Payment', 'Return', 'Sale cancelled',
  'Cancelled', 'Converted to sale', 'Waiting', 'Paid', 'Part paid', 'Not paid',
  'Everything', 'Sales', 'Quotes',
  'All time', 'Today', 'Last 7 days', 'This month', 'Choose dates',
  'Quotation', 'Purchase', 'Receipt',
  'In stock', 'Out of stock',
];

void main() {
  test('every string the app can show has a Tamil translation', () {
    final keys = <String>{...indirect};

    final call = RegExp(r"(?<![A-Za-z])t\('((?:[^'\\]|\\.)*)'\)");
    final emptyState =
        RegExp(r"EmptyState\(\s*Icons\.\w+,\s*'([^']*)',\s*'([^']*)'");

    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final src = f.readAsStringSync();
      for (final m in call.allMatches(src)) {
        keys.add(m.group(1)!);
      }
      for (final m in emptyState.allMatches(src)) {
        keys..add(m.group(1)!)..add(m.group(2)!);
      }
    }

    // Format patterns and interpolated fragments are not user prose.
    keys.removeWhere((k) =>
        k.contains(r'$') ||
        k.isEmpty ||
        RegExp(r'^[#,0.]+$').hasMatch(k) ||
        k == 'd MMM yyyy, h:mm a' ||
        k == 'தமிழ்');

    expect(keys.length, greaterThan(100), reason: 'the scan found the strings');

    final missing = keys.difference(tamilKeys).toList()..sort();
    expect(missing, isEmpty,
        reason: 'no Tamil for:\n  ${missing.join('\n  ')}');
  });

  test('Tamil labels stay short enough for a phone', () {
    locale.value = 'ta';
    // These sit in tabs, tiles and segmented buttons, where there is no room
    // to grow. Anything much longer gets shrunk or clipped on a small screen.
    for (final key in [
      'Buy', 'Sell', 'Quote', 'Stock', 'Products', 'Customers',
      'History', 'Settings', 'Sales', 'Returns', 'Purchases', 'All',
    ]) {
      expect(t(key).length, lessThanOrEqualTo(14),
          reason: '"$key" -> "${t(key)}" is too long for a tab or tile');
    }
    locale.value = 'en';
  });
}
