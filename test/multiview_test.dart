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

  testWidgets('Multivista: empieza con 2 pantallas, se pueden aÃ±adir hasta 4 y quitar hasta 2', (tester) async {
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

    // disposición apilada: cada pantalla ocupa todo el ancho y la mitad del alto
    await tester.tap(find.byKey(const ValueKey('layout-toggle')));
    await tester.pumpAndSettle();
    final stacked = [for (var k = 0; k < 2; k++) tester.getRect(find.ancestor(of: find.byIcon(Icons.add_circle_outline).at(k), matching: find.byType(Stack)).first)];
    expect(stacked[0].width, closeTo(stacked[1].width, 1));
    expect(stacked[0].width, greaterThan(tester.getRect(find.byType(Scaffold).first).width * 0.9), reason: 'apiladas: ancho completo');
    expect(stacked[1].top, greaterThan(stacked[0].bottom - 1));
    expect(s.multiviewLayout, 'stack');
    await tester.tap(find.byKey(const ValueKey('layout-toggle'))); // vuelve a lado a lado
    await tester.pumpAndSettle();
    expect(s.multiviewLayout, 'side');

    // menú de ajuste de imagen: elegir «llenar» se guarda en el estado
    await tester.tap(find.byKey(const ValueKey('fit-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Llenar la pantalla'));
    await tester.pumpAndSettle();
    expect(s.multiviewFit, 'cover');

    // con 2 pantallas, cada una ocupa la mitad de la ventana a todo lo alto (sin hueco para un botÃ³n)
    final body = tester.getRect(find.byType(Scaffold).first);
    final rects = [for (var k = 0; k < find.byIcon(Icons.add_circle_outline).evaluate().length; k++) tester.getRect(find.ancestor(of: find.byIcon(Icons.add_circle_outline).at(k), matching: find.byType(Stack)).first)];
    expect(rects.length, 2);
    expect(rects[0].width, closeTo(rects[1].width, 1));
    expect(rects[0].width, greaterThan(body.width * 0.45));
    expect(rects[0].height, greaterThan(body.height * 0.8), reason: 'a todo lo alto, no solo la fila superior');

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
    final r3 = [for (var k = 0; k < find.byIcon(Icons.add_circle_outline).evaluate().length; k++) tester.getRect(find.ancestor(of: find.byIcon(Icons.add_circle_outline).at(k), matching: find.byType(Stack)).first)];
    expect(r3[2].width, greaterThan(r3[0].width * 1.8), reason: 'con 3, la tercera ocupa todo el ancho de abajo');
    expect(r3[2].top, greaterThan(r3[0].bottom - 1));
    await add();
    expect(emptyCells, findsNWidgets(4));
    expect(addTile, findsNothing, reason: 'mÃ¡ximo 4');
    expect(find.byIcon(Icons.close), findsNWidgets(4));

    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pump();
    expect(emptyCells, findsNWidgets(3));
    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pump();
    expect(emptyCells, findsNWidgets(2));
    expect(find.byIcon(Icons.close), findsNothing, reason: 'vuelve al mÃ­nimo de 2');
    expect(addTile, findsOneWidget);
  }, skip: !haveMpv, timeout: const Timeout(Duration(minutes: 2)));
}
