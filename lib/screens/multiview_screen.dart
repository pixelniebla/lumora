import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../l10n.dart';
import '../models.dart';
import '../services/player_service.dart';
import '../theme.dart';
import '../widgets/channel_picker.dart';

/// Up to four live channels at once. Only the focused cell has sound, and the
/// others are limited to the lowest quality to keep CPU and bandwidth in check.
class MultiviewScreen extends StatefulWidget {
  const MultiviewScreen({super.key});

  @override
  State<MultiviewScreen> createState() => _MultiviewScreenState();
}

class _Cell {
  final Player player = Player(configuration: const PlayerConfiguration(bufferSize: 16 * 1024 * 1024));
  late final VideoController video = VideoController(player);
  Channel? channel;
}

class _MultiviewScreenState extends State<MultiviewScreen> {
  /// Starts with two screens; the user can add up to [_maxCells]. Players are only created for screens
  /// that exist, so the default view costs half the memory and CPU of the old fixed four.
  static const _minCells = 2;
  static const _maxCells = 4;
  final _cells = List.generate(_minCells, (_) => _Cell());
  int _focus = 0;

  @override
  void dispose() {
    for (final c in _cells) {
      c.player.dispose();
    }
    super.dispose();
  }

  Future<void> _pick(_Cell cell) async {
    final app = context.read<AppState>();
    final ch = await pickChannel(context);
    if (ch == null || !mounted || !_cells.contains(cell)) return; // cancelled, or the screen was removed meanwhile
    cell.channel = ch;
    await configurePlayer(cell.player, app, lowQuality: true, light: true);
    await cell.player.open(Media(ch.url));
    if (!mounted || !_cells.contains(cell)) return;
    setState(() => _focus = _cells.indexOf(cell));
    _applyAudio();
  }

  Future<void> _addScreen() async {
    if (_cells.length >= _maxCells) return;
    final cell = _Cell();
    setState(() => _cells.add(cell));
    await _pick(cell);
  }

  void _removeScreen(_Cell cell) {
    final i = _cells.indexOf(cell);
    if (i < 0 || _cells.length <= _minCells) return;
    setState(() {
      _cells.removeAt(i);
      if (_focus >= _cells.length || i < _focus) _focus = (_focus - 1).clamp(0, _cells.length - 1);
    });
    cell.player.dispose();
    _applyAudio();
  }

  void _applyAudio() {
    for (var i = 0; i < _cells.length; i++) {
      _cells[i].player.setVolume(i == _focus ? 100 : 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.transparent, title: Text(context.tr('multiview'))),
      body: Container(
        decoration: const BoxDecoration(gradient: kBackdrop),
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: GridView.count(
          crossAxisCount: 2,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 16 / 9,
          children: [
            for (var i = 0; i < _cells.length; i++) _cell(i),
            if (_cells.length < _maxCells) _addTile(),
          ],
        ),
      ),
    );
  }

  Widget _addTile() => Material(
        color: Colors.transparent,
        child: InkWell(
          key: const ValueKey('add-screen'),
          borderRadius: BorderRadius.circular(12),
          onTap: _addScreen,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: kMuted.withValues(alpha: 0.5)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.add, size: 36, color: kMuted),
                const SizedBox(height: 6),
                Text(translate(context.read<AppState>().lang, 'add_screen'), style: const TextStyle(color: kMuted)),
              ]),
            ),
          ),
        ),
      );

  Widget _removeButton(_Cell cell) => _cells.length > _minCells
      ? IconButton(
          iconSize: 18,
          tooltip: translate(context.read<AppState>().lang, 'remove_screen'),
          icon: const Icon(Icons.close),
          onPressed: () => _removeScreen(cell),
        )
      : const SizedBox.shrink();

  Widget _cell(int i) {
    final c = _cells[i];
    final focused = i == _focus;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: focused ? kEmerald : Colors.transparent, width: 2),
        borderRadius: BorderRadius.circular(12),
        color: Colors.black,
      ),
      clipBehavior: Clip.antiAlias,
      child: c.channel == null
          ? Stack(children: [
              Positioned.fill(
                child: InkWell(
                  onTap: () => _pick(c),
                  child: Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.add_circle_outline, size: 40, color: kMuted),
                      const SizedBox(height: 8),
                      Text(context.tr('tap_to_pick'), style: const TextStyle(color: kMuted)),
                    ]),
                  ),
                ),
              ),
              Positioned(top: 0, right: 0, child: _removeButton(c)),
            ])
          : Stack(children: [
              Positioned.fill(child: Video(controller: c.video, controls: NoVideoControls)),
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () {
                    setState(() => _focus = i);
                    _applyAudio();
                  },
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: Container(
                  color: Colors.black54,
                  padding: const EdgeInsets.only(left: 10),
                  child: Row(children: [
                    Icon(focused ? Icons.volume_up : Icons.volume_off, size: 16, color: focused ? kEmerald : kMuted),
                    const SizedBox(width: 6),
                    Expanded(child: Text(c.channel!.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
                    IconButton(
                      iconSize: 18,
                      tooltip: context.tr('pick_channel'),
                      icon: const Icon(Icons.swap_horiz),
                      onPressed: () => _pick(c),
                    ),
                    _removeButton(c),
                  ]),
                ),
              ),
            ]),
    );
  }
}
