import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../app_state.dart';
import '../models.dart';
import 'channel_checker.dart' show kUserAgent;
import 'log.dart';
import 'scheduler.dart' show recordingFileFor;
import 'stream_recorder.dart';

/// Last settings pushed to each player, so zapping does not re-send a dozen mpv properties.
final Expando<String> _appliedProfile = Expando<String>('applied player profile');

/// The mpv settings [configurePlayer] would apply, as a comparable key.
String playerProfileKey(AppState s, {bool live = true, bool lowQuality = false, bool light = false}) =>
    '${light ? 'light' : (live ? 'live' : 'vod')}|${s.hwdec}|${s.quality}|$lowQuality';

/// Applies network resilience, startup-speed and quality settings to an mpv-backed player.
/// Only does work when the profile (live / vod / light) or the user's settings changed since
/// the last call for this [player]. [light] is for multiview: small cache, no back-buffer.
Future<void> configurePlayer(Player player, AppState s,
    {bool live = true, bool lowQuality = false, bool light = false}) async {
  final p = player.platform;
  if (p is! NativePlayer) return;
  final key = playerProfileKey(s, live: live, lowQuality: lowQuality, light: light);
  if (_appliedProfile[player] == key) return;
  Future<void> set(String k, String v) async {
    try {
      await p.setProperty(k, v);
    } catch (_) {}
  }

  await set('user-agent', kUserAgent);
  await set('network-timeout', '15');
  // Reconnect automatically on dropped HTTP streams.
  await set('demuxer-lavf-o', 'reconnect=1,reconnect_streamed=1,reconnect_delay_max=5');
  await set('hwdec', s.hwdec ? 'auto-safe' : 'no');
  await set('cache', 'yes');
  await set('cache-pause-initial', 'no'); // start playing as soon as data arrives
  await set('cache-pause-wait', '1');
  if (light) {
    // Several players at once: keep each one small instead of 600 s / 200 MiB x 4.
    await set('demuxer-lavf-analyzeduration', '1.5');
    await set('demuxer-lavf-probesize', '1500000');
    await set('cache-secs', '10');
    await set('demuxer-max-bytes', '16MiB');
    await set('demuxer-max-back-bytes', '0');
  } else if (live) {
    // Fast zapping: probe less before starting. Large back-buffer = pause/rewind live up to ~10 min.
    await set('demuxer-lavf-analyzeduration', '1.5');
    await set('demuxer-lavf-probesize', '1500000');
    await set('cache-secs', '600');
    await set('demuxer-max-bytes', '200MiB');
    await set('demuxer-max-back-bytes', '200MiB');
  } else {
    await set('demuxer-lavf-analyzeduration', '5');
    await set('demuxer-lavf-probesize', '5000000');
    await set('cache-secs', '120');
    await set('demuxer-max-bytes', '150MiB');
    await set('demuxer-max-back-bytes', '50MiB');
  }
  await set('hls-bitrate', lowQuality ? 'min' : (s.quality == 'min' ? 'min' : 'max'));
  _appliedProfile[player] = key;
}
/// One player shared by the preview pane and the full-screen view, so expanding a
/// channel is instant (no second player to create and no re-buffering).
class PlayerService {
  final Player player = Player(configuration: const PlayerConfiguration(bufferSize: 64 * 1024 * 1024));
  late final VideoController video = VideoController(player);
  Channel? current;
  StreamRecorder? _recorder;
  String? _currentUrl;
  DateTime? _recordingStart;

  bool get isRecording => _recorder != null;
  String? get recordingPath => _recorder?.path;
  Duration get recordingElapsed => _recordingStart == null ? Duration.zero : DateTime.now().difference(_recordingStart!);

  Future<void> open(Channel c, AppState s, {Duration? start, String? urlOverride}) async {
    await stopRecording();
    current = c;
    await configurePlayer(player, s, live: c.type == ContentType.live);
    _currentUrl = urlOverride ?? c.url;
    Log.i('open ${c.name} ${Log.redact(urlOverride ?? c.url)}');
    await player.open(Media(urlOverride ?? c.url, start: start), play: true);
  }

  Future<void> stop() async {
    await stopRecording();
    current = null;
    await player.stop();
  }

  /// Records the channel being watched to Videos\Lumora Recordings (MPEG-TS, no re-encode).
  Future<String?> startRecording(String name) async {
    final url = _currentUrl;
    if (url == null || url.startsWith('series:')) return null;
    final t = DateTime.now();
    final rec = StreamRecorder();
    final path = recordingFileFor(name, '', t);
    await rec.start(url, path);
    _recorder = rec;
    _recordingStart = t;
    return path;
  }

  Future<void> stopRecording() async {
    final rec = _recorder;
    if (rec == null) return;
    _recorder = null;
    _recordingStart = null;
    await rec.stop();
  }
  Future<void> dispose() async {
    await stopRecording();
    await player.dispose();
  }
}

/// Alternates the Xtream live container (m3u8 <-> ts) as a fallback when one fails.
String? alternateLiveUrl(String url) {
  if (url.contains('/live/')) {
    if (url.endsWith('.m3u8')) return '${url.substring(0, url.length - 5)}.ts';
    if (url.endsWith('.ts')) return '${url.substring(0, url.length - 3)}.m3u8';
  }
  return null;
}
