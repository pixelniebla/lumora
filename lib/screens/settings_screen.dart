import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../l10n.dart';
import '../models.dart';
import '../services/backup.dart';
import '../services/library_cache.dart';
import '../services/log.dart';
import '../theme.dart';
import '../widgets/passphrase_dialog.dart';
import '../widgets/pin_dialog.dart';
import '../widgets/update_dialog.dart';
import 'scheduled_screen.dart';
import 'test_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    Widget section(String title) => Padding(
          padding: const EdgeInsets.fromLTRB(4, 24, 4, 8),
          child: Text(title.toUpperCase(),
              style: const TextStyle(color: kEmerald, fontWeight: FontWeight.w700, letterSpacing: 1.2, fontSize: 12)),
        );

    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.transparent, title: Text(context.tr('settings'))),
      body: Container(
        decoration: const BoxDecoration(gradient: kBackdrop),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: ListView(padding: const EdgeInsets.all(16), children: [
              section(context.tr('general')),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.language),
                  title: Text(context.tr('language')),
                  trailing: DropdownButton<String>(
                    value: s.lang,
                    underline: const SizedBox.shrink(),
                    items: [
                      for (final e in supportedLanguages.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
                    ],
                    onChanged: (v) => v == null ? null : s.setLang(v),
                  ),
                ),
              ),
              section(context.tr('player')),
              Card(
                child: Column(children: [
                  ListTile(
                    leading: const Icon(Icons.high_quality),
                    title: Text(context.tr('default_quality')),
                    trailing: DropdownButton<String>(
                      value: s.quality,
                      underline: const SizedBox.shrink(),
                      items: [
                        DropdownMenuItem(value: 'auto', child: Text(context.tr('q_auto'))),
                        DropdownMenuItem(value: 'max', child: Text(context.tr('q_max'))),
                        DropdownMenuItem(value: 'min', child: Text(context.tr('q_min'))),
                      ],
                      onChanged: (v) => v == null ? null : s.setQuality(v),
                    ),
                  ),
                  SwitchListTile(
                    secondary: const Icon(Icons.memory),
                    title: Text(context.tr('hw_accel')),
                    subtitle: Text(context.tr('hw_accel_desc')),
                    value: s.hwdec,
                    onChanged: s.setHwdec,
                  ),
                  ListTile(
                    leading: const Icon(Icons.keyboard),
                    subtitle: Text(context.tr('shortcuts')),
                  ),
                ]),
              ),
              section(context.tr('parental')),
              Card(
                child: Column(children: [
                  ListTile(
                    leading: const Icon(Icons.lock_outline),
                    title: Text(s.pinEnabled ? context.tr('change_pin') : context.tr('set_pin')),
                    subtitle: Text(context.tr('parental_desc')),
                    onTap: () async {
                      if (s.pinEnabled && !await askPin(context)) return;
                      if (!context.mounted) return;
                      final pin = await askNewPin(context);
                      if (pin != null) await s.setPin(pin);
                    },
                  ),
                  if (s.pinEnabled) ...[
                    ListTile(
                      leading: const Icon(Icons.lock_open),
                      title: Text(context.tr('remove_pin')),
                      onTap: () async {
                        if (await askPin(context)) await s.clearPin();
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.shield_outlined),
                      title: Text(context.tr('lock_adult')),
                      subtitle: Text(context.tr('locked_n', args: {'n': '${s.lockedCats.length}'})),
                      onTap: () async {
                        if (s.library == null || !await askPin(context)) return;
                        await s.autoLockAdult();
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.category_outlined),
                      title: Text(context.tr('manage_categories')),
                      onTap: () async {
                        if (s.library == null || !await askPin(context)) return;
                        if (context.mounted) {
                          showDialog(context: context, builder: (_) => const _CategoriesDialog());
                        }
                      },
                    ),
                  ],
                ]),
              ),
              section(context.tr('tools')),
              Card(
                child: Column(children: [
                  ListTile(
                    leading: const Icon(Icons.network_check),
                    title: Text(context.tr('test_channels')),
                    subtitle: Text(context.tr('test_desc')),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TestScreen())),
                  ),
                  ListTile(
                    leading: const Icon(Icons.schedule),
                    title: Text(context.tr('scheduled')),
                    subtitle: Text('${s.scheduled.length}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ScheduledScreen())),
                  ),
                  SwitchListTile(
                    secondary: const Icon(Icons.visibility_off),
                    title: Text(context.tr('hide_broken')),
                    subtitle: Text('${context.tr('hide_broken_desc')} (${s.broken.length})'),
                    value: s.hideBroken,
                    onChanged: s.setHideBroken,
                  ),
                  ListTile(
                    leading: const Icon(Icons.delete_sweep_outlined),
                    title: Text(context.tr('clear_cache')),
                    subtitle: Text(context.tr('clear_cache_desc')),
                    onTap: () async {
                      await LibraryCache.clear();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('cache_cleared'))));
                      }
                    },
                  ),
                ]),
              ),
              section(context.tr('backup')),
              Card(
                child: Column(children: [
                  ListTile(
                    leading: const Icon(Icons.upload_file),
                    title: Text(context.tr('export_backup')),
                    subtitle: Text(context.tr('backup_desc')),
                    onTap: () => _exportBackup(context, s),
                  ),
                  ListTile(
                    leading: const Icon(Icons.download),
                    title: Text(context.tr('import_backup')),
                    onTap: () => _importBackup(context, s),
                  ),
                ]),
              ),
              section(context.tr('logs')),
              Card(
                child: Column(children: [
                  ListTile(
                    leading: const Icon(Icons.bug_report_outlined),
                    title: Text(context.tr('copy_log')),
                    subtitle: Text(context.tr('logs_desc')),
                    onTap: () async {
                      final text = await Log.read();
                      await Clipboard.setData(ClipboardData(text: text));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('copied'))));
                      }
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.medical_information_outlined),
                    title: Text(context.tr('copy_diag')),
                    subtitle: Text(context.tr('copy_diag_desc')),
                    onTap: () async {
                      final text = await s.diagnostics();
                      await Clipboard.setData(ClipboardData(text: text));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('copied'))));
                      }
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.folder_open),
                    title: Text(context.tr('open_log_folder')),
                    onTap: () async {
                      final d = await Log.dir();
                      await Process.run('explorer', [d.path]);
                    },
                  ),
                ]),
              ),
              section(context.tr('updates')),
              const _UpdatesCard(),
              section(context.tr('about')),              Card(
                child: ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: Text('Lumora ${s.appVersion}'),
                  subtitle: Text(context.tr('about_text')),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

void _toast(ScaffoldMessengerState m, String msg) => m.showSnackBar(SnackBar(content: Text(msg)));

Future<void> _exportBackup(BuildContext context, AppState s) async {
  final messenger = ScaffoldMessenger.of(context);
  final pass = await askPassphrase(context, confirm: true);
  if (pass == null || !context.mounted) return;
  final bytes = await BackupCodec.encrypt(s.exportData(), pass);
  final saved = await FilePicker.saveFile(
    fileName: 'lumora-backup.lbk',
    bytes: Uint8List.fromList(bytes),
    dialogTitle: translate(s.lang, 'export_backup'),
    type: FileType.custom,
    allowedExtensions: ['lbk'],
  );
  if (saved != null) _toast(messenger, translate(s.lang, 'backup_saved'));
}

Future<void> _importBackup(BuildContext context, AppState s) async {
  final messenger = ScaffoldMessenger.of(context);
  final picked = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['lbk']);
  final path = picked.isEmpty ? null : picked.first.path;
  if (path == null || !context.mounted) return;
  final pass = await askPassphrase(context);
  if (pass == null || !context.mounted) return;
  try {
    final data = await BackupCodec.decrypt(Uint8List.fromList(await File(path).readAsBytes()), pass);
    await s.importData(data);
    _toast(messenger, translate(s.lang, 'backup_restored'));
  } catch (e) {
    _toast(messenger, errorText(s.lang, e));
  }
}

