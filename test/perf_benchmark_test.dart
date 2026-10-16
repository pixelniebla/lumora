// CPU-side UI benchmarks (build + layout, no GPU): how long frames take while scrolling and
// searching big lists. Needs libmpv from `flutter build windows` for the player service; skipped otherwise.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/app_state.dart';
import 'package:iptv_player/models.dart';
import 'package:iptv_player/screens/browse_screen.dart';
import 'package:iptv_player/screens/guide_screen.dart';
import 'package:iptv_player/services/perf.dart';
import 'package:iptv_player/services/player_service.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _mpv = r'build\windows\x64\runner\Release\libmpv-2.dll';

Future<AppState> _state(int channels, {int withGuide = 600}) async {
  SharedPreferences.setMockInitialValues({'lang': 'es'});
  final s = AppState();
  await s.initPrefs();
  final cats = [for (var i = 0; i < 40; i++) Category('c$i', 'Categoría $i')];
  s.library = LoadedLibrary(cats, [
    for (var i = 0; i < channels; i++)
      Channel(id: 'ch$i', name: 'Canal número $i HD', url: 'http://h/live/u/p/$i.ts', categoryId: 'c${i % 40}', epgId: i < withGuide ? 'e$i' : null),
  ]);
  final now = DateTime.now();
  s.epg.replaceWith({
    for (var i = 0; i < withGuide; i++)
      'e$i': [
        for (var k = -2; k < 40; k++)
          Programme('e$i', 'Programa $k del canal $i', 'desc', now.add(Duration(hours: k)), now.add(Duration(hours: k + 1))),
      ],
  });
  return s;
}

Widget _app(AppState s, PlayerService ps, Widget home) => MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: s),
        Provider<PlayerService>.value(value: ps),
      ],
      child: MaterialApp(home: home),
    );

void main() {
  final haveMpv = Platform.isWindows && File(_mpv).existsSync();

  testWidgets('BENCH lista de 50.000 canales: construir, scroll y buscar', (tester) async {
    MediaKit.ensureInitialized(libmpv: File(_mpv).absolute.path);
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final s = (await tester.runAsync(() => _state(50000)))!;
    final ps = (await tester.runAsync(() async => PlayerService()))!;

    final sw = Stopwatch()..start();
    await tester.pumpWidget(_app(s, ps, const BrowseScreen(mode: BrowseMode.live)));
    final firstBuild = sw.elapsedMilliseconds;

    // scroll: 60 drag steps, time each pump
    final list = find.byType(ListView).at(1);
    final frameMs = <int>[];
    for (var i = 0; i < 60; i++) {
      sw
        ..reset()
        ..start();
      await tester.drag(list, const Offset(0, -300));
      await tester.pump();
      frameMs.add(sw.elapsedMicroseconds ~/ 1000);
    }

    // search: type, wait the 220 ms debounce, time the rebuild that filters 50k channels
    await tester.enterText(find.byType(TextField), 'número 4999');
    sw
      ..reset()
      ..start();
    await tester.pump(const Duration(milliseconds: 300));
    final searchMs = sw.elapsedMilliseconds;

    // category switch
    sw
      ..reset()
      ..start();
    await tester.tap(find.text('Categoría 7').first);
    await tester.pump();
    final catMs = sw.elapsedMilliseconds;

    // ignore: avoid_print
    print('BENCH browse 50k: primera construcción=${firstBuild}ms  scroll(60 pasos) avg=${frameMs.reduce((a, b) => a + b) ~/ frameMs.length}ms '
        'p95=${percentile(frameMs, 95)}ms max=${percentile(frameMs, 100)}ms  búsqueda=${searchMs}ms  categoría=${catMs}ms');
    expect(percentile(frameMs, 95), lessThan(120), reason: 'el scroll no debe tardar más de ~120 ms por paso en CPU');
    await tester.pumpWidget(const SizedBox()); // (the native player is left to process exit)
  }, skip: !haveMpv, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets('BENCH guía: 600 canales con EPG, desplazar el tiempo', (tester) async {
    MediaKit.ensureInitialized(libmpv: File(_mpv).absolute.path);
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final s = (await tester.runAsync(() => _state(2000, withGuide: 600)))!;
    final ps = (await tester.runAsync(() async => PlayerService()))!;
    final sw = Stopwatch()..start();
    await tester.pumpWidget(_app(s, ps, const GuideScreen()));
    final firstBuild = sw.elapsedMilliseconds;
    final frameMs = <int>[];
    final list = find.byType(ListView).first;
    for (var i = 0; i < 40; i++) {
      sw
        ..reset()
        ..start();
      await tester.drag(list, const Offset(0, -200));
      await tester.pump();
      frameMs.add(sw.elapsedMicroseconds ~/ 1000);
    }
    final next = find.byIcon(Icons.chevron_right);
    final shift = <int>[];
    for (var i = 0; i < 10; i++) {
      sw
        ..reset()
        ..start();
      await tester.tap(next);
      await tester.pump();
      shift.add(sw.elapsedMilliseconds);
    }
    // ignore: avoid_print
    print('BENCH guía 600 canales: primera construcción=${firstBuild}ms  scroll avg=${frameMs.reduce((a, b) => a + b) ~/ frameMs.length}ms '
        'p95=${percentile(frameMs, 95)}ms  cambio de hora avg=${shift.reduce((a, b) => a + b) ~/ shift.length}ms max=${percentile(shift, 100)}ms');
    await tester.pumpWidget(const SizedBox()); // (the native player is left to process exit)
  }, skip: !haveMpv, timeout: const Timeout(Duration(minutes: 3)));
}
