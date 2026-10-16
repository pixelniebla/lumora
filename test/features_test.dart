import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/app_state.dart';
import 'package:iptv_player/l10n.dart' show errorText;
import 'package:iptv_player/models.dart';
import 'package:iptv_player/screens/scheduled_screen.dart';
import 'package:iptv_player/screens/sources_screen.dart';
import 'package:iptv_player/screens/test_screen.dart';
import 'package:iptv_player/services/backup.dart';
import 'package:iptv_player/services/errors.dart';
import 'package:iptv_player/services/scheduler.dart';
import 'package:iptv_player/services/secrets.dart';
import 'package:iptv_player/widgets/interaction.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

ScheduledItem _item(String id, ScheduleKind k, DateTime start, DateTime stop) => ScheduledItem(
    id: id, kind: k, channelId: 'c', channelName: 'Canal', source: 'S', url: 'http://h/live/u/p/1.m3u8', title: 'Peli', start: start, stop: stop);

class _FakeRecorder implements Recorder {
  @override
  String? path;
  bool started = false, stopped = false;
  String? url;
  @override
  Future<void> start(String u, String outPath) async {
    started = true;
    url = u;
    path = outPath;
  }

  @override
  Future<void> stop() async => stopped = true;
}

Widget _app(AppState s, Widget home) => ChangeNotifierProvider<AppState>.value(value: s, child: MaterialApp(home: home));

