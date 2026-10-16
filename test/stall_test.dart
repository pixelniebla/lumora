import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/l10n.dart';
import 'package:iptv_player/services/stall_monitor.dart';

void main() {
  test('StallMonitor: ignora la carga inicial, sube el búfer al primer corte y sugiere bajar al segundo', () {
    var t = DateTime(2026, 10, 16, 10);
    final m = StallMonitor();
    m.onPlaying(t);
    expect(m.onBuffering(true, t.add(const Duration(seconds: 1))), StallAction.none); // aún cargando
    t = t.add(const Duration(seconds: 10));
    expect(m.onBuffering(false, t), StallAction.none);
    expect(m.onBuffering(true, t), StallAction.raiseBuffer); // primer corte
    t = t.add(const Duration(seconds: 20));
    expect(m.onBuffering(true, t), StallAction.suggestLower); // segundo corte seguido
    t = t.add(const Duration(seconds: 20));
    expect(m.onBuffering(true, t), StallAction.none); // ya se avisó
  });

  test('StallMonitor: cortes muy separados no cuentan como repetidos y reset() empieza de cero', () {
    var t = DateTime(2026, 10, 16, 10);
    final m = StallMonitor();
    m.onPlaying(t);
    t = t.add(const Duration(seconds: 10));
    expect(m.onBuffering(true, t), StallAction.raiseBuffer);
    t = t.add(const Duration(minutes: 10));
    expect(m.onBuffering(true, t), StallAction.none);
    m.reset();
    m.onPlaying(t);
    t = t.add(const Duration(seconds: 5));
    expect(m.onBuffering(true, t), StallAction.raiseBuffer);
  });

  test('textos del aviso de conexión lenta en los 4 idiomas', () {
    for (final lang in supportedLanguages.keys) {
      expect(translate(lang, 'slow_connection'), isNot('slow_connection'));
      expect(translate(lang, 'try_lower'), isNot('try_lower'));
    }
  });
}
