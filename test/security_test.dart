import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/app_state.dart';
import 'package:iptv_player/l10n.dart';
import 'package:iptv_player/models.dart';
import 'package:iptv_player/services/epg_service.dart';
import 'package:iptv_player/services/errors.dart';
import 'package:iptv_player/services/log.dart';
import 'package:iptv_player/services/player_service.dart' show playerProfileKey;
import 'package:iptv_player/services/secrets.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _legacySource = {
  'name': 'IPTV',
  'kind': 1,
  'server': 'http://h:80',
  'user': 'bob',
  'pass': 'S3cr3t&"x',
};

Channel _xt(String id) =>
    Channel(id: id, name: id, url: 'http://h:80/live/bob/S3cr3t&"x/$id.m3u8', categoryId: 'c', source: 'IPTV');

class _BrokenStore implements SecretStore {
  @override
  Future<String?> read(String key) => throw UnsupportedError('no store');
  @override
  Future<void> write(String key, String value) => throw UnsupportedError('no store');
  @override
  Future<void> delete(String key) => throw UnsupportedError('no store');
}

void main() {
  group('redacción', () {
    test('Log.redact cubre query, rutas Xtream y user:pass@', () {
      expect(Log.redact('GET http://h/player_api.php?username=bob&password=pw&action=x'),
          'GET http://h/player_api.php?username=***&password=***&action=x');
      expect(Log.redact('http://h/live/bob/pw/12.m3u8'), 'http://h/live/***/***/12.m3u8');
      expect(Log.redact('http://h/movie/bob/pw/12.mkv'), 'http://h/movie/***/***/12.mkv');
      expect(Log.redact('http://h/series/bob/pw/12.mp4'), 'http://h/series/***/***/12.mp4');
      expect(Log.redact('http://bob:pw@h/x'), 'http://***:***@h/x');
      final err = Log.redact(
          'ClientException: Connection closed, uri=http://h:80/player_api.php?username=bob&password=pw');
      expect(err, isNot(contains('bob')));
      expect(err, isNot(contains('pw')));
    });

    test('errorText traduce los LocalizedError y redacta el resto', () {
      expect(errorText('es', const LocalizedError('err_bad_credentials')), 'Usuario o contraseña incorrectos');
      expect(errorText('en', const LocalizedError('err_bad_credentials')), 'Wrong username or password');
      expect(errorText('fr', const LocalizedError('err_status', {'code': '503'})), contains('503'));
      expect(errorText('pt', Exception('falhou http://h/live/u/p/1.ts')), isNot(contains('/u/p/')));
    });

    test('todas las claves de error existen en los 4 idiomas', () {
      const keys = ['err_status', 'err_bad_credentials', 'err_no_channels', 'err_list_empty', 'err_https',
        'err_not_found', 'err_checksum', 'err_epg', 'bad_playlist', 'empty_playlist', 'no_data', 'timeout'];
      for (final lang in supportedLanguages.keys) {
        for (final k in keys) {
          if (k != 'timeout') expect(translate(lang, k), isNot(k), reason: '$lang/$k');
        }
      }
      expect(translate('en', 'err_no_channels'), isNot(translate('es', 'err_no_channels')));
    });

    test('detailText traduce códigos del comprobador y redacta lo demás', () {
      expect(detailText('en', 'bad_playlist'), 'invalid playlist');
      expect(detailText('en', 'HTTP 404'), 'HTTP 404');
    });
  });

  group('UrlScrubber', () {
    test('ida y vuelta con caracteres especiales en el JSON', () {
      final lib = LoadedLibrary(const [Category('c', 'x')], [_xt('1')],
          epgUrl: 'http://h:80/xmltv.php?username=bob&password=S3cr3t');
      final scrubbed = UrlScrubber.scrub(jsonEncode(lib.toJson()));
      expect(scrubbed, isNot(contains('bob')));
      expect(scrubbed, isNot(contains('S3cr3t')));
      final back = LoadedLibrary.fromJson(
          jsonDecode(UrlScrubber.hydrateJson(scrubbed, 'bob', 'S3cr3t&"x')) as Map<String, dynamic>);
      expect(back.items.single.url, 'http://h:80/live/bob/S3cr3t&"x/1.m3u8');
      expect(back.epgUrl, contains('username=bob&password=S3cr3t'));
    });
  });

  test('Windows Credential Manager: escribe, lee y borra (clave de prueba)', () async {
    final s = WindowsSecretStore();
    const k = 'unit-test.tmp';
    await s.write(k, 'p4ss/ü&"');
    expect(await s.read(k), 'p4ss/ü&"');
    await s.write(k, 'otra');
    expect(await s.read(k), 'otra');
    await s.delete(k);
    expect(await s.read(k), isNull);
  }, skip: !Platform.isWindows);

  group('credenciales en disco', () {
    late MemorySecretStore store;

    Future<AppState> boot() async {
      final s = AppState()..secretStore = store;
      await s.initPrefs();
      return s;
    }

    setUp(() {
      store = MemorySecretStore();
      SharedPreferences.setMockInitialValues({'sources': jsonEncode([_legacySource])});
    });

    test('migra la contraseña en claro al almacén seguro y sigue funcionando', () async {
      final s = await boot();
      expect(s.sources.single.password, 'S3cr3t&"x'); // en memoria sigue disponible
      final raw = (await SharedPreferences.getInstance()).getString('sources')!;
      expect(raw, isNot(contains('S3cr3t')));
      expect(store.data[secretKey('IPTV', 'pass')], 'S3cr3t&"x');

      final s2 = await boot(); // segundo arranque: viene solo del almacén
      expect(s2.sources.single.password, 'S3cr3t&"x');
      expect(s2.sources.single.username, 'bob');
    });

    test('si el almacén no está disponible no se pierde la contraseña', () async {
      final s = AppState()..secretStore = _BrokenStore();
      await s.initPrefs();
      expect(s.sources.single.password, 'S3cr3t&"x');
      final s2 = AppState()..secretStore = _BrokenStore();
      await s2.initPrefs();
      expect(s2.sources.single.password, 'S3cr3t&"x');
    });

    test('añadir una lista nueva guarda la contraseña fuera de las preferencias', () async {
      final s = await boot();
      s.sources.add(const Source(name: 'Otra', kind: SourceKind.xtream, server: 'http://z', username: 'u', password: 'pw1'));
      await s.removeSource(s.sources.first); // fuerza _saveSources con la lista restante
      final raw = (await SharedPreferences.getInstance()).getString('sources')!;
      expect(raw, isNot(contains('pw1')));
      expect(store.data[secretKey('Otra', 'pass')], 'pw1');
      expect(store.data.containsKey(secretKey('IPTV', 'pass')), isFalse); // borrada con la lista
    });

    test('el historial no guarda usuario ni contraseña y se rehidrata', () async {
      final s = await boot();
      await s.addToHistory(_xt('7'));
      final raw = (await SharedPreferences.getInstance()).getString('history')!;
      expect(raw, isNot(contains('bob')));
      expect(raw, isNot(contains('S3cr3t')));
      final s2 = await boot();
      expect(s2.history.single.url, 'http://h:80/live/bob/S3cr3t&"x/7.m3u8');
    });
  });

  group('prueba de canales', () {
    test('updateBroken fusiona: solo cambia lo probado', () async {
      SharedPreferences.setMockInitialValues({'broken': ['a', 'b', 'z']});
      final s = AppState();
      await s.initPrefs();
      // se prueban a, b, c; ahora a funciona, b sigue roto, c falla; z no se probó
      await s.updateBroken(tested: {'a', 'b', 'c'}, failed: {'b', 'c'});
      expect(s.broken, {'b', 'c', 'z'});
      final s2 = AppState();
      await s2.initPrefs();
      expect(s2.broken, {'b', 'c', 'z'});
    });
  });

  group('EPG', () {
    test('epgUrlsFor reúne la guía de todas las listas, no solo la primera', () {
      const x1 = Source(name: 'A', kind: SourceKind.xtream, server: 'http://a', username: 'u', password: 'p');
      const x2 = Source(name: 'B', kind: SourceKind.xtream, server: 'http://b', username: 'u', password: 'p');
      const m = Source(name: 'C', kind: SourceKind.m3u, m3uUrl: 'http://c/l.m3u', epgUrl: 'http://c/g.xml');
      const lib = LoadedLibrary([], []);
      expect(AppState.epgUrlsFor([x1, x2, m], lib), {
        'http://a/xmltv.php?username=u&password=p',
        'http://b/xmltv.php?username=u&password=p',
        'http://c/g.xml',
      });
    });

    group('caché en disco', () {
      late HttpServer server;
      late Directory dir;
      var hits = 0;
      var fail = false;
      late String url;

      String xml() {
        final now = DateTime.now().toUtc();
        String f(DateTime d) =>
            '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}'
            '${d.hour.toString().padLeft(2, '0')}${d.minute.toString().padLeft(2, '0')}00 +0000';
        return '<tv><programme start="${f(now.subtract(const Duration(minutes: 10)))}" '
            'stop="${f(now.add(const Duration(hours: 1)))}" channel="la1"><title>Ahora</title><desc>d</desc></programme>'
            '<programme start="${f(now)}" stop="${f(now.add(const Duration(hours: 1)))}" channel="otro"><title>No</title></programme></tv>';
      }

      setUp(() async {
        hits = 0;
        fail = false;
        dir = Directory.systemTemp.createTempSync('lumora_epg_');
        server = await HttpServer.bind('127.0.0.1', 0);
        url = 'http://127.0.0.1:${server.port}/g.xml';
        server.listen((req) async {
          hits++;
          if (fail) req.response.statusCode = 500;
          req.response.write(xml());
          await req.response.close();
        });
      });

      tearDown(() async {
        await server.close(force: true);
        dir.deleteSync(recursive: true);
      });

      test('no vuelve a descargar mientras la caché sea reciente', () async {
        final epg = EpgService();
        await epg.load([url], {'la1'}, cacheDir: dir);
        expect(hits, 1);
        expect(epg.nowPlaying('la1')?.title, 'Ahora');
        expect(epg.hasGuide('otro'), isFalse); // filtrado a los canales de la lista

        final again = EpgService();
        await again.load([url], {'la1'}, cacheDir: dir);
        expect(hits, 1);
        expect(again.nowPlaying('la1')?.title, 'Ahora');
      });

      test('refresca si tiene más de 6 h o si cambian los canales pedidos', () async {
        await EpgService().load([url], {'la1'}, cacheDir: dir);
        await EpgService().load([url], {'la1'}, cacheDir: dir, now: DateTime.now().add(const Duration(hours: 7)));
        expect(hits, 2);
        await EpgService().load([url], {'la1', 'otro'}, cacheDir: dir);
        expect(hits, 3);
      });

      test('si la descarga falla usa la caché vieja', () async {
        await EpgService().load([url], {'la1'}, cacheDir: dir);
        fail = true;
        final epg = EpgService();
        await epg.load([url], {'la1'}, cacheDir: dir, now: DateTime.now().add(const Duration(hours: 9)));
        expect(hits, 2);
        expect(epg.nowPlaying('la1')?.title, 'Ahora');
      });

      test('fusiona varias guías y falla solo si ninguna carga', () async {
        final epg = EpgService();
        await epg.load(['http://127.0.0.1:1/x.xml', url], {'la1'}, cacheDir: dir);
        expect(epg.hasGuide('la1'), isTrue);
        await expectLater(EpgService().load(['http://127.0.0.1:1/x.xml'], {'la1'}, cacheDir: dir), throwsA(anything));
      });
    });
  });

  test('perfil del reproductor: cambia con perfil y ajustes (zapping no reconfigura)', () async {
    SharedPreferences.setMockInitialValues({});
    final s = AppState();
    await s.initPrefs();
    final live = playerProfileKey(s);
    expect(playerProfileKey(s), live);
    expect(playerProfileKey(s, live: false), isNot(live));
    expect(playerProfileKey(s, light: true, lowQuality: true), isNot(live));
    await s.setHwdec(false);
    expect(playerProfileKey(s), isNot(live));
  });
}
