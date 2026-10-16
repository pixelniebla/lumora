import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../l10n.dart';
import '../models.dart';
import '../services/channel_checker.dart';
import '../services/log.dart';
import '../theme.dart';

/// Checks every channel of the active list one by one and marks the dead ones.
class TestScreen extends StatefulWidget {
  const TestScreen({super.key});

  @override
  State<TestScreen> createState() => _TestScreenState();
}

class _TestScreenState extends State<TestScreen> {
  final _checker = ChannelChecker();
  final _results = <CheckResult>[];
  StreamSubscription<CheckResult>? _sub;
  bool _running = false;
  bool _onlyProblems = true;
  bool _allTypes = false;
  int _concurrency = 2;
  int _total = 0;

  @override
  void dispose() {
    _checker.cancel();
    _sub?.cancel();
    super.dispose();
  }

  void _start(AppState s) {
    final items = s.library!.items
        .where((c) => (_allTypes || c.type == ContentType.live) && !c.url.startsWith('series:'))
        .toList();
    setState(() {
      _results.clear();
      _total = items.length;
      _running = true;
    });
    _sub = _checker.run(items, concurrency: _concurrency).listen(
      (r) => setState(() => _results.add(r)),
      onDone: () {
        if (!mounted) return;
        setState(() => _running = false);
        _saveBroken(s);
      },
    );
  }

  /// Merges this (maybe partial) run into the saved broken set instead of replacing it.
  void _saveBroken(AppState s) => s.updateBroken(
        tested: {for (final r in _results) r.channel.id},
        failed: {for (final r in _results) if (r.status == CheckStatus.failed) r.channel.id});

  void _stop(AppState s) {
    _checker.cancel();
    _sub?.cancel();
    setState(() => _running = false);
    _saveBroken(s);
  }

  int _count(CheckStatus st) => _results.where((r) => r.status == st).length;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final shown = _results.where((r) => !_onlyProblems || r.status != CheckStatus.ok).toList().reversed.toList();

    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.transparent, title: Text(context.tr('test_channels'))),
      body: Container(
        decoration: const BoxDecoration(gradient: kBackdrop),
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(context.tr('testing_note'), style: const TextStyle(color: kMuted)),
                const SizedBox(height: 12),
                Wrap(spacing: 20, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('${context.tr('connections')}: '),
                    DropdownButton<int>(
                      value: _concurrency,
                      items: [for (final n in [1, 2, 4, 8]) DropdownMenuItem(value: n, child: Text('$n'))],
                      onChanged: _running ? null : (v) => setState(() => _concurrency = v ?? 2),
                    ),
                  ]),
                  FilterChip(
                    label: Text(context.tr('show_all')),
                    selected: _allTypes,
                    onSelected: _running ? null : (v) => setState(() => _allTypes = v),
                  ),
                  FilledButton.icon(
                    onPressed: _running ? () => _stop(s) : () => _start(s),
                    icon: Icon(_running ? Icons.stop : Icons.play_arrow),
                    label: Text(context.tr(_running ? 'stop' : 'start_test')),
                  ),
                ]),
                Text(context.tr('connections_hint'), style: const TextStyle(color: kMuted, fontSize: 12)),
                if (_total > 0) ...[
                  const SizedBox(height: 14),
                  LinearProgressIndicator(value: _total == 0 ? 0 : _results.length / _total),
                  const SizedBox(height: 8),
                  Row(children: [
                    Text('${context.tr('tested')}: ${_results.length}/$_total'),
                    const Spacer(),
                    _chip(context.tr('ok'), _count(CheckStatus.ok), kEmerald),
                    _chip(context.tr('slow'), _count(CheckStatus.slow), kGold),
                    _chip(context.tr('failed'), _count(CheckStatus.failed), Colors.redAccent),
                  ]),
                ],
              ]),
            ),
          ),
          Row(children: [
            FilterChip(
              label: Text(context.tr('only_problems')),
              selected: _onlyProblems,
              onSelected: (v) => setState(() => _onlyProblems = v),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: _results.any((r) => r.status == CheckStatus.failed)
                  ? () {
                      final text = _results
                          .where((r) => r.status == CheckStatus.failed)
                          .map((r) => '${r.channel.name}\t${detailText(s.lang, r.detail)}\t${Log.redact(r.channel.url)}')
                          .join('\n');
                      Clipboard.setData(ClipboardData(text: text));
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('copied'))));
                    }
                  : null,
              icon: const Icon(Icons.copy),
              label: Text(context.tr('export_failed')),
            ),
          ]),
          Expanded(
            child: ListView.builder(
              itemCount: shown.length,
              itemBuilder: (_, i) {
                final r = shown[i];
                final color = switch (r.status) {
                  CheckStatus.ok => kEmerald,
                  CheckStatus.slow => kGold,
                  CheckStatus.failed => Colors.redAccent,
                };
                return ListTile(
                  dense: true,
                  leading: Icon(
                      r.status == CheckStatus.failed ? Icons.error : (r.status == CheckStatus.slow ? Icons.hourglass_bottom : Icons.check_circle),
                      color: color),
                  title: Text(r.channel.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text('${detailText(s.lang, r.detail)} · ${r.ms} ms', style: TextStyle(color: color)),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }

  Widget _chip(String label, int n, Color c) => Padding(
        padding: const EdgeInsets.only(left: 14),
        child: Text('$label: $n', style: TextStyle(color: c, fontWeight: FontWeight.w700)),
      );
}