/// Per-category lock / hide switches (opened after the PIN was entered).
class _CategoriesDialog extends StatefulWidget {
  const _CategoriesDialog();

  @override
  State<_CategoriesDialog> createState() => _CategoriesDialogState();
}

class _CategoriesDialogState extends State<_CategoriesDialog> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final q = _q.toLowerCase();
    final cats = s.library!.categories.where((Category c) => q.isEmpty || c.name.toLowerCase().contains(q)).toList();
    return AlertDialog(
      title: Text(context.tr('manage_categories')),
      content: SizedBox(
        width: 520,
        height: 480,
        child: Column(children: [
          TextField(
            decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: context.tr('search')),
            onChanged: (v) => setState(() => _q = v.trim()),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              itemCount: cats.length,
              itemExtent: 48,
              itemBuilder: (_, i) {
                final c = cats[i];
                return Row(children: [
                  Expanded(child: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
                  IconButton(
                    tooltip: context.tr('lock'),
                    icon: Icon(s.lockedCats.contains(c.id) ? Icons.lock : Icons.lock_open,
                        color: s.lockedCats.contains(c.id) ? kGold : kMuted),
                    onPressed: () => s.setCategoryFlags(c.id, locked: !s.lockedCats.contains(c.id)),
                  ),
                  IconButton(
                    tooltip: context.tr('hide'),
                    icon: Icon(s.hiddenCats.contains(c.id) ? Icons.visibility_off : Icons.visibility,
                        color: s.hiddenCats.contains(c.id) ? kEmerald : kMuted),
                    onPressed: () => s.setCategoryFlags(c.id, hidden: !s.hiddenCats.contains(c.id)),
                  ),
                ]);
              },
            ),
          ),
        ]),
      ),
      actions: [FilledButton(onPressed: () => Navigator.pop(context), child: Text(context.tr('done')))],
    );
  }
}

