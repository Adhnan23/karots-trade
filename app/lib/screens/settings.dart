import 'package:flutter/material.dart';

import '../core.dart';
import '../files.dart';
import '../photo.dart';
import '../store.dart' as s;

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final _name = TextEditingController(text: s.businessName);
  late final _phone = TextEditingController(text: s.businessPhone);
  bool _busy = false;

  /// When the app last replaced everything, if it ever has.
  DateTime? _undoPoint;

  @override
  void initState() {
    super.initState();
    _checkUndoPoint();
  }

  Future<void> _checkUndoPoint() async {
    // Only an offer to undo. If storage will not answer, the screen still has
    // to open — it is the one holding the backup buttons.
    DateTime? at;
    try {
      at = await lastImportUndoPoint();
    } catch (_) {
      at = null;
    }
    if (mounted) {
      setState(() {
        _undoPoint = at;
      });
    }
  }

  /// Everything an import or an undo has to refresh afterwards.
  Future<void> _afterRestore(String message) async {
    await s.loadSettings();
    if (!mounted) return;
    _name.text = s.businessName;
    _phone.text = s.businessPhone;
    locale.value = s.settings['language'] ?? 'en';
    await _checkUndoPoint();
    if (mounted) toast(context, message);
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() f) async {
    setState(() => _busy = true);
    await guard(context, () async {
      await f();
      return true;
    });
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(backgroundColor: C.settings, title: Text(t('Settings'))),
        body: AbsorbPointer(
          absorbing: _busy,
          // The list runs to the bottom of the screen, so the last control
          // would otherwise sit under the system navigation bar.
          child: SafeArea(
              child: ListView(padding: const EdgeInsets.all(16), children: [
            Text(t('These appear on your receipts'),
                style: const TextStyle(fontSize: 15, color: Colors.black54)),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              style: const TextStyle(fontSize: 18),
              decoration: InputDecoration(
                  labelText: t('Business name'), prefixIcon: const Icon(Icons.store)),
              onChanged: (v) => s.setSetting('business_name', v.trim()),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              style: const TextStyle(fontSize: 18),
              decoration: InputDecoration(
                  labelText: t('Business phone'), prefixIcon: const Icon(Icons.phone)),
              onChanged: (v) => s.setSetting('business_phone', v.trim()),
            ),
            const SizedBox(height: 16),
            Text(t('Logo'),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(t('Printed at the top of every receipt.'),
                style: const TextStyle(fontSize: 14, color: Colors.black54)),
            const SizedBox(height: 10),
            Row(children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(14)),
                clipBehavior: Clip.antiAlias,
                child: s.businessLogo == null
                    ? const Icon(Icons.storefront, size: 34, color: Colors.black38)
                    : Image.memory(s.businessLogo!, fit: BoxFit.contain),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(46),
                        foregroundColor: C.products),
                    icon: const Icon(Icons.image),
                    label: Fit(t(s.businessLogo == null ? 'Choose logo' : 'Change logo')),
                    onPressed: () => _run(() async {
                      final bytes = await pickPhoto(context);
                      if (bytes == null) return;
                      await s.setBusinessLogo(bytes);
                      setState(() {});
                    }),
                  ),
                  if (s.businessLogo != null)
                    TextButton.icon(
                      style: TextButton.styleFrom(foregroundColor: C.owe),
                      icon: const Icon(Icons.close),
                      label: Fit(t('Remove logo')),
                      onPressed: () => _run(() async {
                        await s.setBusinessLogo(null);
                        setState(() {});
                      }),
                    ),
                ]),
              ),
            ]),
            const Divider(height: 40),
            Text(t('Products screen'),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            SegmentedButton<String>(
              style: SegmentedButton.styleFrom(
                  textStyle: const TextStyle(fontSize: 16),
                  selectedBackgroundColor: C.products,
                  selectedForegroundColor: Colors.white),
              segments: [
                ButtonSegment(
                    value: 'cards',
                    label: Fit(t('Photo cards')),
                    icon: const Icon(Icons.grid_view)),
                ButtonSegment(
                    value: 'list',
                    label: Fit(t('Compact list')),
                    icon: const Icon(Icons.view_list)),
              ],
              selected: {s.productsAsCards ? 'cards' : 'list'},
              onSelectionChanged: (v) async {
                await s.setSetting('product_view', v.first);
                setState(() {});
              },
            ),
            const Divider(height: 40),
            Text(t('Language'),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            SegmentedButton<String>(
              style: SegmentedButton.styleFrom(
                  textStyle: const TextStyle(fontSize: 17),
                  selectedBackgroundColor: C.settings,
                  selectedForegroundColor: Colors.white),
              segments: const [
                ButtonSegment(value: 'en', label: Fit('English')),
                ButtonSegment(value: 'ta', label: Fit('தமிழ்')),
              ],
              selected: {locale.value},
              onSelectionChanged: (v) async {
                await s.setSetting('language', v.first);
                locale.value = v.first;
                setState(() {});
              },
            ),
            const Divider(height: 40),
            Text(t('Backup'),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(t('Keeps everything, including product photos.'),
                style: const TextStyle(fontSize: 14, color: Colors.black54)),
            const SizedBox(height: 12),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: C.buy),
              icon: const Icon(Icons.save_alt),
              label: Text(t('Export backup')),
              onPressed: () => _run(() async {
                final saved = await saveBackup();
                if (saved && context.mounted) toast(context, t('Backup saved'));
              }),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(56), foregroundColor: C.owe),
              icon: const Icon(Icons.upload_file),
              label: Text(t('Import backup'), style: const TextStyle(fontSize: 18)),
              onPressed: () async {
                if (!await ask(
                    context,
                    t('Importing replaces everything currently in the app. Continue?'),
                    t('Import'))) {
                  return;
                }
                if (!mounted) return;
                await _run(() async {
                  final bytes = await pickBackupFile();
                  if (bytes == null) return;
                  await importBackupSafely(bytes);
                  await _afterRestore(t('Backup restored'));
                });
              },
            ),
            if (_undoPoint != null) ...[
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
                  leading: const Icon(Icons.history_toggle_off, color: C.settings),
                  title: Text(t('Undo the last import'),
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600)),
                  subtitle: Text(
                      '${t('Puts back what was here on')} ${when(_undoPoint!.millisecondsSinceEpoch)}',
                      style: const TextStyle(fontSize: 13)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    if (!await ask(
                        context,
                        t('Put back the data from before the last import?'),
                        t('Undo'))) {
                      return;
                    }
                    if (!mounted) return;
                    await _run(() async {
                      await undoLastImport();
                      await _afterRestore(t('Put back'));
                    });
                  },
                ),
              ),
            ],
            const Divider(height: 40),
            Text(t('Products only'),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(t('Names and photos, without stock, prices or sales.'),
                style: const TextStyle(fontSize: 14, color: Colors.black54)),
            const SizedBox(height: 12),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: C.products),
              icon: const Icon(Icons.inventory_2),
              label: Fit(t('Export products')),
              onPressed: () => _run(() async {
                final saved = await saveProductsFile();
                if (saved && context.mounted) toast(context, t('Products saved'));
              }),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                  foregroundColor: C.products),
              icon: const Icon(Icons.playlist_add),
              label: Fit(t('Import products')),
              // No warning to give: this one only ever adds, and a name that is
              // already here is left alone.
              onPressed: () => _run(() async {
                final bytes = await pickBackupFile();
                if (bytes == null) return;
                final added = await importProducts(bytes);
                if (context.mounted) {
                  toast(context,
                      added == 0 ? t('Nothing new to add') : '$added ${t('products added')}');
                }
              }),
            ),
            const Divider(height: 40),
            Text(t('About'),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(appName,
                        style:
                            TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(t('All your data stays on this phone.'),
                        style: const TextStyle(fontSize: 13, color: Colors.black45)),
                    const SizedBox(height: 14),
                    Text(t('App made by'),
                        style: const TextStyle(
                            fontSize: 11,
                            letterSpacing: 1.4,
                            fontWeight: FontWeight.w700,
                            color: Colors.black38)),
                    const SizedBox(height: 4),
                    const Text(author,
                        style:
                            TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    const SelectableText(authorEmail,
                        style: TextStyle(fontSize: 15, color: C.products)),
                    const SelectableText(authorPhone,
                        style: TextStyle(fontSize: 15, color: C.products)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
          ])),
        ),
      );
}
