import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/app_state.dart';
import 'package:iptv_player/models.dart';
import 'package:iptv_player/screens/multiview_screen.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _mpv = r'build\windows\x64\runner\Release\libmpv-2.dll';

void main() {
  final haveMpv = Platform.isWindows && File(_mpv).existsSync();

  testWidgets('Multivista: empieza con 2 pantallas, se pueden añadir hasta 4 y quitar hasta 2', (tester) async {
    MediaKit.ensureInitialized(libmpv: File(_mpv).absolute.path);
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({'lang': 'es'});
    final s = AppState();
    await tester.runAsync(s.initPrefs);
    s.library = LoadedLibrary(const [Category('c', 'C')], [
      Channel(id: 'a', name: 'Canal A', url: 'http://h/a.ts', categoryId: 'c'),
    ]);

    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(value: s, child: const MaterialApp(home: MultiviewScreen())));
    final emptyCells = find.byIcon(Icons.add_circle_outline);
    final addTile = find.byKey(const ValueKey('add-screen'));
    expect(emptyCells, findsNWidgets(2), reason: 'dos pantallas de base');
    expect(addTile, findsOneWidget);
    expect(find.byIcon(Icons.close), findsNothing, reason: 'con 2 no se puede quitar ninguna');

    Future<void> add() async {
      await tester.tap(addTile);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape); // cierra el selector de canal sin elegir
      await tester.pump(const Duration(milliseconds: 300));
    }

    await add();
    expect(emptyCells, findsNWidgets(3));
    expect(addTile, findsOneWidget);
    await add();
    expect(emptyCells, findsNWidgets(4));
    expect(addTile, findsNothing, reason: 'máximo 4');
    expect(find.byIcon(Icons.close), findsNWidgets(4));

    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pump();
    expect(emptyCells, findsNWidgets(3));
    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pump();
    expect(emptyCells, findsNWidgets(2));
    expect(find.byIcon(Icons.close), findsNothing, reason: 'vuelve al mínimo de 2');
    expect(addTile, findsOneWidget);
  }, skip: !haveMpv, timeout: const Timeout(Duration(minutes: 2)));
}
