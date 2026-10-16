import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../l10n.dart';
import '../models.dart';
import '../services/logo_cache.dart';
import '../services/player_service.dart';
import '../theme.dart';
import '../widgets/pin_dialog.dart';
import 'player_screen.dart';

enum BrowseMode { live, movie, series, favorites, history, continueWatching }

enum _Sort { original, az, za }

const _titles = {
  BrowseMode.live: 'live',
  BrowseMode.movie: 'movies',
  BrowseMode.series: 'series',
  BrowseMode.favorites: 'favorites',
  BrowseMode.history: 'history',
  BrowseMode.continueWatching: 'continue_watching',
};

/// Three panes: categories | channel list | preview with guide.
class BrowseScreen extends StatefulWidget {
  final BrowseMode mode;
  const BrowseScreen({super.key, required this.mode});

  @override
  State<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<BrowseScreen> {
  late final PlayerService _ps;
  String? _categoryId;
  String _query = '';
  _Sort _sort = _Sort.original;
  Channel? _selected;
  Timer? _debounce;

  // Memoized result so rebuilds that change nothing relevant do not refilter 50k items.
  Object? _key;
  List<Channel> _cached = const [];

  ContentType? get _type => switch (widget.mode) {
        BrowseMode.live => ContentType.live,
        BrowseMode.movie => ContentType.movie,
        BrowseMode.series => ContentType.series,
        _ => null,
      };

  @override
  void initState() {
    super.initState();
    _ps = context.read<PlayerService>(); // not lazily in dispose(): the element is deactivated by then
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ps.stop(); // leave no audio playing behind the previous screen
    super.dispose();
  }

  List<Channel> _items(AppState s) {
    final lib = s.library!;
    final key = Object.hashAll([
      identityHashCode(lib), widget.mode, _categoryId, _query, _sort, s.hideBroken, s.broken.length,
      s.unlocked, s.hiddenCats.length, s.lockedCats.length, s.pinEnabled,
      if (widget.mode == BrowseMode.history) s.history.length,
      if (widget.mode == BrowseMode.continueWatching) s.history.length,
      if (widget.mode == BrowseMode.favorites) ...[s.favorites.length, ...s.favOrder.take(1)],
    ]);
    if (key == _key) return _cached;

    Iterable<Channel> it = switch (widget.mode) {
      BrowseMode.favorites => s.orderedFavorites(),
      BrowseMode.history => s.history,
      BrowseMode.continueWatching => s.continueWatching(),
      _ => lib.items.where((c) => c.type == _type),
    };
    it = it.where(s.visible);
    if (s.hideBroken && s.broken.isNotEmpty) it = it.where((c) => !s.broken.contains(c.id));
    if (_categoryId != null) it = it.where((c) => c.categoryId == _categoryId);
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      it = it.where((c) => c.lower.contains(q));
    }
    var list = it.toList();
    if (_sort != _Sort.original) {
      list.sort((a, b) => a.lower.compareTo(b.lower));
      if (_sort == _Sort.za) list = list.reversed.toList();
    }
    _key = key;
    return _cached = list;
  }

  List<Category> _categories(AppState s) {
    if (_type == null) return const [];
    final lib = s.library!;
    final used = <String>{for (final c in lib.items) if (c.type == _type) c.categoryId};
    return lib.categories.where((c) => used.contains(c.id) && !s.hiddenCats.contains(c.id)).toList();
  }

