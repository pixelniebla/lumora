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
        clipBehavior: Clip.hardEdge,
        child: Stack(children: [
          const Positioned(top: -180, right: -120, child: GlowBlob(size: 620)),
          const Positioned(bottom: -260, left: -160, child: GlowBlob(size: 640, color: kGold)),
          Padding(
        padding: const EdgeInsets.fromLTRB(40, 28, 40, 28),
        child: Column(
          children: [
            Row(children: [
              const LumoraLogo(size: 52),
              const SizedBox(width: 16),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Lumora',
                    style: TextStyle(fontFamily: kDisplayFont, fontFamilyFallback: kFontFallback, fontSize: 30, fontWeight: FontWeight.w600, height: 1.1)),
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
        ]),
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
    final c0 = widget.colors.first, c1 = widget.colors.last;
    return Expanded(
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedScale(
            scale: _hover ? 1.035 : 1,
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            child: AspectRatio(
              aspectRatio: 0.95,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(30),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color.alphaBlend(c0.withValues(alpha: 0.22), kSurface), Color.alphaBlend(c1.withValues(alpha: 0.08), kSurface)],
                  ),
                  border: Border.all(color: c0.withValues(alpha: _hover ? 0.75 : 0.28), width: 1.4),
                  boxShadow: [BoxShadow(color: c0.withValues(alpha: _hover ? 0.32 : 0.12), blurRadius: _hover ? 36 : 24, offset: const Offset(0, 14))],
                ),
                child: Stack(children: [
                  Positioned(
                    right: -26,
                    bottom: -30,
                    child: Transform.rotate(angle: tileTilt(), child: Icon(widget.icon, size: 200, color: c0.withValues(alpha: 0.08))),
                  ),
                  Positioned.fill(
                    child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          width: 92,
                          height: 92,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [c0, c1]),
                            boxShadow: [BoxShadow(color: c0.withValues(alpha: 0.45), blurRadius: 26)],
                          ),
                          child: Icon(widget.icon, size: 46, color: kBg),
                        ),
                        const SizedBox(height: 20),
                        Text(widget.title,
                            style: const TextStyle(fontFamily: kDisplayFont, fontFamilyFallback: kFontFallback, fontSize: 25, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text(widget.subtitle, style: const TextStyle(color: kMuted, fontSize: 14)),
                      ],
                    ),
                  ),
                  ),
                ]),
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
      color: kSurface2.withValues(alpha: 0.7),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
      child: InkWell(
        customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        hoverColor: kEmerald.withValues(alpha: 0.10),
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