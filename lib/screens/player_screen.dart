import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import '../app_state.dart';
import '../l10n.dart';
import '../models.dart';
import '../services/channel_variants.dart';
import '../services/log.dart';
import '../services/player_service.dart';
import '../theme.dart';
import '../widgets/interaction.dart';

const _maxRetries = 4;
const _stallLimit = Duration(seconds: 15);
const _barIdle = Duration(seconds: 3);

class PlayerScreen extends StatefulWidget {
  final Channel channel;
  final List<Channel> queue;
  const PlayerScreen({super.key, required this.channel, required this.queue});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final PlayerService _ps = context.read<PlayerService>();
  late final AppState _app = context.read<AppState>();
  Player get _player => _ps.player;
  late Channel _current = widget.channel;
  final _subs = <StreamSubscription>[];
  Timer? _stallTimer, _retryTimer, _numTimer, _saveTimer, _recTick;
  late final _bar = IdleVisibility(idle: _barIdle, onChanged: (_) => mounted ? setState(() {}) : null);
  bool get _barVisible => _bar.visible;
  final _dblClick = DoubleClickDetector();
  int _retries = 0;
  bool _failed = false;
  bool _reconnecting = false;
  bool _showGuide = false;
  bool _fullscreen = false;
  bool _pip = false;
  String? _urlOverride;
  String _numBuf = '';
  Size? _savedSize;
  Offset? _savedPos;

  bool get _isLive => _current.type == ContentType.live;

