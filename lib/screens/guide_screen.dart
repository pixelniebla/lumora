import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../l10n.dart';
import '../models.dart';
import '../services/scheduler.dart';
import '../theme.dart';
import 'player_screen.dart';
import 'scheduled_screen.dart';

const _spanMinutes = 180;
const _nameWidth = 190.0;

/// Program-guide grid: channels down the side, time across the top.
class GuideScreen extends StatefulWidget {
  const GuideScreen({super.key});

  @override
  State<GuideScreen> createState() => _GuideScreenState();
}

class _GuideScreenState extends State<GuideScreen> {
  late DateTime _t0 = _roundDown(DateTime.now().subtract(const Duration(minutes: 30)));
  String? _categoryId;
  bool _onlyGuide = true;

  Object? _key;
  List<Channel> _rows = const [];

  Object? _catKey;
  List<Category> _cats = const [];

  /// Live categories only, computed once per library (not per rebuild).
  List<Category> _liveCategories(AppState s) {
    final lib = s.library!;
    final key = Object.hash(identityHashCode(lib), s.hiddenCats.length);
    if (key == _catKey) return _cats;
    final used = <String>{for (final c in lib.items) if (c.type == ContentType.live) c.categoryId};
    _catKey = key;
    return _cats = lib.categories.where((c) => used.contains(c.id) && !s.hiddenCats.contains(c.id)).toList();
  }

  static DateTime _roundDown(DateTime d) => DateTime(d.year, d.month, d.day, d.hour, d.minute < 30 ? 0 : 30);

