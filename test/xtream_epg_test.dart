import 'dart:convert';
import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/models.dart';
import 'package:iptv_player/services/epg_service.dart';
import 'package:iptv_player/services/errors.dart';
import 'package:iptv_player/services/player_service.dart' show alternateLiveUrl;
import 'package:iptv_player/services/xtream_client.dart';

void main() {
  group('XtreamClient', () {
    late io.HttpServer server;
    late String base;
    var requests = <String>[];
    var failSeries = false;

    setUp(() async {
      requests = [];
      failSeries = false;
      server = await io.HttpServer.bind('127.0.0.1', 0);
      base = 'http://127.0.0.1:${server.port}';
      server.listen((req) async {
        final q = req.uri.queryParameters;
        requests.add(q['action'] ?? 'auth');
        final r = req.response..headers.contentType = io.ContentType.json;
        if (q['password'] == 'bad') {
          r.write(jsonEncode({'user_info': {'auth': 0}}));
        } else {
          switch (q['action']) {
            case null:
              r.write(jsonEncode({'user_info': {'auth': 1}}));
            case 'get_live_categories':
              r.write(jsonEncode([{'category_id': '1', 'category_name': 'Noticias'}]));
            case 'get_live_streams':
              r.write(jsonEncode([
                {'stream_id': 10, 'name': 'La 1', 'category_id': '1', 'epg_channel_id': 'la1', 'stream_icon': 'http://x/l.png'},
                {'stream_id': 11, 'name': 'La 2', 'category_id': '1'},
              ]));
            case 'get_vod_categories':
              r.write(jsonEncode([{'category_id': '5', 'category_name': 'Cine'}]));
            case 'get_vod_streams':
              r.write(jsonEncode([{'stream_id': 20, 'name': 'Peli', 'category_id': '5', 'container_extension': 'mkv'}]));
            case 'get_series_categories' || 'get_series':
              if (failSeries) {
                r.statusCode = 500;
              } else {
                r.write(q['action'] == 'get_series' ? jsonEncode([{'series_id': 30, 'name': 'Serie', 'category_id': '7'}]) : '[]');
              }
            case 'get_series_info':
              r.write(jsonEncode({
                'episodes': {
                  '2': [{'id': '202', 'episode_num': 1, 'title': 'B', 'container_extension': 'mp4'}],
                  '1': [{'id': '101', 'episode_num': 1, 'title': 'A'}],
                }
              }));
            default:
              r.statusCode = 404;
          }
        }
        await r.close();
      });
    });

    tearDown(() => server.close(force: true));

    test('carga todo en paralelo y prefija ids con el nombre de la lista', () async {
      final lib = await XtreamClient(base, 'u', 'p', src: 'IPTV').load();
      expect(lib.items.where((c) => c.type == ContentType.live).length, 2);
      final la1 = lib.items.firstWhere((c) => c.name == 'La 1');
      expect(la1.id, 'IPTV|live_10');
      expect(la1.categoryId, 'IPTV|live_1');
      expect(la1.epgId, 'la1');
      expect(la1.source, 'IPTV');
      expect(la1.url, '$base/live/u/p/10.m3u8');
      expect(lib.items.firstWhere((c) => c.type == ContentType.movie).url, endsWith('/movie/u/p/20.mkv'));
      expect(lib.items.firstWhere((c) => c.type == ContentType.series).url, 'series:30');
      expect(lib.epgUrl, contains('xmltv.php'));
      expect(requests.toSet(), containsAll(['auth', 'get_live_streams', 'get_vod_streams', 'get_series']));
    });

    test('una sección que el proveedor no ofrece no rompe las demás', () async {
      failSeries = true;
      final lib = await XtreamClient(base, 'u', 'p').load();
      expect(lib.items.where((c) => c.type == ContentType.live), isNotEmpty);
      expect(lib.items.where((c) => c.type == ContentType.series), isEmpty);
    });

    test('credenciales incorrectas lanzan error claro', () async {
      expect(
        () => XtreamClient(base, 'u', 'bad').load(),
        throwsA(isA<LocalizedError>().having((e) => e.key, 'key', 'err_bad_credentials')),
      );
    });

    test('episodios ordenados por temporada', () async {
      final eps = await XtreamClient(base, 'u', 'p', src: 'S').seriesEpisodes('30', 'cat');
      expect(eps.map((e) => e.name), ['T1 · E1 · A', 'T2 · E1 · B']);
      expect(eps.first.url, endsWith('/series/u/p/101.mp4'));
    });
  });

  group('EPG', () {
    String fmt(DateTime d, String off) =>
        '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}'
        '${d.hour.toString().padLeft(2, '0')}${d.minute.toString().padLeft(2, '0')}00 $off';

    test('streaming parser: filtra por canal y ventana, y respeta zonas horarias', () {
      final now = DateTime.now().toUtc();
      final xml = '''<?xml version="1.0"?><tv>
<channel id="la1"><display-name>La 1</display-name></channel>
<programme start="${fmt(now.subtract(const Duration(minutes: 30)), '+0000')}" stop="${fmt(now.add(const Duration(minutes: 30)), '+0000')}" channel="la1"><title>Ahora</title><desc>Descripción &amp; más</desc></programme>
<programme start="${fmt(now.add(const Duration(minutes: 30)), '+0000')}" stop="${fmt(now.add(const Duration(hours: 1)), '+0000')}" channel="la1"><title><![CDATA[Luego]]></title></programme>
<programme start="${fmt(now.add(const Duration(minutes: 30)), '+0000')}" stop="${fmt(now.add(const Duration(hours: 1)), '+0000')}" channel="otro"><title>No pedido</title></programme>
<programme start="${fmt(now.subtract(const Duration(days: 5)), '+0000')}" stop="${fmt(now.subtract(const Duration(days: 5, hours: -1)), '+0000')}" channel="la1"><title>Antiguo</title></programme>
</tv>''';
      final data = parseXmltv(EpgJob(utf8.encode(xml) as dynamic, {'la1'}, now.millisecondsSinceEpoch));
      expect(data.keys, ['la1']);
      expect(data['la1']!.map((p) => p.title), ['Ahora', 'Luego']);
      expect(data['la1']!.first.description, 'Descripción & más');
      expect(data['la1']!.first.isOn(DateTime.now()), isTrue);
    });

    test('hora XMLTV con desfase', () {
      final a = parseXmltvTime('20240101120000 +0100')!;
      final b = parseXmltvTime('20240101110000 +0000')!;
      expect(a.isAtSameMomentAs(b), isTrue);
      expect(parseXmltvTime('basura'), isNull);
    });
  });

  test('alternateLiveUrl alterna m3u8 <-> ts solo en rutas Xtream live', () {
    expect(alternateLiveUrl('http://h/live/u/p/1.m3u8'), 'http://h/live/u/p/1.ts');
    expect(alternateLiveUrl('http://h/live/u/p/1.ts'), 'http://h/live/u/p/1.m3u8');
    expect(alternateLiveUrl('http://h/movie/u/p/1.mp4'), isNull);
  });
}
