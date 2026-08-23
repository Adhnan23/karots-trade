import 'package:flutter/material.dart';

import '../core.dart';
import '../files.dart';
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
                    label: Text(t('Photo cards')),
                    icon: const Icon(Icons.grid_view)),
                ButtonSegment(
                    value: 'list',
                    label: Text(t('Compact list')),
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
                ButtonSegment(value: 'en', label: Text('English')),
                ButtonSegment(value: 'ta', label: Text('தமிழ்')),
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
                  await importBackup(bytes);
                  await s.loadSettings();
                  if (!context.mounted) return;
                  _name.text = s.businessName;
                  _phone.text = s.businessPhone;
                  locale.value = s.settings['language'] ?? 'en';
                  toast(context, t('Backup restored'));
                });
              },
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
          ]),
        ),
      );
}