/// Update source, manual check and automatic-check switch.
class _UpdatesCard extends StatefulWidget {
  const _UpdatesCard();

  @override
  State<_UpdatesCard> createState() => _UpdatesCardState();
}

class _UpdatesCardState extends State<_UpdatesCard> {
  late final TextEditingController _src = TextEditingController(text: context.read<AppState>().updateSource);
  String? _message;

  @override
  void dispose() {
    _src.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    final s = context.read<AppState>();
    await s.setUpdateSource(_src.text);
    final err = await s.checkUpdates();
    if (!mounted) return;
    if (err != null) {
      setState(() => _message = '${context.tr('update_failed')}: $err');
    } else if (s.updateAvailable != null) {
      setState(() => _message = null);
      await showUpdateDialog(context, s.updateAvailable!);
    } else {
      setState(() => _message = context.tr('up_to_date'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${context.tr('current_version')}: ${s.appVersion.isEmpty ? '…' : s.appVersion}'),
          const SizedBox(height: 12),
          TextField(
            controller: _src,
            decoration: InputDecoration(labelText: context.tr('update_source')),
            onSubmitted: (_) => _check(),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(context.tr('auto_check_updates')),
            value: s.autoUpdate,
            onChanged: s.setAutoUpdate,
          ),
          Row(children: [
            FilledButton.icon(
              onPressed: s.checkingUpdate ? null : _check,
              icon: s.checkingUpdate
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.system_update_alt),
              label: Text(context.tr('check_updates')),
            ),
            if (s.updateAvailable != null) ...[
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: () => showUpdateDialog(context, s.updateAvailable!),
                child: Text(context.tr('update_available', args: {'v': s.updateAvailable!.version})),
              ),
            ],
          ]),
          if (_message != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_message!)),
        ]),
      ),
    );
  }
}