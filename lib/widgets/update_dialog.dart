import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../l10n.dart';
import '../services/updater.dart';

Future<void> showUpdateDialog(BuildContext context, UpdateInfo info) =>
    showDialog(context: context, barrierDismissible: false, builder: (_) => _UpdateDialog(info));

class _UpdateDialog extends StatefulWidget {
  final UpdateInfo info;
  const _UpdateDialog(this.info);

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  bool _busy = false;
  double _progress = 0;
  String? _error;

  Future<void> _run() async {
    final app = context.read<AppState>();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final file = await Updater.download(widget.info, app.updateSource, onProgress: (p) {
        if (mounted) setState(() => _progress = p);
      });
      await Updater.installAndExit(file);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = errorText(app.lang, e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.tr('update_available', args: {'v': widget.info.version})),
      content: SizedBox(
        width: 440,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (widget.info.notes.isNotEmpty) ...[
            Text(context.tr('whats_new'), style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(widget.info.notes),
            const SizedBox(height: 14),
          ],
          Text(context.tr('update_restart_note'), style: const TextStyle(fontSize: 12)),
          if (_busy) ...[
            const SizedBox(height: 16),
            Text(context.tr('downloading')),
            const SizedBox(height: 6),
            LinearProgressIndicator(value: _progress > 0 ? _progress : null),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text('${context.tr('update_failed')}: $_error', style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ]),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: Text(context.tr('later'))),
        FilledButton(onPressed: _busy ? null : _run, child: Text(context.tr('update_now'))),
      ],
    );
  }
}
