import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/models.dart';
import 'package:iptv_player/services/m3u_parser.dart';

void main() {
  test('parsea una lista M3U con grupos, logos y EPG', () {
    const m3u = '''#EXTM3U url-tvg="http://epg.test/guide.xml"
#EXTINF:-1 tvg-id="la1" tvg-logo="http://l/1.png" group-title="Noticias",La 1
http://stream.test/live/1.m3u8
#EXTINF:-1 group-title="Cine",Pelicula X
http://stream.test/movie/u/p/5.mp4
#EXTINF:-1,Sin grupo
http://stream.test/x.ts
''';
    final lib = parseM3u(m3u);
    expect(lib.epgUrl, 'http://epg.test/guide.xml');
    expect(lib.items.length, 3);
    expect(lib.items[0].name, 'La 1');
    expect(lib.items[0].epgId, 'la1');
    expect(lib.items[0].logo, 'http://l/1.png');
    expect(lib.items[1].type, ContentType.movie);
    expect(lib.items[2].categoryId, 'Sin categoría');
    expect(lib.categories.length, 3);
  });
}
