import 'package:flutter/material.dart';

import '../l10n.dart';

/// Asks for a backup passphrase. With [confirm] it asks twice (when creating a backup).
Future<String?> askPassphrase(BuildContext context, {bool confirm = false}) =>
    showDialog<String>(context: context, builder: (_) => _PassphraseDialog(confirm: confirm));

class _PassphraseDialog extends StatefulWidget {
  final bool confirm;
  const _PassphraseDialog({required this.confirm});

  @override
  State<_PassphraseDialog> createState() => _PassphraseDialogState();
}

class _PassphraseDialogState extends State<_PassphraseDialog> {
  final _a = TextEditingController();
  final _b = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _a.dispose();
    _b.dispose();
    super.dispose();
  }

  void _submit() {
    if (_a.text.length < 6) {
      setState(() => _error = context.tr('passphrase_short'));
    } else if (widget.confirm && _a.text != _b.text) {
      setState(() => _error = context.tr('passphrase_mismatch'));
    } else {
      Navigator.pop(context, _a.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.tr('passphrase')),
      content: SizedBox(
        width: 380,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: _a,
            obscureText: true,
            autofocus: true,
            decoration: InputDecoration(labelText: context.tr('passphrase')),
            onSubmitted: (_) => widget.confirm ? null : _submit(),
          ),
          if (widget.confirm)
            TextField(
              controller: _b,
              obscureText: true,
              decoration: InputDecoration(labelText: context.tr('passphrase_again')),
              onSubmitted: (_) => _submit(),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(context.tr('cancel'))),
        FilledButton(onPressed: _submit, child: Text(context.tr('done'))),
      ],
    );
  }
}