void main() {
  group('barra inactiva y doble clic', () {
    testWidgets('IdleVisibility oculta a los 3 s y reaparece al mover el ratÃ³n', (tester) async {
      final changes = <bool>[];
      final v = IdleVisibility(idle: const Duration(seconds: 3), onChanged: changes.add)..poke();
      expect(v.visible, isTrue);
      await tester.pump(const Duration(seconds: 2));
      expect(v.visible, isTrue);
      v.poke(); // movimiento: reinicia la cuenta atrÃ¡s
      await tester.pump(const Duration(seconds: 2));
      expect(v.visible, isTrue);
      await tester.pump(const Duration(seconds: 2));
      expect(v.visible, isFalse);
      v.poke();
      expect(v.visible, isTrue);
      expect(changes, [false, true]);
      v.dispose();
      await tester.pump(const Duration(seconds: 5));
      expect(changes, [false, true]); // dispose cancela el temporizador
    });

    test('DoubleClickDetector: dos pulsaciones cercanas en tiempo y espacio', () {
      var t = DateTime(2026);
      final d = DoubleClickDetector(clock: () => t);
      expect(d.press(const Offset(100, 100)), isFalse);
      t = t.add(const Duration(milliseconds: 200));
      expect(d.press(const Offset(103, 101)), isTrue);
      t = t.add(const Duration(milliseconds: 100));
      expect(d.press(const Offset(103, 101)), isFalse); // la tercera no cuenta como doble
      t = t.add(const Duration(milliseconds: 600));
      expect(d.press(const Offset(103, 101)), isFalse); // demasiado lento
      t = t.add(const Duration(milliseconds: 100));
      expect(d.press(const Offset(300, 300)), isFalse); // demasiado lejos
    });
  });

  group('programaciÃ³n', () {
    final t0 = DateTime(2026, 10, 20, 21, 0);

    test('planSchedule: grabaciÃ³n empieza 1 min antes y termina 2 min despuÃ©s', () {
      final it = _item('r', ScheduleKind.record, t0, t0.add(const Duration(hours: 1)));
      SchedulePlan plan(DateTime now, {bool rec = false}) =>
          planSchedule([it], now, recording: rec ? {'r'} : {}, notified: {});
      expect(plan(t0.subtract(const Duration(minutes: 5))).isEmpty, isTrue);
      expect(plan(t0.subtract(const Duration(seconds: 30))).startRecording, [it]);
      expect(plan(t0.add(const Duration(minutes: 30)), rec: true).isEmpty, isTrue);
      expect(plan(t0.add(const Duration(hours: 1, minutes: 3)), rec: true).stopRecording, [it]);
      expect(plan(t0.add(const Duration(hours: 2))).expired, [it]); // perdida: la app estaba cerrada
    });

    test('planSchedule: recordatorio 2 min antes, una sola vez, caduca', () {
      final it = _item('m', ScheduleKind.remind, t0, t0.add(const Duration(minutes: 30)));
      expect(planSchedule([it], t0.subtract(const Duration(minutes: 3)), recording: {}, notified: {}).isEmpty, isTrue);
      expect(planSchedule([it], t0.subtract(const Duration(minutes: 1)), recording: {}, notified: {}).remind, [it]);
      expect(planSchedule([it], t0.subtract(const Duration(minutes: 1)), recording: {}, notified: {'m'}).isEmpty, isTrue);
      expect(planSchedule([it], t0.add(const Duration(minutes: 10)), recording: {}, notified: {}).expired, [it]);
    });

    test('AppState: graba, avisa, guarda sin credenciales y sobrevive al reinicio', () async {
      final now = DateTime.now();
      SharedPreferences.setMockInitialValues({
        'sources': jsonEncode([
          {'name': 'S', 'kind': 1, 'server': 'http://h', 'user': 'u', 'pass': 'pw'},
        ]),
      });
      final store = MemorySecretStore();
      final s = AppState()..secretStore = store;
      await s.initPrefs();
      final rec = _FakeRecorder();
      s.recorderFactory = () => rec;
      s.recordingPath = (c, t, d) => 'C:/tmp/$c.ts';
      final finished = <String?>[];
      final reminded = <String>[];
      s.onRecordingFinished = (_, p) => finished.add(p);
      s.onReminder = (it) => reminded.add(it.id);

      final recItem = _item('rec', ScheduleKind.record, now.add(const Duration(seconds: 20)), now.add(const Duration(minutes: 30)));
      final remItem = _item('rem', ScheduleKind.remind, now.add(const Duration(minutes: 1)), now.add(const Duration(minutes: 30)));
      await s.addScheduled(recItem);
      await s.addScheduled(remItem);
      await s.scheduleTick(now: now);
      expect(rec.started, isTrue); // dentro del margen de 1 min
      expect(rec.url, 'http://h/live/u/p/1.m3u8');
      expect(s.isRecordingNow('rec'), isTrue);
      expect(reminded, ['rem']);
      await s.scheduleTick(now: now); // no repite
      expect(reminded, ['rem']);

      final raw = (await SharedPreferences.getInstance()).getString('scheduled')!;
      expect(raw, isNot(contains('/u/pw/')));
      expect(raw, isNot(contains('"pw"')));

      final s2 = AppState()..secretStore = store;
      await s2.initPrefs();
      expect(s2.scheduled.map((e) => e.id), containsAll(['rec', 'rem']));
      expect(s2.scheduled.firstWhere((e) => e.id == 'rec').url, 'http://h/live/u/pw/1.m3u8');

      await s.scheduleTick(now: now.add(const Duration(minutes: 40)));
      expect(rec.stopped, isTrue);
      expect(finished, ['C:/tmp/Canal.ts']);
      expect(s.scheduled, isEmpty);
    });

    test('quitar una grabaciÃ³n en curso la detiene', () async {
      SharedPreferences.setMockInitialValues({});
      final s = AppState()..secretStore = MemorySecretStore();
      await s.initPrefs();
      final rec = _FakeRecorder();
      s.recorderFactory = () => rec;
      s.recordingPath = (c, t, d) => 'x.ts';
      final now = DateTime.now();
      await s.addScheduled(_item('a', ScheduleKind.record, now, now.add(const Duration(hours: 1))));
      await s.scheduleTick(now: now);
      expect(rec.started, isTrue);
      await s.removeScheduled('a');
      expect(rec.stopped, isTrue);
      expect(s.isScheduled('a'), isFalse);
    });

    testWidgets('pantalla Programadas lista y quita elementos', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final s = AppState()..secretStore = MemorySecretStore();
      await tester.runAsync(s.initPrefs);
      final now = DateTime.now();
      await tester.runAsync(() => s.addScheduled(_item('a', ScheduleKind.remind, now.add(const Duration(hours: 3)), now.add(const Duration(hours: 4)))));
      await tester.pumpWidget(_app(s, const ScheduledScreen()));
      expect(find.text('Peli'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      expect(find.text('Peli'), findsNothing);
    });
  });

  group('copia de seguridad', () {
    test('BackupCodec: ida y vuelta, frase incorrecta y archivo ajeno', () async {
      final data = {'app': 'lumora', 'x': 'Ã±andÃº âœ“', 'n': 3};
      final file = await BackupCodec.encrypt(data, 'frase-secreta', iterations: 1000);
      expect(utf8.decode(file), isNot(contains('Ã±andÃº')));
      expect(await BackupCodec.decrypt(file, 'frase-secreta'), data);
      await expectLater(BackupCodec.decrypt(file, 'otra-frase'),
          throwsA(isA<LocalizedError>().having((e) => e.key, 'key', 'err_backup_pass')));
      await expectLater(BackupCodec.decrypt(Uint8List.fromList(utf8.encode('{"hola":1}')), 'x'),
          throwsA(isA<LocalizedError>().having((e) => e.key, 'key', 'err_backup_file')));
      await expectLater(BackupCodec.decrypt(Uint8List.fromList([1, 2, 3]), 'x'),
          throwsA(isA<LocalizedError>().having((e) => e.key, 'key', 'err_backup_file')));
    });

    test('exportar en un AppState e importar en otro limpio restaura todo', () async {
      SharedPreferences.setMockInitialValues({
        'sources': jsonEncode([
          {'name': 'S', 'kind': 1, 'server': 'http://h', 'user': 'u', 'pass': 'pw12345'},
        ]),
        'favorites': ['a', 'b'],
        'favOrder': ['b', 'a'],
        'broken': ['z'],
        'lockedCats': ['c9'],
      });
      final a = AppState()..secretStore = MemorySecretStore();
      await a.initPrefs();
      await a.setLang('fr');
      await a.setPin('1234');
      await a.saveResume('m1', 60000, 600000, force: true);
      final file = await BackupCodec.encrypt(a.exportData(), 'pass-123', iterations: 1000);

      SharedPreferences.setMockInitialValues({});
      final store = MemorySecretStore();
      final b = AppState()..secretStore = store;
      await b.initPrefs();
      await b.importData(await BackupCodec.decrypt(file, 'pass-123'));
      expect(b.sources.single.password, 'pw12345');
      expect(store.data[secretKey('S', 'pass')], 'pw12345'); // y de vuelta al almacÃ©n seguro
      expect(b.orderedFavorites().length, 0); // sin biblioteca cargada no hay canales...
      expect(b.favorites, {'a', 'b'});
      expect(b.favOrder, ['b', 'a']);
      expect(b.broken, {'z'});
      expect(b.lockedCats, {'c9'});
      expect(b.lang, 'fr');
      expect(b.verifyPin('1234'), isTrue);
      expect(b.resumeFor('m1')!.posMs, 60000);
      expect((await SharedPreferences.getInstance()).getString('sources'), isNot(contains('pw12345')));
    });

    test('importar rechaza JSON que no es de Lumora', () async {
      SharedPreferences.setMockInitialValues({});
      final s = AppState()..secretStore = MemorySecretStore();
      await s.initPrefs();
      await expectLater(s.importData({'otra': 'cosa'}), throwsA(isA<LocalizedError>()));
    });
  });

  group('diagnÃ³stico', () {
    test('no incluye credenciales ni siquiera si estÃ¡n en el log', () async {
      SharedPreferences.setMockInitialValues({
        'sources': jsonEncode([
          {'name': 'S', 'kind': 1, 'server': 'http://h', 'user': 'bob', 'pass': 'pw12345'},
        ]),
      });
      final s = AppState()..secretStore = MemorySecretStore();
      await s.initPrefs();
      final d = await s.diagnostics();
      expect(d, startsWith('Lumora'));
      expect(d, contains('Lists: 1 (xtream)'));
      expect(d, isNot(contains('pw12345')));
      expect(d, isNot(contains('bob')));
    });
  });

  group('pantallas', () {
    testWidgets('Listas: el error se muestra traducido y sin credenciales', (tester) async {
      SharedPreferences.setMockInitialValues({'lang': 'en'});
      final s = AppState()..secretStore = MemorySecretStore();
      await tester.runAsync(s.initPrefs);
      s.error = errorText(s.lang, const LocalizedError('err_bad_credentials'));
      await tester.pumpWidget(_app(s, const SourcesScreen()));
      expect(find.text('Wrong username or password'), findsOneWidget);

      s.error = errorText(s.lang, Exception('Failed host lookup: http://h/player_api.php?username=bob&password=pw'));
      s.notifyListeners();
      await tester.pump();
      expect(find.textContaining('bob'), findsNothing);
      expect(find.textContaining('password=***'), findsOneWidget);
    });

    testWidgets('Probar canales: una prueba parcial fusiona con lo marcado antes', (tester) async {
      HttpOverrides.global = null; // flutter_test bloquea la red por defecto
      final server = (await tester.runAsync(() => HttpServer.bind('127.0.0.1', 0)))!;
      addTearDown(() => server.close(force: true));
      server.listen((req) async {
        if (req.uri.path == '/ok.ts') {
          req.response.add(List.filled(8000, 1));
        } else {
          req.response.statusCode = 404;
        }
        await req.response.close();
      });
      final base = 'http://127.0.0.1:${server.port}';
      SharedPreferences.setMockInitialValues({
        'broken': ['ok', 'old'], // 'ok' ahora funciona; 'old' no se vuelve a probar
      });
      final s = AppState()..secretStore = MemorySecretStore();
      await tester.runAsync(s.initPrefs);
      s.library = LoadedLibrary(const [Category('c', 'C')], [
        Channel(id: 'ok', name: 'Bueno', url: '$base/ok.ts', categoryId: 'c'),
        Channel(id: 'bad', name: 'Malo', url: '$base/bad.ts', categoryId: 'c'),
      ]);
      await tester.pumpWidget(_app(s, const TestScreen()));
      // El botón se pulsa dentro de runAsync para que la red real avance fuera del reloj falso.
      await tester.runAsync(() async => tester.widget<FilledButton>(find.byType(FilledButton)).onPressed!());
      for (var i = 0; i < 60 && !(s.broken.contains('bad') && !s.broken.contains('ok')); i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100))); // red real
        await tester.pump(); // y que la pantalla procese los resultados
      }      expect(s.broken, {'bad', 'old'});
      // copiar fallos no exporta credenciales
      expect(find.text('Malo'), findsOneWidget);
    });
  });
}