  List<Channel> _channels(AppState s) {
    final lib = s.library!;
    final key = Object.hash(identityHashCode(lib), _categoryId, _onlyGuide, s.epg.isEmpty, s.unlocked, s.hideBroken);
    if (key == _key) return _rows;
    final rows = <Channel>[];
    for (final c in lib.items) {
      if (c.type != ContentType.live || !s.visible(c)) continue;
      if (_categoryId != null && c.categoryId != _categoryId) continue;
      if (s.hideBroken && s.broken.contains(c.id)) continue;
      if (_onlyGuide && !s.epg.hasGuide(c.epgId)) continue;
      rows.add(c);
    }
    _key = key;
    return _rows = rows;
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final rows = _channels(s);
    final cats = _liveCategories(s);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(context.tr('guide_grid')),
        actions: [
          DropdownButton<String?>(
            value: _categoryId,
            hint: Text(context.tr('category')),
            underline: const SizedBox.shrink(),
            items: [
              DropdownMenuItem(value: null, child: Text(context.tr('all'))),
              for (final c in cats) DropdownMenuItem(value: c.id, child: Text(c.name, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) async {
              if (v != null && s.isCategoryLocked(v)) return;
              setState(() => _categoryId = v);
            },
          ),
          const SizedBox(width: 12),
          FilterChip(
            label: Text(context.tr('only_with_guide')),
            selected: _onlyGuide,
            onSelected: (v) => setState(() => _onlyGuide = v),
          ),
          IconButton(
              tooltip: context.tr('prev'),
              icon: const Icon(Icons.chevron_left),
              onPressed: () => setState(() => _t0 = _t0.subtract(const Duration(hours: 1)))),
          IconButton(
              tooltip: context.tr('next'),
              icon: const Icon(Icons.chevron_right),
              onPressed: () => setState(() => _t0 = _t0.add(const Duration(hours: 1)))),
          IconButton(
              tooltip: context.tr('scheduled'),
              icon: Icon(Icons.schedule, color: s.scheduled.isEmpty ? null : kGold),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ScheduledScreen()))),
          const SizedBox(width: 12),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: kBackdrop),
        child: Column(children: [
          _timeRuler(),
          Expanded(
            child: rows.isEmpty
                ? Center(child: Text(context.tr('nothing'), style: const TextStyle(color: kMuted)))
                : ListView.builder(
                    itemCount: rows.length,
                    itemExtent: 56,
                    itemBuilder: (_, i) => _row(s, rows, i),
                  ),
          ),
        ]),
      ),
    );
  }

  Widget _timeRuler() => SizedBox(
        height: 32,
        child: Row(children: [
          const SizedBox(width: _nameWidth),
          Expanded(
            child: LayoutBuilder(
              builder: (_, box) => Stack(children: [
                for (var m = 0; m < _spanMinutes; m += 30)
                  Positioned(
                    left: box.maxWidth * m / _spanMinutes + 6,
                    top: 8,
                    child: Text(_hm(_t0.add(Duration(minutes: m))), style: const TextStyle(color: kMuted, fontSize: 12)),
                  ),
              ]),
            ),
          ),
        ]),
      );

  Widget _row(AppState s, List<Channel> rows, int i) {
    final c = rows[i];
    final t1 = _t0.add(const Duration(minutes: _spanMinutes));
    final progs = s.epg.between(c.epgId, _t0, t1);
    final now = DateTime.now();
    return Row(children: [
      SizedBox(
        width: _nameWidth,
        child: InkWell(
          onTap: () => _play(s, rows, c),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
        ),
      ),
      Expanded(
        child: LayoutBuilder(builder: (_, box) {
          double x(DateTime t) =>
              (t.difference(_t0).inSeconds / 60 / _spanMinutes).clamp(0.0, 1.0) * box.maxWidth;
          return Stack(children: [
            for (final p in progs)
              Positioned(
                left: x(p.start) + 1,
                width: (x(p.stop) - x(p.start) - 2).clamp(0, box.maxWidth),
                top: 4,
                bottom: 4,
                child: Material(
                  color: p.isOn(now) ? kEmerald.withValues(alpha: 0.28) : kSurface2,
                  borderRadius: BorderRadius.circular(8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => _programmeSheet(s, rows, c, p),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(p.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                      ),
                    ),
                  ),
                ),
              ),
            if (now.isAfter(_t0) && now.isBefore(t1))
              Positioned(left: x(now), top: 0, bottom: 0, child: Container(width: 2, color: kGold)),
          ]);
        }),
      ),
    ]);
  }

  ScheduledItem _item(ScheduleKind k, Channel c, Programme p, {DateTime? from}) => ScheduledItem(
        id: AppState.scheduleId(k, c.id, p.start),
        kind: k,
        channelId: c.id,
        channelName: c.name,
        source: c.source,
        url: c.url,
        title: p.title,
        start: from ?? p.start,
        stop: p.stop,
      );

  /// Tapping a programme: watch the channel, record it, or get a reminder.
  Future<void> _programmeSheet(AppState s, List<Channel> rows, Channel c, Programme p) async {
    final messenger = ScaffoldMessenger.of(context);
    final now = DateTime.now();
    final onAir = p.isOn(now);
    final future = p.start.isAfter(now);
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            title: Text(p.title, maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Text('${c.name} · ${_hm(p.start)} – ${_hm(p.stop)}'),
          ),
          ListTile(leading: const Icon(Icons.play_arrow), title: Text(ctx.tr('sched_watch')), onTap: () => Navigator.pop(ctx, 'watch')),
          if (onAir)
            ListTile(
                leading: const Icon(Icons.fiber_manual_record, color: Colors.redAccent),
                title: Text(ctx.tr('sched_record_now')),
                onTap: () => Navigator.pop(ctx, 'now')),
          if (future) ...[
            ListTile(
                leading: const Icon(Icons.videocam),
                title: Text(ctx.tr('sched_record')),
                onTap: () => Navigator.pop(ctx, 'record')),
            ListTile(
                leading: const Icon(Icons.notifications_active),
                title: Text(ctx.tr('sched_remind')),
                onTap: () => Navigator.pop(ctx, 'remind')),
          ],
        ]),
      ),
    );
    if (action == null || !mounted) return;
    switch (action) {
      case 'watch':
        _play(s, rows, c);
      case 'now':
        await s.addScheduled(_item(ScheduleKind.record, c, p, from: now));
      case 'record':
        await s.addScheduled(_item(ScheduleKind.record, c, p));
      case 'remind':
        await s.addScheduled(_item(ScheduleKind.remind, c, p));
    }
    if (action != 'watch') messenger.showSnackBar(SnackBar(content: Text(translate(s.lang, 'sched_added'))));
  }

  void _play(AppState s, List<Channel> rows, Channel c) {
    s.addToHistory(c);
    Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerScreen(channel: c, queue: rows)));
  }

  String _hm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
