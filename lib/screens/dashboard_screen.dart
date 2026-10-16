import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../l10n.dart';
import '../models.dart';
import '../theme.dart';
import 'browse_screen.dart';
import 'guide_screen.dart';
import 'multiview_screen.dart';
import 'settings_screen.dart';
import '../widgets/update_dialog.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Object? _countKey;
  List<int> _counts = const [0, 0, 0];

  /// Counting 50k items on every rebuild is wasteful: do it once per library.
  List<int> _count(LoadedLibrary lib) {
    if (_countKey == lib) return _counts;
    var l = 0, m = 0, s = 0;
    for (final c in lib.items) {
      switch (c.type) {
        case ContentType.live:
          l++;
        case ContentType.movie:
          m++;
        case ContentType.series:
          s++;
      }
    }
    _countKey = lib;
    return _counts = [l, m, s];
  }

  void _go(BrowseMode m) => Navigator.push(context, MaterialPageRoute(builder: (_) => BrowseScreen(mode: m)));
  void _push(Widget w) => Navigator.push(context, MaterialPageRoute(builder: (_) => w));

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final lib = s.library;
    if (lib == null) return const SizedBox.shrink();
    final n = _count(lib);
    final continueCount = s.continueWatching().length;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: kBackdrop),
        padding: const EdgeInsets.fromLTRB(40, 28, 40, 28),
        child: Column(
          children: [
            Row(children: [
              const LumoraLogo(size: 52),
              const SizedBox(width: 14),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Lumora', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: 1)),
                Row(children: [
                  Text(
                    '${context.tr('list')}: ${s.merged ? context.tr('all_lists') : s.activeName}',
                    style: const TextStyle(color: kMuted, fontSize: 13),
                  ),
                  if (s.refreshing) ...[
                    const SizedBox(width: 10),
                    const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
                    const SizedBox(width: 6),
                    Text(context.tr('refreshing'), style: const TextStyle(color: kMuted, fontSize: 12)),
                  ],
                ]),
              ]),
              const Spacer(),
              _Clock(lang: s.lang),
            ]),
            const Spacer(),
            Row(
              children: [
                _BigTile(context.tr('live'), context.tr('n_channels', args: {'n': '${n[0]}'}), Icons.live_tv_rounded,
                    const [Color(0xFF19E3A1), Color(0xFF0A8F73)], () => _go(BrowseMode.live)),
                const SizedBox(width: 24),
                _BigTile(context.tr('movies'), context.tr('n_titles', args: {'n': '${n[1]}'}),
                    Icons.movie_creation_rounded, const [Color(0xFFFFC857), Color(0xFFD9822B)], () => _go(BrowseMode.movie)),
                const SizedBox(width: 24),
                _BigTile(context.tr('series'), context.tr('n_series', args: {'n': '${n[2]}'}),
                    Icons.video_library_rounded, const [Color(0xFF4FC3F7), Color(0xFF2468C9)], () => _go(BrowseMode.series)),
              ],
            ),
            const Spacer(),
            Wrap(spacing: 14, runSpacing: 12, alignment: WrapAlignment.center, children: [
              if (s.updateAvailable != null)
                _SmallButton(Icons.system_update_alt, context.tr('update_available', args: {'v': s.updateAvailable!.version}),
                    () => showUpdateDialog(context, s.updateAvailable!)),
              if (continueCount > 0)
                _SmallButton(Icons.play_circle_rounded, '${context.tr('continue_watching')} ($continueCount)',
                    () => _go(BrowseMode.continueWatching)),
              _SmallButton(Icons.calendar_view_week_rounded, context.tr('guide_grid'), () => _push(const GuideScreen())),
              _SmallButton(Icons.grid_view_rounded, context.tr('multiview'), () => _push(const MultiviewScreen())),
              _SmallButton(Icons.star_rounded, context.tr('favorites'), () => _go(BrowseMode.favorites)),
              _SmallButton(Icons.history_rounded, context.tr('history'), () => _go(BrowseMode.history)),
              _SmallButton(Icons.refresh_rounded, context.tr('refresh'), s.reload),
              _SmallButton(Icons.swap_horiz_rounded, context.tr('change_list'), s.closeSource),
              _SmallButton(Icons.settings_rounded, context.tr('settings'), () => _push(const SettingsScreen())),
              _SmallButton(Icons.power_settings_new_rounded, context.tr('exit'), () => SystemNavigator.pop()),
            ]),
          ],
        ),
      ),
    );
  }
}

/// Own widget so the ticking clock repaints only itself, not the whole dashboard.
class _Clock extends StatefulWidget {
  final String lang;
  const _Clock({required this.lang});

  @override
  State<_Clock> createState() => _ClockState();
}

class _ClockState extends State<_Clock> {
  DateTime _now = DateTime.now();
  late final Timer _timer = Timer.periodic(const Duration(seconds: 20), (_) => setState(() => _now = DateTime.now()));

  @override
  void initState() {
    super.initState();
    _timer; // start ticking
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hm = '${_now.hour.toString().padLeft(2, '0')}:${_now.minute.toString().padLeft(2, '0')}';
    return Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
      Text(hm, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w300)),
      Text(formatDate(widget.lang, _now), style: const TextStyle(color: kMuted, fontSize: 13)),
    ]);
  }
}

class _BigTile extends StatefulWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> colors;
  final VoidCallback onTap;
  const _BigTile(this.title, this.subtitle, this.icon, this.colors, this.onTap);

  @override
  State<_BigTile> createState() => _BigTileState();
}

class _BigTileState extends State<_BigTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedScale(
            scale: _hover ? 1.04 : 1,
            duration: const Duration(milliseconds: 150),
            child: AspectRatio(
              aspectRatio: 0.95,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: widget.colors,
                  ),
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: widget.colors.first.withValues(alpha: _hover ? 0.45 : 0.2),
                      blurRadius: 30,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(widget.icon, size: 84, color: kBg),
                    const SizedBox(height: 16),
                    Text(widget.title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: kBg)),
                    const SizedBox(height: 4),
                    Text(widget.subtitle, style: TextStyle(color: kBg.withValues(alpha: 0.75))),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SmallButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _SmallButton(this.icon, this.label, this.onTap);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: kSurface2,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: kEmerald),
            const SizedBox(width: 10),
            Text(label),
          ]),
        ),
      ),
    );
  }
}