  Future<void> _select(AppState s, Channel c, List<Channel> queue) async {
    if (c.url.startsWith('series:')) {
      final client = s.xtreamFor(c);
      if (client == null) return;
      final eps = await client.seriesEpisodes(c.url.substring(7), c.categoryId);
      if (!mounted) return;
      if (eps.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('no_episodes'))));
        return;
      }
      showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(c.name),
          content: SizedBox(
            width: 480,
            height: 420,
            child: ListView(children: [
              for (final e in eps)
                ListTile(
                  title: Text(e.name),
                  onTap: () {
                    Navigator.pop(dialogContext);
                    _fullscreen(s, e, eps);
                  },
                ),
            ]),
          ),
        ),
      );
      return;
    }
    if (_selected?.id == c.id) {
      _fullscreen(s, c, queue); // second tap = full screen
      return;
    }
    setState(() => _selected = c);
    s.addToHistory(c);
    _ps.open(c, s);
  }

  Future<void> _fullscreen(AppState s, Channel c, List<Channel> queue) async {
    s.addToHistory(c);
    await Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerScreen(channel: c, queue: queue)));
    if (mounted) setState(() => _selected = _ps.current); // reflects zapping done in full screen
  }

  Future<void> _pickCategory(AppState s, String? id) async {
    if (id != null && s.isCategoryLocked(id)) {
      if (!await askPin(context)) return;
    }
    setState(() => _categoryId = id);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final items = _items(s);
    final cats = _categories(s);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: kBackdrop),
        child: SafeArea(
          child: Column(
            children: [
              _topBar(s),
              Expanded(
                child: Row(
                  children: [
                    if (cats.isNotEmpty) SizedBox(width: 230, child: _categoryList(s, cats)),
                    Expanded(flex: 5, child: _channelList(s, items)),
                    SizedBox(width: 400, child: _previewPane(s, items)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topBar(AppState s) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 20, 8),
        child: Row(children: [
          BackButton(onPressed: () => Navigator.pop(context)),
          const LumoraLogo(size: 32),
          const SizedBox(width: 10),
          Text(context.tr(_titles[widget.mode]!), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(width: 28),
          SizedBox(
            width: 320,
            child: TextField(
              decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search), hintText: context.tr('search'), isDense: true),
              onChanged: (v) {
                // Debounce: filtering tens of thousands of channels on every key press would stutter.
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 220), () {
                  if (mounted) setState(() => _query = v.trim());
                });
              },
            ),
          ),
          const SizedBox(width: 8),
          PopupMenuButton<_Sort>(
            tooltip: context.tr('sort'),
            icon: const Icon(Icons.sort),
            color: kSurface2,
            onSelected: (v) => setState(() => _sort = v),
            itemBuilder: (_) => [
              PopupMenuItem(value: _Sort.original, child: Text(context.tr('sort_default'))),
              PopupMenuItem(value: _Sort.az, child: Text(context.tr('sort_az'))),
              PopupMenuItem(value: _Sort.za, child: Text(context.tr('sort_za'))),
            ],
          ),
          if (s.refreshing) ...[
            const SizedBox(width: 12),
            const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 8),
            Text(context.tr('refreshing'), style: const TextStyle(color: kMuted, fontSize: 12)),
          ],
          const Spacer(),
          if (s.pinEnabled && s.unlocked)
            TextButton.icon(
              onPressed: s.lockAgain,
              icon: const Icon(Icons.lock_outline),
              label: Text(context.tr('lock_again')),
            ),
          if (widget.mode == BrowseMode.history)
            TextButton.icon(
              onPressed: s.clearHistory,
              icon: const Icon(Icons.delete_outline),
              label: Text(context.tr('clear_history')),
            ),
        ]),
      );

  Widget _categoryList(AppState s, List<Category> cats) => Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 8, 16),
        decoration: BoxDecoration(color: kSurface.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(18)),
        clipBehavior: Clip.antiAlias,
        // Material above the decoration: ListTile paints its selection colour and ink on the nearest
        // Material, which would otherwise be hidden behind this container's background.
        child: Material(
          type: MaterialType.transparency,
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: cats.length + 1,
            itemBuilder: (_, i) => i == 0
                ? _catTile(s, translate(s.lang, 'all'), null)
                : _catTile(s, cats[i - 1].name, cats[i - 1].id),
          ),
        ),
      );

  Widget _catTile(AppState s, String name, String? id) {
    final on = _categoryId == id;
    final locked = id != null && s.isCategoryLocked(id);
    return ListTile(
      dense: true,
      selected: on,
      selectedColor: kEmerald,
      selectedTileColor: kEmerald.withValues(alpha: 0.12),
      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: locked ? const Icon(Icons.lock, size: 16, color: kGold) : null,
      onTap: () => _pickCategory(s, id),
    );
  }

  Widget _channelList(AppState s, List<Channel> items) {
    final reorderable = widget.mode == BrowseMode.favorites && _query.isEmpty && _sort == _Sort.original;
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 16),
      decoration: BoxDecoration(color: kSurface.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(18)),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: items.isEmpty
          ? Center(child: Text(context.tr('nothing'), style: const TextStyle(color: kMuted)))
          : Column(children: [
              if (reorderable)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(context.tr('reorder_hint'), style: const TextStyle(color: kMuted, fontSize: 12)),
                ),
              Expanded(
                child: reorderable
                    ? ReorderableListView.builder(
                        buildDefaultDragHandles: false,
                        itemCount: items.length,
                        onReorderItem: s.reorderFavorites,
                        itemBuilder: (_, i) => KeyedSubtree(
                          key: ValueKey(items[i].id),
                          child: _tile(s, items, i, handleIndex: i),
                        ),
                      )
                    : ListView.builder(
                        itemCount: items.length,
                        itemExtent: 64,
                        itemBuilder: (_, i) => _tile(s, items, i),
                      ),
              ),
            ]),
      ),
    );
  }

  Widget _tile(AppState s, List<Channel> items, int i, {int? handleIndex}) {
    final c = items[i];
    final now = c.type == ContentType.live ? s.epg.nowPlaying(c.epgId) : null;
    final res = c.type == ContentType.live ? null : s.resumeFor(c.id);
    final fav = s.isFavorite(c);
    return SizedBox(
      height: 64,
      child: ListTile(
        selected: _selected?.id == c.id,
        selectedTileColor: kEmerald.withValues(alpha: 0.12),
        onTap: () => _select(s, c, items),
        leading: _Logo(c.logo),
        title: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: now != null
            ? Text(now.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: kGold))
            : (res != null && res.fraction > 0.01
                ? Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: LinearProgressIndicator(value: res.fraction.clamp(0, 1), minHeight: 3),
                  )
                : null),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
            tooltip: translate(s.lang, 'favorite'),
            icon: Icon(fav ? Icons.star_rounded : Icons.star_border_rounded, color: fav ? kGold : kMuted),
            onPressed: () => s.toggleFavorite(c),
          ),
          if (handleIndex != null)
            ReorderableDragStartListener(index: handleIndex, child: const Icon(Icons.drag_indicator, color: kMuted)),
        ]),
      ),
    );
  }

  Widget _previewPane(AppState s, List<Channel> items) {
    final c = _selected;
    final live = c != null && c.type == ContentType.live;
    final programmes = live ? s.epg.upcoming(c.epgId, max: 6) : const <Programme>[];
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 0, 16, 16),
      decoration: BoxDecoration(color: kSurface.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(18)),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        AspectRatio(
          aspectRatio: 16 / 9,
          child: c == null
              ? ColoredBox(
                  color: Colors.black,
                  child: Center(child: Text(context.tr('select_channel'), style: const TextStyle(color: kMuted))),
                )
              : Video(controller: _ps.video, controls: NoVideoControls),
        ),
        if (c != null)
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Expanded(child: Text(c.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
              FilledButton.icon(
                onPressed: () => _fullscreen(s, c, items),
                icon: const Icon(Icons.fullscreen),
                label: Text(context.tr('expand')),
              ),
            ]),
          ),
        Expanded(
          child: ListView(padding: const EdgeInsets.symmetric(horizontal: 14), children: [
            if (live && programmes.isEmpty) Text(context.tr('no_guide'), style: const TextStyle(color: kMuted)),
            for (final p in programmes)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${_hm(p.start)} – ${_hm(p.stop)}',
                      style: TextStyle(color: p.isOn(DateTime.now()) ? kEmerald : kMuted, fontSize: 12)),
                  Text(p.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                ]),
              ),
          ]),
        ),
      ]),
    );
  }

  String _hm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

/// Channel logo decoded at icon size: decoding full-size images for a long list
/// is what makes scrolling stutter and eats memory.
class _Logo extends StatelessWidget {
  final String? url;
  const _Logo(this.url);

  @override
  Widget build(BuildContext context) {
    if (url == null || url!.isEmpty) return const SizedBox(width: 48, height: 48, child: Icon(Icons.tv, color: kMuted));
    return SizedBox(
      width: 48,
      height: 48,
      child: CachedNetworkImage(
        imageUrl: url!,
        cacheManager: logoCacheManager,
        fit: BoxFit.contain,
        memCacheWidth: 96,
        memCacheHeight: 96,
        maxWidthDiskCache: 128,
        maxHeightDiskCache: 128,
        fadeInDuration: Duration.zero,
        fadeOutDuration: Duration.zero,
        errorWidget: (_, _, _) => const Icon(Icons.tv, color: kMuted),
        placeholder: (_, _) => const SizedBox.shrink(),
      ),
    );
  }
}
