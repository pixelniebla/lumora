import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/app_state.dart';
import 'package:iptv_player/services/store_build.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('isPackagedPath reconoce la carpeta de apps empaquetadas (MSIX)', () {
    expect(isPackagedPath(r'C:\Program Files\WindowsApps\pixelniebla.Lumora_1.3.8.0_x64__abc\Lumora.exe'), isTrue);
    expect(isPackagedPath('c:/program files/windowsapps/x/Lumora.exe'), isTrue);
    expect(isPackagedPath(r'C:\Program Files\Lumora\Lumora.exe'), isFalse);
    expect(isPackagedPath(r'D:\Claude\iptv_player\build\windows\x64\runner\Release\Lumora.exe'), isFalse);
  });

  test('en la versión de la Store no hay autoactualización ni comprobación', () async {
    SharedPreferences.setMockInitialValues({'lastUpdateCheck': 0});
    final s = AppState();
    await s.initPrefs();
    s.storeBuild = true;
    s.updateSource = 'https://127.0.0.1:1/unreachable'; // si se intentara, fallaría o tardaría
    expect(await s.checkUpdates(), isNull);
    expect(s.checkingUpdate, isFalse);
    expect(s.updateAvailable, isNull);
    await s.maybeCheckUpdates(); // vuelve sin hacer nada
    expect((await SharedPreferences.getInstance()).getInt('lastUpdateCheck'), 0);
  });
}
