import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/app_state.dart';
import 'package:iptv_player/models.dart';
import 'package:iptv_player/services/secrets.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const m3u = 'http://prov.example/get.php?username=bob&password=SuperSecret99&type=m3u';

  test('ScrubSpec.m3uSecrets toma solo valores de credenciales de al menos 6 caracteres', () {
    final s = ScrubSpec.m3uSecrets('http://h/p.m3u?token=abcdef123456&type=m3u&user=bob&key=xyz');
    expect(s.values, ['abcdef123456']); // user=bob y key=xyz son demasiado cortos
    expect(ScrubSpec.m3uSecrets('http://h/p.m3u'), isEmpty);
  });

  test('ScrubSpec M3U: ida y vuelta de URLs y de un JSON completo', () {
    final spec = ScrubSpec(secrets: ScrubSpec.m3uSecrets(m3u));
    const url = 'http://cdn.example/stream/1.ts?auth=SuperSecret99&x=1';
    final scrubbed = spec.scrubUrl(url);
    expect(scrubbed, isNot(contains('SuperSecret99')));
    expect(spec.hydrateUrl(scrubbed), url);

    final lib = LoadedLibrary(const [], [Channel(id: '1', name: 'Uno', url: url, categoryId: 'c')]);
    final json = spec.scrubText(jsonEncode(lib.toJson()));
    expect(json, isNot(contains('SuperSecret99')));
    final back = LoadedLibrary.fromJson(jsonDecode(spec.hydrateText(json)) as Map<String, dynamic>);
    expect(back.items.single.url, url);
  });

  test('ScrubSpec Xtream + M3U a la vez', () {
    const spec = ScrubSpec(user: 'bob', pass: 'pw', secrets: {'{s0}': 'TOKEN-123456'});
    const url = 'http://h/live/bob/pw/9.m3u8?t=TOKEN-123456';
    expect(spec.scrubUrl(url), 'http://h/live/{u}/{p}/9.m3u8?t={s0}');
    expect(spec.hydrateUrl(spec.scrubUrl(url)), url);
  });

  test('ChunkedSecretStore guarda valores grandes en varias entradas y los lee enteros', () async {
    final mem = MemorySecretStore();
    final store = ChunkedSecretStore(mem);
    final big = 'http://h/p.m3u?token=${List.generate(5000, (i) => 'ñ${i % 10}').join()}';
    await store.write('k', big);
    expect(mem.data.length, greaterThan(2));
    expect(mem.data.values.every((v) => v.length <= 2000), isTrue);
    expect(await store.read('k'), big);

    await store.write('k', 'corto'); // vuelve a un valor simple y limpia los trozos
    expect(await store.read('k'), 'corto');
    expect(mem.data.keys, ['k']);

    await store.write('k', big);
    await store.delete('k');
    expect(mem.data, isEmpty);
    expect(await store.read('k'), isNull);
  });

  test('ChunkedSecretStore lee valores antiguos (sin trozos)', () async {
    final mem = MemorySecretStore()..data['k'] = 'plano';
    expect(await ChunkedSecretStore(mem).read('k'), 'plano');
  });

  test('lista M3U: URL con token fuera de prefs y historial sin token; sobrevive al reinicio', () async {
    final store = MemorySecretStore();
    SharedPreferences.setMockInitialValues({
      'sources': jsonEncode([
        {'name': 'M', 'kind': 0, 'm3u': m3u},
      ]),
    });
    AppState s = AppState()..secretStore = store;
    await s.initPrefs();
    final raw = (await SharedPreferences.getInstance()).getString('sources')!;
    expect(raw, isNot(contains('SuperSecret99')));
    expect(s.sources.single.m3uUrl, m3u);

    await s.addToHistory(Channel(
        id: 'a', name: 'A', url: 'http://cdn/x.ts?auth=SuperSecret99', categoryId: 'c', source: 'M'));
    final hist = (await SharedPreferences.getInstance()).getString('history')!;
    expect(hist, isNot(contains('SuperSecret99')));

    s = AppState()..secretStore = store;
    await s.initPrefs();
    expect(s.sources.single.m3uUrl, m3u);
    expect(s.history.single.url, 'http://cdn/x.ts?auth=SuperSecret99');
  });

  test('migración de formato: el historial antiguo con credenciales se reescribe', () async {
    SharedPreferences.setMockInitialValues({
      'sources': jsonEncode([
        {'name': 'X', 'kind': 1, 'server': 'http://h', 'user': 'bob', 'pass': 'pw12345'},
      ]),
      'history': jsonEncode([
        {'id': '1', 'name': 'A', 'url': 'http://h/live/bob/pw12345/1.m3u8', 'cat': 'c', 'type': 0, 'src': 'X'},
      ]),
    });
    final s = AppState()..secretStore = MemorySecretStore();
    await s.initPrefs();
    expect(s.history.single.url, 'http://h/live/bob/pw12345/1.m3u8');
    final raw = (await SharedPreferences.getInstance()).getString('history')!;
    expect(raw, isNot(contains('pw12345')));
    expect(raw, isNot(contains('bob')));
  });
}
