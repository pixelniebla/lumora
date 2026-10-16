import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../l10n.dart';

/// Asks for the PIN; returns true when it is correct (and unlocks for this session).
Future<bool> askPin(BuildContext context) async {
  final s = context.read<AppState>();
  if (!s.pinEnabled) return true;
  final ok = await showDialog<bool>(context: context, builder: (_) => _PinDialog(verify: s.verifyPin)) ?? false;
  if (ok) s.unlock();
  return ok;
}

/// Asks for a new PIN twice. Returns it, or null if cancelled.
Future<String?> askNewPin(BuildContext context) =>
    showDialog<String>(context: context, builder: (_) => const _NewPinDialog());

class _PinDialog extends StatefulWidget {
  final bool Function(String) verify;
  const _PinDialog({required this.verify});

  @override
  State<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<_PinDialog> {
  final _c = TextEditingController();
  bool _wrong = false;

  void _submit() {
    if (widget.verify(_c.text)) {
      Navigator.pop(context, true);
    } else {
      setState(() => _wrong = true);
      _c.clear();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.tr('enter_pin')),
      content: TextField(
        controller: _c,
        autofocus: true,
        obscureText: true,
        keyboardType: TextInputType.number,
        maxLength: 4,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(errorText: _wrong ? context.tr('wrong_pin') : null, counterText: ''),
        onChanged: (v) {
          if (v.length == 4) _submit();
        },
        onSubmitted: (_) => _submit(),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: Text(context.tr('cancel')))],
    );
  }
}

class _NewPinDialog extends StatefulWidget {
  const _NewPinDialog();

  @override
  State<_NewPinDialog> createState() => _NewPinDialogState();
}

class _NewPinDialogState extends State<_NewPinDialog> {
  final _a = TextEditingController();
  final _b = TextEditingController();
  bool _mismatch = false;

  @override
  void dispose() {
    _a.dispose();
    _b.dispose();
    super.dispose();
  }

  void _save() {
    if (_a.text.length == 4 && _a.text == _b.text) {
      Navigator.pop(context, _a.text);
    } else {
      setState(() => _mismatch = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    InputDecoration deco(String l) => InputDecoration(labelText: l, counterText: '');
    final fmt = [FilteringTextInputFormatter.digitsOnly];
    return AlertDialog(
      title: Text(context.tr('set_pin')),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(
            controller: _a,
            obscureText: true,
            maxLength: 4,
            keyboardType: TextInputType.number,
            inputFormatters: fmt,
            decoration: deco(context.tr('pin_label'))),
        const SizedBox(height: 8),
        TextField(
          controller: _b,
          obscureText: true,
          maxLength: 4,
          keyboardType: TextInputType.number,
          inputFormatters: fmt,
          decoration: deco(context.tr('pin_label')).copyWith(errorText: _mismatch ? context.tr('wrong_pin') : null),
          onSubmitted: (_) => _save(),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(context.tr('cancel'))),
        FilledButton(onPressed: _save, child: Text(context.tr('done'))),
      ],
    );
  }
}
