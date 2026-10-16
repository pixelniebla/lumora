import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models.dart';
import 'log.dart';

const kUserAgent = 'VLC/3.0.20 LibVLC/3.0.20';

enum CheckStatus { ok, slow, failed }

class CheckResult {
  final Channel channel;
  final CheckStatus status;
  final String detail;
  final int ms;
  const CheckResult(this.channel, this.status, this.detail, this.ms);
}

/// Probes whether a stream actually delivers data. For HLS it follows the master
/// playlist to a media playlist and downloads the first segment; for raw streams
/// it reads the first few KB. This checks reachability and data flow, not decoding.
class ChannelChecker {
  final Duration timeout;
  final Duration slowAfter;
  ChannelChecker({this.timeout = const Duration(seconds: 12), this.slowAfter = const Duration(seconds: 5)});

  bool _cancelled = false;
  void cancel() => _cancelled = true;

  /// Runs checks with [concurrency] workers. Emits a result as soon as each finishes.
  Stream<CheckResult> run(List<Channel> channels, {int concurrency = 2}) {
    _cancelled = false;
    final out = StreamController<CheckResult>();
    var next = 0;

    Future<void> worker() async {
      while (!_cancelled && next < channels.length) {
        final c = channels[next++];
        if (c.url.startsWith('series:')) continue; // needs episode lookup; skipped
        final r = await checkOne(c);
        if (!out.isClosed && !_cancelled) out.add(r);
      }
    }

    Future(() async {
      await Future.wait([for (var i = 0; i < concurrency; i++) worker()]);
      await out.close();
    });
    return out.stream;
  }

  Future<CheckResult> checkOne(Channel c) async {
    final sw = Stopwatch()..start();
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8)
      ..userAgent = kUserAgent
      ..badCertificateCallback = (_, _, _) => true;
    try {
      final bytes = await _probe(client, Uri.parse(c.url)).timeout(timeout);
      sw.stop();
      if (bytes.error != null) return CheckResult(c, CheckStatus.failed, bytes.error!, sw.elapsedMilliseconds);
      final slow = sw.elapsed > slowAfter;
      return CheckResult(
          c, slow ? CheckStatus.slow : CheckStatus.ok, '${bytes.bytes} B', sw.elapsedMilliseconds);
    } on TimeoutException {
      return CheckResult(c, CheckStatus.failed, 'timeout', sw.elapsedMilliseconds);
    } catch (e) {
      return CheckResult(c, CheckStatus.failed, Log.redact(e.toString().split('\n').first), sw.elapsedMilliseconds);
    } finally {
      client.close(force: true);
    }
  }

  Future<({int bytes, String? error})> _probe(HttpClient client, Uri uri, {int depth = 0}) async {
    final req = await client.getUrl(uri);
    req.headers.set(HttpHeaders.rangeHeader, 'bytes=0-65535');
    final res = await req.close();
    if (res.statusCode != 200 && res.statusCode != 206) {
      await res.drain<void>().catchError((_) {});
      return (bytes: 0, error: 'HTTP ${res.statusCode}');
    }

    final isPlaylist = uri.path.toLowerCase().endsWith('.m3u8') ||
        (res.headers.contentType?.mimeType.contains('mpegurl') ?? false);

    if (isPlaylist && depth < 3) {
      final text = await res.transform(const Utf8Decoder(allowMalformed: true)).join();
      if (!text.trimLeft().startsWith('#EXTM3U')) return (bytes: text.length, error: 'bad_playlist');
      final lines = text.split(RegExp(r'\r?\n')).map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
      final uriLines = lines.where((l) => !l.startsWith('#')).toList();
      if (uriLines.isEmpty) return (bytes: text.length, error: 'empty_playlist');
      // Master playlist: follow first variant. Media playlist: fetch first segment.
      final target = uri.resolve(uriLines.first);
      return _probe(client, target, depth: depth + 1);
    }

    // Raw stream or segment: require real data to arrive.
    var total = 0;
    await for (final chunk in res) {
      total += chunk.length;
      if (total >= 4096) break;
    }
    if (total == 0) return (bytes: 0, error: 'no_data');
    return (bytes: total, error: null);
  }
}