  @override
  void initState() {
    super.initState();
    _subs.add(_player.stream.error.listen((e) {
      Log.w('player error on ${_current.name}: $e');
      _onProblem();
    }));
    _subs.add(_player.stream.buffering.listen((b) {
      _stallTimer?.cancel();
      if (b) _stallTimer = Timer(_stallLimit, _onProblem); // stalled stream: reconnect, don't freeze
    }));
    _subs.add(_player.stream.playing.listen((p) {
      if (p) {
        _retries = 0;
        if (_failed || _reconnecting) setState(() => _failed = _reconnecting = false);
      }
    }));
    // Preview already playing this very channel: expanding is instant, no reopen.
    if (_ps.current?.id != _current.id) _open();
    _saveTimer = Timer.periodic(const Duration(seconds: 5), (_) => _saveResume());
    _recTick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_ps.isRecording && mounted) setState(() {});
    });
    _bar.poke();
  }


  Future<void> _open() async {
    _stallTimer?.cancel();
    Duration? start;
    String? resumeMsg;
    if (!_isLive) {
      final r = _app.resumeFor(_current.id);
      if (r != null && r.resumable) {
        start = Duration(milliseconds: r.posMs);
        resumeMsg = translate(_app.lang, 'resume_from', args: {'t': _fmt(start)});
      }
    }
    if (resumeMsg != null && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(resumeMsg), duration: const Duration(seconds: 3)));
    }
    await _ps.open(_current, _app, start: start, urlOverride: _urlOverride);
  }

  void _saveResume({bool force = false}) {
    if (_isLive) return;
    final dur = _player.state.duration.inMilliseconds;
    final pos = _player.state.position.inMilliseconds;
    if (dur > 0 && pos > 0) _app.saveResume(_current.id, pos, dur, force: force);
  }

  void _onProblem() {
    if (!mounted || _retryTimer?.isActive == true) return;
    if (_retries >= _maxRetries) {
      Log.e('giving up on ${_current.name}');
      setState(() {
        _failed = true;
        _reconnecting = false;
      });
      return;
    }
    _retries++;
    setState(() => _reconnecting = true);
    _retryTimer = Timer(Duration(seconds: 2 * _retries), () {
      if (!mounted) return;
      // From the second retry on, try the other Xtream container (m3u8 <-> ts).
      if (_retries == 2 && _urlOverride == null) {
        final alt = alternateLiveUrl(_current.url);
        if (alt != null) {
          Log.i('falling back to alternate stream format');
          _urlOverride = alt;
        }
      }
      _open();
    });
  }

  void _manualRetry() {
    _retries = 0;
    setState(() {
      _failed = false;
      _reconnecting = false;
    });
    _open();
  }

  void _zapTo(Channel next) {
    _saveResume(force: true);
    setState(() {
      _current = next;
      _retries = 0;
      _failed = false;
      _reconnecting = false;
      _urlOverride = null;
    });
    _app.addToHistory(next);
    _open();
  }

  void _step(int delta) {
    final q = widget.queue;
    final i = q.indexWhere((c) => c.id == _current.id);
    if (i < 0 || q.length < 2) return;
    _zapTo(q[(i + delta) % q.length]);
  }

  // ------------------------------------------------------------ shortcuts

  void _typeDigit(String d) {
    _numBuf += d;
    _numTimer?.cancel();
    setState(() {});
    _numTimer = Timer(const Duration(milliseconds: 1600), () {
      final n = int.tryParse(_numBuf);
      _numBuf = '';
      if (mounted) setState(() {});
      if (n != null && n >= 1 && n <= widget.queue.length) _zapTo(widget.queue[n - 1]);
    });
  }

  void _seek(int seconds) {
    final t = _player.state.position + Duration(seconds: seconds);
    _player.seek(t < Duration.zero ? Duration.zero : t);
  }

  void _volume(double delta) => _player.setVolume((_player.state.volume + delta).clamp(0, 100));

  /// Same native call media_kit uses (true borderless fullscreen). The button, F, and a
  /// double click all go through here so they behave identically.
  static const _nativeChannel = MethodChannel('com.alexmercerind/media_kit_video');

  Future<void> _setFullscreen(bool v) async {
    try {
      await _nativeChannel.invokeMethod(v ? 'Utils.EnterNativeFullscreen' : 'Utils.ExitNativeFullscreen');
    } catch (e) {
      Log.w('fullscreen change failed: $e');
      return;
    }
    if (mounted) setState(() => _fullscreen = v);
  }

  Future<void> _toggleFullscreen() => _setFullscreen(!_fullscreen);

  void _onVideoPointerDown(PointerDownEvent e) {
    if (_dblClick.press(e.position)) _toggleFullscreen();
  }

  Future<void> _togglePip() async {
    if (_pip) {
      await _exitPip();
      return;
    }
    if (_fullscreen) await _toggleFullscreen();
    _savedSize = await windowManager.getSize();
    _savedPos = await windowManager.getPosition();
    if (!mounted) return;
    final d = View.of(context).display;
    final screen = d.size / d.devicePixelRatio;
    await windowManager.setAlwaysOnTop(true);
    await windowManager.setSize(const Size(480, 300));
    await windowManager.setPosition(Offset(screen.width - 500, screen.height - 360));
    if (mounted) setState(() => _pip = true);
  }

  Future<void> _exitPip() async {
    await windowManager.setAlwaysOnTop(false);
    if (_savedSize != null) await windowManager.setSize(_savedSize!);
    if (_savedPos != null) await windowManager.setPosition(_savedPos!);
    if (mounted) setState(() => _pip = false);
  }

  Future<void> _toggleRecord() async {
    if (_ps.isRecording) {
      final path = _ps.recordingPath;
      await _ps.stopRecording();
      if (mounted && path != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('saved_to', args: {'path': path}))));
      }
    } else {
      await _ps.startRecording(_current.name);
    }
    if (mounted) setState(() {});
  }

  Future<void> _back() async {
    if (_fullscreen) await _toggleFullscreen();
    if (_pip) await _exitPip();
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _saveResume(force: true);
    for (final t in [_stallTimer, _retryTimer, _numTimer, _saveTimer, _recTick]) {
      t?.cancel();
    }
    _bar.dispose();
    for (final s in _subs) {
      s.cancel();
    }
    if (_fullscreen) _nativeChannel.invokeMethod<void>('Utils.ExitNativeFullscreen').ignore();
    if (_pip) {
      windowManager.setAlwaysOnTop(false);
      if (_savedSize != null) windowManager.setSize(_savedSize!);
    }
    super.dispose();
  }

  // ------------------------------------------------------------------ ui

  String _videoLabel(VideoTrack t) {
    if (t.h != null && t.h! > 0) return '${t.h}p';
    if (t.bitrate != null && t.bitrate! > 0) return '${(t.bitrate! / 1000).round()} kbps';
    return t.title ?? t.id;
  }

  String _fmt(Duration d) {
    final h = d.inHours, m = d.inMinutes.remainder(60), s = d.inSeconds.remainder(60);
    return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}' : '$m:${s.toString().padLeft(2, '0')}';
  }

  Widget _trackMenu<T>({
    required IconData icon,
    required String tooltip,
    required List<T> tracks,
    required T current,
    required String Function(T) label,
    required T autoTrack,
    required String autoLabel,
    required void Function(T) onSelect,
  }) {
    return PopupMenuButton<T>(
      tooltip: tooltip,
      icon: Icon(icon),
      color: kSurface2,
      onSelected: onSelect,
      itemBuilder: (_) => [
        PopupMenuItem(
          value: autoTrack,
          child: Text(autoLabel, style: TextStyle(color: current == autoTrack ? kEmerald : null)),
        ),
        for (final t in tracks)
          PopupMenuItem(value: t, child: Text(label(t), style: TextStyle(color: current == t ? kEmerald : null))),
      ],
    );
  }

  /// One quality button that always shows: stream renditions (when the stream has several)
  /// plus other versions of the same channel found in the list (HD / FHD / 4K ...).
  Widget _qualityMenu(List<VideoTrack> video, VideoTrack currentTrack) {
    final versions = _isLive ? _app.variantsOf(_current) : const <Channel>[];
    final hasTracks = video.length > 1;
    return StreamBuilder<int?>(
      stream: _player.stream.height,
      initialData: _player.state.height,
      builder: (_, snap) {
        final h = snap.data;
        return PopupMenuButton<Object>(
          tooltip: context.tr('quality'),
          color: kSurface2,
          onSelected: (v) {
            if (v is VideoTrack) {
              _player.setVideoTrack(v);
            } else if (v is Channel && v.id != _current.id) {
              _zapTo(v);
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.high_quality),
              if (h != null && h > 0) ...[
                const SizedBox(width: 4),
                Text('${h}p', style: const TextStyle(fontSize: 12, color: kEmerald)),
              ],
            ]),
          ),
          itemBuilder: (_) => [
            if (hasTracks) ...[
              PopupMenuItem<Object>(enabled: false, child: Text(context.tr('stream_quality'), style: const TextStyle(color: kMuted, fontSize: 12))),
              PopupMenuItem<Object>(
                value: VideoTrack.auto(),
                child: Text(context.tr('auto'), style: TextStyle(color: currentTrack.id == 'auto' ? kEmerald : null)),
              ),
              for (final t in video)
                PopupMenuItem<Object>(
                  value: t,
                  child: Text(_videoLabel(t), style: TextStyle(color: currentTrack == t ? kEmerald : null)),
                ),
            ],
            if (hasTracks && versions.length > 1) const PopupMenuDivider(),
            if (versions.length > 1) ...[
              PopupMenuItem<Object>(enabled: false, child: Text(context.tr('channel_versions'), style: const TextStyle(color: kMuted, fontSize: 12))),
              for (final v in versions)
                PopupMenuItem<Object>(
                  value: v,
                  child: Text(
                    '${tierOf(v.name)?.label ?? '·'}   ${v.name}',
                    style: TextStyle(color: v.id == _current.id ? kEmerald : null),
                  ),
                ),
            ],
            if (!hasTracks && versions.length <= 1)
              PopupMenuItem<Object>(enabled: false, child: Text(context.tr('no_other_quality'))),
          ],
        );
      },
    );
  }

  Widget _trackMenus() => StreamBuilder<Tracks>(
        stream: _player.stream.tracks,
        initialData: _player.state.tracks,
        builder: (_, snap) {
          final tr = snap.data ?? const Tracks();
          final video = tr.video.where((t) => t.id != 'auto' && t.id != 'no').toList();
          final audio = tr.audio.where((t) => t.id != 'auto' && t.id != 'no').toList();
          final subs = tr.subtitle.where((t) => t.id != 'auto' && t.id != 'no').toList();
          return StreamBuilder<Track>(
            stream: _player.stream.track,
            initialData: _player.state.track,
            builder: (_, cur) {
              final c = cur.data ?? const Track();
              return Row(mainAxisSize: MainAxisSize.min, children: [
                _qualityMenu(video, c.video),

                if (audio.length > 1)
                  _trackMenu<AudioTrack>(
                    icon: Icons.audiotrack,
                    tooltip: context.tr('audio'),
                    tracks: audio,
                    current: c.audio,
                    label: (t) => t.title ?? t.language ?? t.id,
                    autoTrack: AudioTrack.auto(),
                    autoLabel: context.tr('auto'),
                    onSelect: _player.setAudioTrack,
                  ),
                if (subs.isNotEmpty)
                  _trackMenu<SubtitleTrack>(
                    icon: Icons.subtitles,
                    tooltip: context.tr('subtitles'),
                    tracks: subs,
                    current: c.subtitle,
                    label: (t) => t.title ?? t.language ?? t.id,
                    autoTrack: SubtitleTrack.no(),
                    autoLabel: context.tr('off'),
                    onSelect: _player.setSubtitleTrack,
                  ),
              ]);
            },
          );
        },
      );

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final programmes = _isLive ? s.epg.upcoming(_current.epgId) : const <Programme>[];
    final controlsOff = const MaterialDesktopVideoControlsThemeData(
      keyboardShortcuts: {}, // shortcuts are handled below, in one place
      // The video controls own the mouse cursor over the picture, so they must hide it
      // (same 3 s as the top bar); our own MouseRegion above would lose to theirs.
      hideMouseOnControlsRemoval: true,
      toggleFullscreenOnDoublePress: false, // handled by _onVideoPointerDown instead
      controlsHoverDuration: _barIdle,
      bottomButtonBar: [
        MaterialDesktopPlayOrPauseButton(),
        MaterialDesktopVolumeButton(),
        MaterialDesktopPositionIndicator(),
        Spacer(),
      ],
    );

    final digits = <ShortcutActivator, VoidCallback>{
      for (var i = 0; i <= 9; i++) ...{
        SingleActivator(LogicalKeyboardKey(LogicalKeyboardKey.digit0.keyId + i)): () => _typeDigit('$i'),
        SingleActivator(LogicalKeyboardKey(LogicalKeyboardKey.numpad0.keyId + i)): () => _typeDigit('$i'),
      },
    };

    return CallbackShortcuts(
      bindings: {
        ...digits,
        const SingleActivator(LogicalKeyboardKey.escape): () async {
          if (_fullscreen) {
            await _toggleFullscreen();
          } else if (_pip) {
            await _exitPip();
          } else {
            _back();
          }
        },
        const SingleActivator(LogicalKeyboardKey.space): _player.playOrPause,
        const SingleActivator(LogicalKeyboardKey.keyF): _toggleFullscreen,
        const SingleActivator(LogicalKeyboardKey.keyM): () => _player.setVolume(_player.state.volume > 0 ? 0 : 100),
        const SingleActivator(LogicalKeyboardKey.keyR): _toggleRecord,
        const SingleActivator(LogicalKeyboardKey.keyP): _togglePip,
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _seek(-10),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => _seek(10),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () => _isLive ? _step(-1) : _volume(5),
        const SingleActivator(LogicalKeyboardKey.arrowDown): () => _isLive ? _step(1) : _volume(-5),
        const SingleActivator(LogicalKeyboardKey.equal): () => _volume(5),
        const SingleActivator(LogicalKeyboardKey.minus): () => _volume(-5),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: MouseRegion(
            cursor: (_fullscreen && !_barVisible) ? SystemMouseCursors.none : MouseCursor.defer,
            onHover: (_) => _bar.poke(),
            opaque: false,
            child: Stack(
            children: [
              Row(children: [
                Expanded(
                  child: MaterialDesktopVideoControlsTheme(
                    normal: controlsOff,
                    fullscreen: controlsOff,
                    child: Listener(
                      behavior: HitTestBehavior.translucent,
                      onPointerDown: _onVideoPointerDown,
                      child: Video(controller: _ps.video, controls: MaterialDesktopVideoControls),
                    ),
                  ),
                ),
                if (_showGuide && !_pip)
                  Container(
                    width: 320,
                    color: Colors.black87,
                    child: ListView(padding: const EdgeInsets.all(12), children: [
                      Text(context.tr('guide'), style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      if (programmes.isEmpty) Text(context.tr('no_guide')),
                      for (final p in programmes)
                        ListTile(
                          dense: true,
                          title: Text(p.title),
                          subtitle: Text(
                            '${_hm(p.start)} – ${_hm(p.stop)}${p.description != null ? '\n${p.description}' : ''}',
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                          ),
                          selected: p.isOn(DateTime.now()),
                        ),
                    ]),
                  ),
              ]),
              if (_numBuf.isNotEmpty)
                Positioned(
                  top: 70,
                  right: 30,
                  child: Text(_numBuf, style: const TextStyle(fontSize: 56, fontWeight: FontWeight.w800, color: kEmerald)),
                ),
              if (_reconnecting && !_failed)
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(14)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                      const SizedBox(width: 12),
                      Text('${context.tr('reconnecting')} ($_retries/$_maxRetries)'),
                    ]),
                  ),
                ),
              if (_failed)
                Center(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(context.tr('cant_play')),
                        const SizedBox(height: 10),
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          FilledButton(onPressed: _manualRetry, child: Text(context.tr('retry'))),
                          if (widget.queue.length > 1) ...[
                            const SizedBox(width: 10),
                            OutlinedButton(onPressed: () => _step(1), child: Text(context.tr('next_channel'))),
                          ],
                        ]),
                      ]),
                    ),
                  ),
                ),
              Positioned(
                top: 0,
                left: 0,
                right: (_showGuide && !_pip) ? 320 : 0,
                child: IgnorePointer(
                  ignoring: !_barVisible && !_failed,
                  child: AnimatedOpacity(
                    opacity: (_barVisible || _failed) ? 1 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: _topBar(s),
                  ),
                ),
              ),
            ],
          ),
          ),
        ),
      ),
    );
  }

  Widget _topBar(AppState s) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black87, Colors.transparent],
        ),
      ),
      child: Row(children: [
        BackButton(onPressed: _back),
        Expanded(child: Text(_current.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
        if (_ps.isRecording)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(children: [
              const Icon(Icons.fiber_manual_record, color: Colors.redAccent, size: 14),
              const SizedBox(width: 4),
              Text('${context.tr('recording')} ${_fmt(_ps.recordingElapsed)}',
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
            ]),
          ),
        if (!_pip) ...[
          _trackMenus(),
          if (widget.queue.length > 1) ...[
            IconButton(tooltip: context.tr('prev'), icon: const Icon(Icons.skip_previous), onPressed: () => _step(-1)),
            IconButton(tooltip: context.tr('next'), icon: const Icon(Icons.skip_next), onPressed: () => _step(1)),
          ],
          if (_isLive)
            IconButton(
              tooltip: _ps.isRecording ? context.tr('stop_record') : context.tr('record'),
              icon: Icon(Icons.fiber_manual_record, color: _ps.isRecording ? Colors.redAccent : null),
              onPressed: _toggleRecord,
            ),
          if (_isLive)
            IconButton(
              tooltip: context.tr('guide'),
              icon: const Icon(Icons.list_alt),
              onPressed: () => setState(() => _showGuide = !_showGuide),
            ),
          IconButton(
            tooltip: context.tr('favorite'),
            icon: Icon(s.isFavorite(_current) ? Icons.star : Icons.star_border),
            onPressed: () => s.toggleFavorite(_current),
          ),
        ],
        IconButton(
          tooltip: context.tr('pip'),
          icon: Icon(_pip ? Icons.open_in_full : Icons.picture_in_picture_alt),
          onPressed: _togglePip,
        ),
        if (!_pip)
          IconButton(
            tooltip: context.tr('fullscreen'),
            icon: Icon(_fullscreen ? Icons.fullscreen_exit : Icons.fullscreen),
            onPressed: _toggleFullscreen,
          ),
      ]),
    );
  }

  String _hm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
