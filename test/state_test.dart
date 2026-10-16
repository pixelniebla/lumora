import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/app_state.dart';
import 'package:iptv_player/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

Channel _c(String id, {String cat = 'c1'}) => Channel(id: id, name: id, url: 'http://x/$id', categoryId: cat);

void main() {
  late AppState s;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    s = AppState();
    await s.initPrefs();
    s.library = LoadedLibrary(
      const [Category('c1', 'Noticias'), Category('c2', 'Adultos XXX'), Category('c3', 'Cine')],
      [_c('a'), _c('b'), _c('c', cat: 'c2'), _c('d', cat: 'c3')],
    );
  });

  test('PIN: se guarda con hash, verifica y bloquea categorías hasta desbloquear', () async {
    expect(s.pinEnabled, isFalse);
    await s.setPin('1234');
    expect(s.pinEnabled, isTrue);
    expect(s.verifyPin('1234'), isTrue);
    expect(s.verifyPin('0000'), isFalse);

    s.lockAgain();
    expect(await s.autoLockAdult(), 1); // solo "Adultos XXX"
    expect(s.visible(_c('c', cat: 'c2')), isFalse);
    expect(s.visible(_c('a')), isTrue);
    s.unlock();
    expect(s.visible(_c('c', cat: 'c2')), isTrue);

    // el PIN no se guarda en claro
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('pinHash'), isNot(contains('1234')));
  });

  test('categorías ocultas no se listan aunque no haya PIN', () async {
    await s.setCategoryFlags('c3', hidden: true);
    expect(s.visible(_c('d', cat: 'c3')), isFalse);
  });

  test('quitar el PIN desbloquea todo', () async {
    await s.setPin('1234');
    await s.setCategoryFlags('c2', locked: true);
    s.lockAgain();
    expect(s.isCategoryLocked('c2'), isTrue);
    await s.clearPin();
    expect(s.isCategoryLocked('c2'), isFalse);
  });

  test('favoritos: orden personalizado y reordenar', () async {
    for (final id in ['a', 'b', 'd']) {
      await s.toggleFavorite(_c(id));
    }
    expect(s.orderedFavorites().map((c) => c.id), ['a', 'b', 'd']);
    await s.reorderFavorites(2, 0); // mover 'd' al principio
    expect(s.orderedFavorites().map((c) => c.id), ['d', 'a', 'b']);
    await s.toggleFavorite(_c('a')); // quitar
    expect(s.orderedFavorites().map((c) => c.id), ['d', 'b']);
  });

  test('seguir viendo: solo posiciones sin terminar', () async {
    for (final id in ['a', 'b', 'd']) {
      await s.addToHistory(_c(id));
    }
    await s.saveResume('a', 60000, 600000, force: true); // 10 %  -> reanudable
    await s.saveResume('b', 590000, 600000, force: true); // 98 % -> terminada
    await s.saveResume('d', 3000, 600000, force: true); // 3 s  -> demasiado pronto
    expect(s.continueWatching().map((c) => c.id), ['a']);
    expect(s.resumeFor('a')!.fraction, closeTo(0.1, 0.001));
  });

  test('las preferencias sobreviven a un reinicio', () async {
    await s.setLang('fr');
    await s.setQuality('min');
    await s.setHwdec(false);
    final s2 = AppState();
    await s2.initPrefs();
    expect(s2.lang, 'fr');
    expect(s2.quality, 'min');
    expect(s2.hwdec, isFalse);
  });

  test('LoadedLibrary: ida y vuelta JSON y fusión de listas', () {
    final lib = LoadedLibrary.fromJson(s.library!.toJson());
    expect(lib.items.length, 4);
    expect(lib.categories.map((c) => c.name), contains('Cine'));
    final merged = LoadedLibrary.merge([lib, lib]);
    expect(merged.items.length, 8);
  });
}
