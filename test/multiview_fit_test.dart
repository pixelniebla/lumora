import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/app_state.dart';
import 'package:iptv_player/l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('multiviewFit: por defecto con barras, se guarda y sobrevive al reinicio; valores raros se ignoran', () async {
    SharedPreferences.setMockInitialValues({});
    final s = AppState();
    await s.initPrefs();
    expect(s.multiviewFit, 'contain');
    await s.setMultiviewFit('cover');
    final s2 = AppState();
    await s2.initPrefs();
    expect(s2.multiviewFit, 'cover');
    await s2.setMultiviewFit('fill');
    expect((AppState()..multiviewFit = 'x').multiviewFit, 'x'); // campo simple
    SharedPreferences.setMockInitialValues({'multiviewFit': 'basura'});
    final s3 = AppState();
    await s3.initPrefs();
    expect(s3.multiviewFit, 'contain');
  });

  test('multiviewLayout: por defecto lado a lado; apilada se guarda', () async {
    SharedPreferences.setMockInitialValues({});
    final s = AppState();
    await s.initPrefs();
    expect(s.multiviewLayout, 'side');
    await s.setMultiviewLayout('stack');
    final s2 = AppState();
    await s2.initPrefs();
    expect(s2.multiviewLayout, 'stack');
  });

  test('textos del ajuste de imagen en los 4 idiomas', () {
    for (final lang in supportedLanguages.keys) {
      for (final k in ['fit_mode', 'fit_contain', 'fit_cover', 'fit_fill', 'layout_side', 'layout_stack']) {
        expect(translate(lang, k), isNot(k), reason: '$lang/$k');
      }
    }
  });
}
