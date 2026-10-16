import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'channel_checker.dart' show kUserAgent;
import 'log.dart';
import 'scheduler.dart' show Recorder;

/// Saves a live stream to a file by copying its bytes: a raw HTTP stream (Xtream `.ts`) is
/// copied as it arrives; an HLS playlist is followed and its segments appended in order.
/// The result is an MPEG-TS file any player can open. (mpv's own `stream-record` cannot be
/// used: the libmpv shipped with media_kit has no muxers, so it never writes a file.)
///
/// Dropped connections are retried; after [maxFailures] failures in a row it gives up.
class StreamRecorder implements Recorder {
  final int maxFailures;
  final Duration retryDelay;
  StreamRecorder({this.maxFailures = 8, this.retryDelay = const Duration(seconds: 2)});

  @override
  String? path;
  int bytesWritten = 0;
  Object? lastError;
  bool _stopped = false;
  HttpClient? _client;
  IOSink? _sink;
  Future<void>? _loop;

  bool get isRunning => _loop != null && !_stopped;

  @override
  Future<void> start(String url, String outPath) async {
    path = outPath;
    _stopped = false;
    _client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10)
      ..userAgent = kUserAgent
      ..autoUncompress = false;
    _sink = File(outPath).openWrite();
    Log.i('recording started: ${Log.redact(url)} -> $outPath');
    _loop = _run(Uri.parse(url));
  }

  @override
  Future<void> stop() async {
    _stopped = true;
    _client?.close(force: true);
    try {
      await _loop;
    } catch (_) {}
    try {
      await _sink?.flush();
      await _sink?.close();
    } catch (_) {}
    _sink = null;
    _loop = null;
    Log.i('recording finished: $path ($bytesWritten bytes)');
  }

  Future<void> _run(Uri url) async {
    var failures = 0;
    while (!_stopped && failures < maxFailures) {
      try {
        final done = await _session(url);
        if (done) break; // HLS ENDLIST
        failures = 0; // the stream was alive; if it simply ended, reconnect
      } catch (e) {
        if (_stopped) break;
        lastError = e;
        failures++;
        Log.w('recording interrupted (${failures}x): ${Log.redact(e.toString())}');
      }
      if (!_stopped) await Future<void>.delayed(retryDelay);
    }
    if (!_stopped && failures >= maxFailures) Log.e('recording gave up: ${Log.redact('$lastError')}');
  }

  /// One connection. Returns true when the stream is finished for good.
  Future<bool> _session(Uri url) async {
    final res = await _get(url);
    if (res.statusCode != 200) {
      await res.drain<void>().catchError((_) {});
      throw HttpException('HTTP ${res.statusCode}');
    }
    final type = res.headers.contentType?.mimeType ?? '';
    final looksHls = url.path.toLowerCase().endsWith('.m3u8') || type.contains('mpegurl');
    if (!looksHls) {
      await _copy(res);
      return false;
    }
    final text = await res.transform(const Utf8Decoder(allowMalformed: true)).join();
    if (!text.trimLeft().startsWith('#EXTM3U')) throw const FormatException('not a playlist');
    return _hls(url, text);
  }

  Future<HttpClientResponse> _get(Uri url) async => (await _client!.getUrl(url)).close();

  Future<void> _copy(Stream<List<int>> body) async {
    await for (final chunk in body) {
      if (_stopped) return;
      _sink!.add(chunk);
      bytesWritten += chunk.length;
    }
  }

  Future<bool> _hls(Uri url, String firstText) async {
    var playlistUrl = url;
    var text = firstText;
    final seen = <String>{};
    var quiet = 0;
    while (!_stopped) {
      final lines = text.split(RegExp(r'\r?\n')).map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
      if (lines.any((l) => l.startsWith('#EXT-X-STREAM-INF'))) {
        // Master playlist: follow the best variant.
        String? best;
        var bestBw = -1;
        for (var i = 0; i < lines.length; i++) {
          if (!lines[i].startsWith('#EXT-X-STREAM-INF')) continue;
          final bw = int.tryParse(RegExp(r'BANDWIDTH=(\d+)').firstMatch(lines[i])?[1] ?? '') ?? 0;
          final next = lines.skip(i + 1).firstWhere((l) => !l.startsWith('#'), orElse: () => '');
          if (next.isNotEmpty && bw > bestBw) {
            bestBw = bw;
            best = next;
          }
        }
        if (best == null) throw const FormatException('empty master playlist');
        playlistUrl = playlistUrl.resolve(best);
      } else {
        var target = 4.0;
        final t = RegExp(r'#EXT-X-TARGETDURATION:(\d+)').firstMatch(text);
        if (t != null) target = double.parse(t[1]!);
        var fresh = 0;
        for (final l in lines.where((l) => !l.startsWith('#'))) {
          final seg = playlistUrl.resolve(l);
          if (!seen.add(seg.toString())) continue;
          fresh++;
          final r = await _get(seg);
          if (r.statusCode != 200) {
            await r.drain<void>().catchError((_) {});
            throw HttpException('segment HTTP ${r.statusCode}');
          }
          await _copy(r);
          if (_stopped) return false;
        }
        if (text.contains('#EXT-X-ENDLIST')) return true;
        quiet = fresh == 0 ? quiet + 1 : 0;
        if (quiet > 30) throw const FormatException('playlist stopped updating');
        await Future<void>.delayed(Duration(milliseconds: (target * 500).clamp(500, 6000).round()));
      }
      if (_stopped) return false;
      final r = await _get(playlistUrl);
      if (r.statusCode != 200) {
        await r.drain<void>().catchError((_) {});
        throw HttpException('HTTP ${r.statusCode}');
      }
      text = await r.transform(const Utf8Decoder(allowMalformed: true)).join();
    }
    return false;
  }
}
