import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/models.dart';
import 'package:iptv_player/services/channel_checker.dart';

Channel _ch(String name, String url) => Channel(id: name, name: name, url: url, categoryId: 'c');

void main() {
  late io.HttpServer server;
  late String base;

  setUp(() async {
    server = await io.HttpServer.bind('127.0.0.1', 0);
    base = 'http://127.0.0.1:${server.port}';
    server.listen((req) async {
      final r = req.response;
      switch (req.uri.path) {
        case '/hls/master.m3u8':
          r.headers.contentType = io.ContentType('application', 'vnd.apple.mpegurl');
          r.write('#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=800000\nmedia.m3u8\n');
        case '/hls/media.m3u8':
          r.headers.contentType = io.ContentType('application', 'vnd.apple.mpegurl');
          r.write('#EXTM3U\n#EXT-X-TARGETDURATION:4\n#EXTINF:4,\nseg1.ts\n');
        case '/hls/seg1.ts':
          r.add(List<int>.filled(8192, 0x47));
        case '/raw/live.ts':
          r.add(List<int>.filled(8192, 0x47));
        case '/empty.m3u8':
          r.write('<html>not a playlist</html>');
        case '/hls/deadseg.m3u8':
          r.write('#EXTM3U\n#EXTINF:4,\nmissing.ts\n');
        case '/stall.ts':
          // headers sent, but no data ever arrives
          await r.flush();
          await Future<void>.delayed(const Duration(seconds: 10));
        default:
          r.statusCode = 404;
      }
      await r.close().catchError((_) {});
    });
  });

  tearDown(() => server.close(force: true));

  test('HLS maestro -> media -> segmento = OK', () async {
    final r = await ChannelChecker().checkOne(_ch('hls', '$base/hls/master.m3u8'));
    expect(r.status, CheckStatus.ok, reason: r.detail);
  });

  test('stream TS directo = OK', () async {
    final r = await ChannelChecker().checkOne(_ch('raw', '$base/raw/live.ts'));
    expect(r.status, CheckStatus.ok, reason: r.detail);
  });

  test('404 = fallo', () async {
    final r = await ChannelChecker().checkOne(_ch('dead', '$base/nope.m3u8'));
    expect(r.status, CheckStatus.failed);
    expect(r.detail, contains('404'));
  });

  test('playlist inválida = fallo', () async {
    final r = await ChannelChecker().checkOne(_ch('bad', '$base/empty.m3u8'));
    expect(r.status, CheckStatus.failed);
  });

  test('segmento caído dentro de una playlist = fallo', () async {
    final r = await ChannelChecker().checkOne(_ch('deadseg', '$base/hls/deadseg.m3u8'));
    expect(r.status, CheckStatus.failed);
    expect(r.detail, contains('404'));
  });

  test('servidor que se queda colgado = fallo por timeout', () async {
    final checker = ChannelChecker(timeout: const Duration(seconds: 2));
    final r = await checker.checkOne(_ch('stall', '$base/stall.ts'));
    expect(r.status, CheckStatus.failed);
    expect(r.detail, 'timeout');
  });

  test('run() prueba todos los canales y respeta la concurrencia', () async {
    final chans = [
      _ch('a', '$base/raw/live.ts'),
      _ch('b', '$base/hls/master.m3u8'),
      _ch('c', '$base/nope.ts'),
      _ch('d', '$base/raw/live.ts'),
    ];
    final results = await ChannelChecker().run(chans, concurrency: 2).toList();
    expect(results.length, 4);
    expect(results.where((r) => r.status == CheckStatus.failed).map((r) => r.channel.name), ['c']);
  });
}
