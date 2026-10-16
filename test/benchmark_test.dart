import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/models.dart';
import 'package:iptv_player/services/m3u_parser.dart';

String _bigM3u(int n) {
  final b = StringBuffer('#EXTM3U url-tvg="http://epg.test/g.xml"\n');
  for (var i = 0; i < n; i++) {
    b.writeln('#EXTINF:-1 tvg-id="ch$i" tvg-logo="http://l/$i.png" group-title="Grupo ${i % 120}",Canal número $i HD');
    b.writeln('http://server.test:8080/live/user/pass/$i.m3u8');
  }
  return b.toString();
}

void main() {
  for (final n in [50000, 200000]) {
  test('benchmark: lista de $n canales (parseo, caché, filtrado)', () async {
    final text = _bigM3u(n);
    final mb = (text.length / 1048576).toStringAsFixed(1);

    final sw = Stopwatch()..start();
    final lib = parseM3u(text, src: 'bench');
    final parseMs = sw.elapsedMilliseconds;
    expect(lib.items.length, n);

    sw
      ..reset()
      ..start();
    final gz = gzip.encode(utf8.encode(jsonEncode(lib.toJson())));
    final encMs = sw.elapsedMilliseconds;

    sw
      ..reset()
      ..start();
    final back = LoadedLibrary.fromJson(jsonDecode(utf8.decode(gzip.decode(gz))) as Map<String, dynamic>);
    final decMs = sw.elapsedMilliseconds;
    expect(back.items.length, n);

    // Opening from cache (decode only) vs. downloading + parsing every time
    sw
      ..reset()
      ..start();
    var hits = 0;
    for (final c in back.items) {
      if (c.type == ContentType.live && c.lower.contains('número 49999')) hits++;
    }
    final searchMs = sw.elapsedMilliseconds;
    expect(hits, greaterThan(0));

    // The same parse in a background isolate must not be meaningfully slower overall,
    // and the point is that the UI thread is free meanwhile.
    sw
      ..reset()
      ..start();
    final bg = await compute(_parseLen, text);
    final bgMs = sw.elapsedMilliseconds;
    expect(bg, n);

    // ignore: avoid_print
    print('BENCH $n canales ($mb MB M3U): parseo=${parseMs}ms  caché-gzip=${gz.length ~/ 1024}KB '
        'guardar=${encMs}ms  abrir-desde-caché=${decMs}ms  búsqueda=${searchMs}ms  parseo-en-isolate=${bgMs}ms');
    expect(searchMs, lessThan(1000));
  }, timeout: const Timeout(Duration(minutes: 3)));
  }
}

int _parseLen(String t) => parseM3u(t, src: 'bench').items.length;
