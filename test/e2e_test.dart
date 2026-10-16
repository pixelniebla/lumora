// End-to-end checks with the real pieces: Credential Manager, disk caches, a fake Xtream
// server, and a real mpv (libmpv from the Windows build) recording a stream to a file.
// Skipped unless `flutter build windows` has produced libmpv-2.dll.
import 'dart:convert';
import 'dart:io';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/app_state.dart';
import 'package:iptv_player/services/scheduler.dart';
import 'package:iptv_player/services/secrets.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Paths extends PathProviderPlatform {
  final String dir;
  _Paths(this.dir);
  @override
  Future<String?> getApplicationSupportPath() async => dir;
}

Uint8List _tsLike() {
  final b = Uint8List(400000);
  for (var i = 0; i < b.length; i++) {
    b[i] = i % 188 == 0 ? 0x47 : (i % 251);
  }
  b[1] = 0x40;
  b[2] = 0x11;
  b[3] = 0x10;
  return b;
}

void main() {
  test('flujo completo: migraciÃ³n, cachÃ© sin credenciales, EPG en cachÃ© y grabaciÃ³n programada real', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    HttpOverrides.global = null; // flutter_test blocks real HTTP by default

    final tmp = Directory.systemTemp.createTempSync('lumora_e2e_');
    PathProviderPlatform.instance = _Paths(tmp.path);
    final recDir = Directory('${tmp.path}${Platform.pathSeparator}rec')..createSync();

    // ---- fake Xtream server
    final requests = <String>[];
    final stream = _tsLike(); // 400 KB of fake transport stream, repeated by the server
    final server = await HttpServer.bind('127.0.0.1', 0);
    final base = 'http://127.0.0.1:${server.port}';
    server.listen((req) async {
      requests.add('${req.uri.path}${req.uri.hasQuery ? '?${req.uri.query}' : ''}');
      final q = req.uri.queryParameters, r = req.response;
      if (req.uri.path == '/player_api.php') {
        r.headers.contentType = io.ContentType.json;
        final ok = q['username'] == 'E2EUser' && q['password'] == 'E2EPass99';
        if (!ok) {
          r.write(jsonEncode({'user_info': {'auth': 0}}));
        } else {
          switch (q['action']) {
            case null:
              r.write(jsonEncode({'user_info': {'auth': 1}}));
            case 'get_live_categories':
              r.write(jsonEncode([{'category_id': '1', 'category_name': 'Pruebas'}]));
            case 'get_live_streams':
              r.write(jsonEncode([{'stream_id': 1, 'name': 'Canal Prueba', 'category_id': '1', 'epg_channel_id': 'prueba'}]));
            default:
              r.write('[]');
          }
        }
      } else if (req.uri.path == '/xmltv.php') {
        final n = DateTime.now().toUtc();
        String f(DateTime d) =>
            '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}'
            '${d.hour.toString().padLeft(2, '0')}${d.minute.toString().padLeft(2, '0')}00 +0000';
        r.write('<tv><programme start="${f(n.subtract(const Duration(minutes: 10)))}" '
            'stop="${f(n.add(const Duration(hours: 1)))}" channel="prueba"><title>Programa E2E</title></programme></tv>');
      } else if (req.uri.path == '/live/E2EUser/E2EPass99/1.ts') {
        r.headers.contentType = io.ContentType('video', 'mp2t');
        r.contentLength = stream.length;
        r.add(stream);
      } else {
        r.statusCode = 404;
      }
      await r.close();
    });

    // ---- a list saved by an old version: password in clear text in the preferences
    const name = 'E2E-Lumora-Test';
    final store = ChunkedSecretStore(WindowsSecretStore()); // the real Windows Credential Manager
    addTearDown(() async {
      await server.close(force: true);
      await store.delete(secretKey(name, 'pass'));
      tmp.deleteSync(recursive: true);
    });
    SharedPreferences.setMockInitialValues({
      'sources': jsonEncode([
        {'name': name, 'kind': 1, 'server': base, 'user': 'E2EUser', 'pass': 'E2EPass99'},
      ]),
    });

    final s = AppState();
    await s.initPrefs();
    expect(await store.read(secretKey(name, 'pass')), 'E2EPass99', reason: 'migrada a Credential Manager');
    final prefsRaw = (await SharedPreferences.getInstance()).getString('sources')!;
    expect(prefsRaw, isNot(contains('E2EPass99')));

    // ---- open: download, cache on disk without credentials, EPG
    await s.open(s.sources.single);
    expect(s.error, isNull);
    expect(s.library!.items.single.url, '$base/live/E2EUser/E2EPass99/1.m3u8');
    for (var i = 0; i < 50 && s.epg.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(s.epg.nowPlaying('prueba')?.title, 'Programa E2E');

    final cacheFile = tmp.listSync().whereType<Directory>().expand((d) => d.path.endsWith('cache') ? d.listSync() : <FileSystemEntity>[]).whereType<File>().single;
    final cacheJson = utf8.decode(gzip.decode(cacheFile.readAsBytesSync()));
    expect(cacheJson, isNot(contains('E2EUser')));
    expect(cacheJson, isNot(contains('E2EPass99')));
    expect(cacheJson, contains('{u}'));
    final epgFiles = Directory('${tmp.path}${Platform.pathSeparator}epg').listSync();
    expect(epgFiles, hasLength(1));
    final epgBytes = epgFiles.single.statSync().size;
    expect(epgBytes, greaterThan(20));

    // ---- second start: everything from disk, nothing downloaded again
    requests.clear();
    final s2 = AppState();
    await s2.initPrefs();
    expect(s2.sources.single.password, 'E2EPass99');
    await s2.open(s2.sources.single);
    for (var i = 0; i < 30 && s2.epg.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(s2.library!.items.single.url, '$base/live/E2EUser/E2EPass99/1.m3u8', reason: 'credenciales restauradas');
    expect(s2.epg.nowPlaying('prueba')?.title, 'Programa E2E');
    expect(requests, isEmpty, reason: 'cachÃ© reciente de lista y de EPG: sin descargas');

    // ---- scheduled recording with the real mpv: stream -> file
    s2.recordingPath = (c, t, d) => '${recDir.path}${Platform.pathSeparator}e2e.ts';
    String? finishedPath;
    s2.onRecordingFinished = (_, p) => finishedPath = p;
    final now = DateTime.now();
    await s2.addScheduled(ScheduledItem(
      id: 'record|e2e|1',
      kind: ScheduleKind.record,
      channelId: s2.library!.items.single.id,
      channelName: 'Canal Prueba',
      source: name,
      url: '$base/live/E2EUser/E2EPass99/1.ts',
      title: 'Grabacion E2E',
      start: now,
      stop: now.add(const Duration(seconds: 10)),
    ));
    final storedSchedule = (await SharedPreferences.getInstance()).getString('scheduled')!;
    expect(storedSchedule, isNot(contains('E2EPass99')));
    await s2.scheduleTick(now: now); // inside the 1 min lead-in -> starts a real BackgroundRecorder
    expect(s2.isRecordingNow('record|e2e|1'), isTrue);
    final out = File('${recDir.path}${Platform.pathSeparator}e2e.ts');
    for (var i = 0; i < 150 && !(out.existsSync() && out.lengthSync() > 100000); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    await s2.scheduleTick(now: now.add(const Duration(minutes: 5))); // past the end -> stops
    expect(s2.isRecordingNow('record|e2e|1'), isFalse);
    expect(finishedPath, out.path);
    expect(out.existsSync(), isTrue);
    expect(out.lengthSync(), greaterThan(100000), reason: 'el archivo grabado tiene datos del stream');
    expect(out.readAsBytesSync().sublist(0, 4), [0x47, 0x40, 0x11, 0x10], reason: 'los bytes del stream, tal cual');
    expect(s2.scheduled, isEmpty);
    // ignore: avoid_print
    print('E2E: grabaciÃ³n real = ${out.lengthSync()} bytes de ${stream.length}');
  }, timeout: const Timeout(Duration(minutes: 2)));
}
