import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../l10n.dart';
import '../models.dart';

/// Search-and-pick dialog over the live channels of the current list.
Future<Channel?> pickChannel(BuildContext context) => showDialog<Channel>(
      context: context,
      builder: (_) => const _Picker(),
    );

class _Picker extends StatefulWidget {
  const _Picker();

  @override
  State<_Picker> createState() => _PickerState();
}

class _PickerState extends State<_Picker> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    final q = _q.toLowerCase();
    final list = <Channel>[];
    for (final c in s.library!.items) {
      if (c.type != ContentType.live || !s.visible(c)) continue;
      if (q.isNotEmpty && !c.lower.contains(q)) continue;
      list.add(c);
      if (list.length >= 200) break; // the user refines with the search box
    }
    return AlertDialog(
      title: Text(context.tr('pick_channel')),
      content: SizedBox(
        width: 460,
        height: 460,
        child: Column(children: [
          TextField(
            autofocus: true,
            decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: context.tr('search')),
            onChanged: (v) => setState(() => _q = v.trim()),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              itemCount: list.length,
              itemExtent: 48,
              itemBuilder: (_, i) => ListTile(
                dense: true,
                title: Text(list[i].name, maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () => Navigator.pop(context, list[i]),
              ),
            ),
          ),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(context.tr('cancel')))],
    );
  }
}
