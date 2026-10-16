import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../l10n.dart';
import '../models.dart';
import '../theme.dart';

class SourcesScreen extends StatelessWidget {
  const SourcesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Row(children: [
          LumoraLogo(size: 34),
          SizedBox(width: 12),
          Text('Lumora', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1)),
        ]),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: s.loading ? null : () => _addDialog(context),
        icon: const Icon(Icons.add),
        label: Text(context.tr('add_list')),
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: kBackdrop),
        child: Stack(
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 80, 16, 16),
                children: [
                  if (s.error != null)
                    Card(
                      color: Theme.of(context).colorScheme.errorContainer,
                      child: ListTile(
                        leading: const Icon(Icons.error_outline),
                        title: Text(s.error!),
                      ),
                    ),
                  if (s.sources.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 80),
                      child: Column(
                        children: [
                          const Icon(Icons.live_tv, size: 72),
                          const SizedBox(height: 16),
                          Text(context.tr('add_first')),
                          const SizedBox(height: 8),
                          Text(
                            context.tr('only_player'),
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  if (s.sources.length > 1)
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.layers, color: kGold),
                        title: Text(context.tr('all_lists')),
                        onTap: s.loading ? null : s.openAll,
                      ),
                    ),
                  for (final src in s.sources)
                    Card(
                      child: ListTile(
                        leading: Icon(src.kind == SourceKind.xtream ? Icons.cloud : Icons.list_alt),
                        title: Text(src.name),
                        subtitle: Text(src.kind == SourceKind.xtream ? 'Xtream · ${src.server}' : 'M3U'),
                        onTap: s.loading ? null : () => s.open(src),
                        trailing: IconButton(
                          tooltip: context.tr('sched_remove'),
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => s.removeSource(src),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (s.loading)
            ColoredBox(
              color: Colors.black54,
              child: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 12),
                  Text(context.tr('loading_list')),
                ]),
              ),
            ),
        ],
      ),
      ),
    );
  }

  void _addDialog(BuildContext context) {
    showDialog(context: context, builder: (_) => const _AddSourceDialog());
  }
}

class _AddSourceDialog extends StatefulWidget {
  const _AddSourceDialog();

  @override
  State<_AddSourceDialog> createState() => _AddSourceDialogState();
}

class _AddSourceDialogState extends State<_AddSourceDialog> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  final _name = TextEditingController();
  final _m3u = TextEditingController();
  final _epg = TextEditingController();
  final _server = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();

  @override
  void dispose() {
    _tabs.dispose();
    for (final c in [_name, _m3u, _epg, _server, _user, _pass]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickFile() async {
    final r = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['m3u', 'm3u8', 'txt']);
    final path = r.isEmpty ? null : r.first.path;
    if (path != null) setState(() => _m3u.text = path);
  }

  void _submit() {
    final isXtream = _tabs.index == 1;
    final name = _name.text.trim().isEmpty ? (isXtream ? _server.text.trim() : 'Mi lista') : _name.text.trim();
    final Source src;
    if (isXtream) {
      if (_server.text.trim().isEmpty || _user.text.trim().isEmpty || _pass.text.isEmpty) return;
      src = Source(
        name: name,
        kind: SourceKind.xtream,
        server: _server.text.trim(),
        username: _user.text.trim(),
        password: _pass.text,
      );
    } else {
      if (_m3u.text.trim().isEmpty) return;
      src = Source(name: name, kind: SourceKind.m3u, m3uUrl: _m3u.text.trim(), epgUrl: _epg.text.trim());
    }
    Navigator.pop(context);
    context.read<AppState>().addSource(src);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.tr('add_list')),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TabBar(controller: _tabs, tabs: const [Tab(text: 'M3U'), Tab(text: 'Xtream Codes')]),
            const SizedBox(height: 12),
            TextField(controller: _name, decoration: InputDecoration(labelText: context.tr('name_optional'))),
            SizedBox(
              height: 190,
              child: AnimatedBuilder(
                animation: _tabs,
                builder: (_, _) => _tabs.index == 0
                    ? Column(children: [
                        TextField(
                          controller: _m3u,
                          decoration: InputDecoration(
                            labelText: context.tr('m3u_src'),
                            suffixIcon: IconButton(tooltip: context.tr('open_log_folder'), icon: const Icon(Icons.folder_open), onPressed: _pickFile),
                          ),
                        ),
                        TextField(
                          controller: _epg,
                          decoration: InputDecoration(labelText: context.tr('epg_url')),
                        ),
                      ])
                    : Column(children: [
                        TextField(
                            controller: _server,
                            decoration: InputDecoration(labelText: context.tr('server'))),
                        TextField(controller: _user, decoration: InputDecoration(labelText: context.tr('username'))),
                        TextField(
                          controller: _pass,
                          obscureText: true,
                          decoration: InputDecoration(labelText: context.tr('password')),
                        ),
                      ]),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(context.tr('cancel'))),
        FilledButton(onPressed: _submit, child: Text(context.tr('add'))),
      ],
    );
  }
}
