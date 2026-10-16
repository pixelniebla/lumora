import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/services/stream_recorder.dart';

Uint8List _bytes(int n, int seed) => Uint8List.fromList(List.generate(n, (i) => (i * 31 + seed) % 256));

Future<void> _until(bool Function() ok, {int ms = 8000}) async {
  for (var t = 0; t < ms && !ok(); t += 50) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

void main() {
  late HttpServer server;
  late Directory dir;
  late String base;
  var rawHits = 0;
  var hlsPlaylistHits = 0;
  final segs = <int, Uint8List>{for (var i = 0; i < 6; i++) i: _bytes(5000 + i, i)};

  setUp(() async {
    rawHits = 0;
    hlsPlaylistHits = 0;
    dir = Directory.systemTemp.createTempSync('lumora_rec_');
    server = await HttpServer.bind('127.0.0.1', 0);
    base = 'http://127.0.0.1:${server.port}';
    server.listen((req) async {
      final r = req.response;
      final p = req.uri.path;
      if (p == '/live/u/p/1.ts') {
        rawHits++;
        r.headers.contentType = ContentType('video', 'mp2t');
        if (rawHits == 1) {
          r.add(_bytes(30000, 1));
          await r.close(); // the connection ends: the recorder must reconnect
          return;
        }
        r.add(_bytes(30000, 2));
        await r.flush();
        await Future<void>.delayed(const Duration(seconds: 30)); // then stays open (live)
      } else if (p == '/hls/master.m3u8') {
        r.headers.contentType = ContentType('application', 'vnd.apple.mpegurl');
        r.write('#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=500000\nlow/index.m3u8\n#EXT-X-STREAM-INF:BANDWIDTH=2000000\nhigh/index.m3u8\n');
      } else if (p == '/hls/high/index.m3u8') {
        hlsPlaylistHits++;
        r.headers.contentType = ContentType('application', 'vnd.apple.mpegurl');
        // live window: first reload shows segments 0-2, then 2-5 with ENDLIST
        final live = hlsPlaylistHits < 2;
        final from = live ? 0 : 2, to = live ? 2 : 5;
        r.write('#EXTM3U\n#EXT-X-TARGETDURATION:1\n#EXT-X-MEDIA-SEQUENCE:$from\n');
        for (var i = from; i <= to; i++) {
          r.write('#EXTINF:1.0,\nseg$i.ts\n');
        }
        if (!live) r.write('#EXT-X-ENDLIST\n');
      } else if (RegExp(r'^/hls/high/seg(\d)\.ts$').hasMatch(p)) {
        r.add(segs[int.parse(RegExp(r'seg(\d)').firstMatch(p)![1]!)]!);
      } else if (p == '/dead.ts') {
        r.statusCode = 503;
      } else {
        r.statusCode = 404;
      }
      await r.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
    dir.deleteSync(recursive: true);
  });

  test('stream directo: copia los bytes tal cual y se reconecta si se corta', () async {
    final out = '${dir.path}${Platform.pathSeparator}raw.ts';
    final rec = StreamRecorder(retryDelay: const Duration(milliseconds: 100));
    await rec.start('$base/live/u/p/1.ts', out);
    await _until(() => rec.bytesWritten >= 60000);
    await rec.stop();
    final got = File(out).readAsBytesSync();
    expect(rawHits, greaterThanOrEqualTo(2));
    expect(got.length, greaterThanOrEqualTo(60000));
    expect(got.sublist(0, 30000), _bytes(30000, 1)); // primera conexión
    expect(got.sublist(30000, 60000), _bytes(30000, 2)); // tras reconectar
  });

  test('HLS: sigue la mejor variante y añade los segmentos nuevos en orden, sin repetir', () async {
    final out = '${dir.path}${Platform.pathSeparator}hls.ts';
    final rec = StreamRecorder(retryDelay: const Duration(milliseconds: 100));
    await rec.start('$base/hls/master.m3u8', out);
    await _until(() => !rec.isRunning || hlsPlaylistHits >= 2, ms: 10000);
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    await rec.stop();
    final expected = BytesBuilder();
    for (var i = 0; i <= 5; i++) {
      expected.add(segs[i]!);
    }
    expect(File(out).readAsBytesSync(), expected.toBytes());
  });

  test('stop() cierra el archivo y es seguro llamarlo a mitad de una descarga', () async {
    final out = '${dir.path}${Platform.pathSeparator}stop.ts';
    final rec = StreamRecorder();
    await rec.start('$base/live/u/p/1.ts', out);
    await _until(() => rec.bytesWritten > 0);
    await rec.stop().timeout(const Duration(seconds: 5));
    expect(rec.bytesWritten, greaterThan(0));
    expect(File(out).lengthSync(), rec.bytesWritten);
  });

  test('error persistente: se rinde tras maxFailures sin colgarse', () async {
    final out = '${dir.path}${Platform.pathSeparator}dead.ts';
    final rec = StreamRecorder(maxFailures: 3, retryDelay: const Duration(milliseconds: 50));
    await rec.start('$base/dead.ts', out);
    await Future<void>.delayed(const Duration(seconds: 1));
    await rec.stop().timeout(const Duration(seconds: 5));
    expect(rec.lastError, isNotNull);
    expect(File(out).lengthSync(), 0);
  });
}
