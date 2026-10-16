import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/services/errors.dart';
import 'package:iptv_player/services/update_signature.dart';
import 'package:iptv_player/services/updater.dart';
import 'package:pointycastle/export.dart';
import 'dart:typed_data';

AsymmetricKeyPair<RSAPublicKey, RSAPrivateKey> _newKeyDifferent() => _newKey(seed: 99);

AsymmetricKeyPair<RSAPublicKey, RSAPrivateKey> _newKey({int seed = 7}) {
  final gen = RSAKeyGenerator()
    ..init(ParametersWithRandom(
        RSAKeyGeneratorParameters(BigInt.from(65537), 2048, 64), FortunaRandom()..seed(KeyParameter(Uint8List.fromList(List.generate(32, (i) => i * seed + 1))))));
  final p = gen.generateKeyPair();
  return AsymmetricKeyPair(p.publicKey, p.privateKey);
}

late AsymmetricKeyPair<RSAPublicKey, RSAPrivateKey> _keys;

String _sig(String version, String url, String sha) =>
    signManifestPayload(_keys.privateKey, manifestPayload(version, url, sha));

void main() {
  setUpAll(() {
    _keys = _newKey();
    Updater.publicKey = UpdatePublicKey(_keys.publicKey.modulus!, _keys.publicKey.exponent!);
  });

  late Directory dir;
  late List<int> payload;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('lumora_upd_test');
    payload = List<int>.generate(50000, (i) => i % 251);
    File('${dir.path}${Platform.pathSeparator}Lumora-Setup-1.3.0.exe').writeAsBytesSync(payload);
  });

  tearDown(() => dir.deleteSync(recursive: true));

  void writeManifest({String? sha, String version = '1.3.0', String url = 'Lumora-Setup-1.3.0.exe', bool sign = true, String? sigOf}) {
    final h = sha ?? sha256.convert(payload).toString();
    File('${dir.path}${Platform.pathSeparator}latest.json').writeAsStringSync(jsonEncode({
      'version': version,
      'url': url,
      'sha256': h,
      'notes': 'Novedades de prueba',
      if (sign) 'sig': _sig(version, url, sigOf ?? h),
    }));
  }

  test('comparación de versiones', () {
    expect(Updater.isNewer('1.10.0', '1.9.2'), isTrue);
    expect(Updater.isNewer('1.2.0', '1.2.0+5'), isFalse);
    expect(Updater.isNewer('1.2.1', '1.2.0'), isTrue);
    expect(Updater.isNewer('1.1.9', '1.2.0'), isFalse);
    expect(Updater.isNewer('2.0', '1.9.9'), isTrue);
  });

  test('carpeta local: detecta versión nueva, copia el instalador y verifica el hash', () async {
    writeManifest();
    final info = await Updater.check(dir.path, '1.2.0');
    expect(info, isNotNull);
    expect(info!.version, '1.3.0');
    expect(info.notes, 'Novedades de prueba');
    final f = await Updater.download(info, dir.path);
    expect(f.readAsBytesSync(), payload);
  });

  test('misma versión o más antigua: no hay actualización', () async {
    writeManifest();
    expect(await Updater.check(dir.path, '1.3.0'), isNull);
    expect(await Updater.check(dir.path, '2.0.0'), isNull);
  });

  test('hash incorrecto: rechaza el instalador y borra la descarga', () async {
    writeManifest(sha: 'a' * 64);
    final info = (await Updater.check(dir.path, '1.2.0'))!;
    await expectLater(Updater.download(info, dir.path), throwsA(isA<LocalizedError>().having((e) => e.key, 'key', 'err_checksum')));
    final leftover = File('${Directory.systemTemp.path}${Platform.pathSeparator}lumora_update${Platform.pathSeparator}Lumora-Setup-1.3.0.exe');
    expect(leftover.existsSync(), isFalse);
  });

  test('fuente HTTP remota (no HTTPS) se rechaza', () async {
    await expectLater(
      Updater.check('http://ejemplo.com/updates', '1.0.0'),
      throwsA(isA<LocalizedError>().having((e) => e.key, 'key', 'err_https')),
    );
  });

  test('servidor HTTP (loopback): descarga con progreso y verificación', () async {
    final server = await HttpServer.bind('127.0.0.1', 0);
    addTearDown(() => server.close(force: true));
    server.listen((req) async {
      if (req.uri.path.endsWith('latest.json')) {
        final h = sha256.convert(payload).toString();
        req.response.write(jsonEncode({
          'version': '1.3.0',
          'url': 'setup.exe',
          'sha256': h,
          'notes': '',
          'sig': _sig('1.3.0', 'setup.exe', h),
        }));
      } else if (req.uri.path.endsWith('setup.exe')) {
        req.response.contentLength = payload.length;
        req.response.add(payload);
      } else {
        req.response.statusCode = 404;
      }
      await req.response.close();
    });
    final base = 'http://127.0.0.1:${server.port}/updates';
    final info = (await Updater.check(base, '1.0.0'))!;
    final progress = <double>[];
    final f = await Updater.download(info, base, onProgress: progress.add);
    expect(f.lengthSync(), payload.length);
    expect(progress, isNotEmpty);
    expect(progress.last, closeTo(1, 0.001));
  });

  test('manifiesto sin firma o con la firma de otro contenido se rechaza', () async {
    writeManifest(sign: false);
    await expectLater(Updater.check(dir.path, '1.2.0'),
        throwsA(isA<LocalizedError>().having((e) => e.key, 'key', 'err_signature')));
    // alguien cambia el hash del instalador pero conserva la firma original
    writeManifest(sha: 'b' * 64, sigOf: sha256.convert(payload).toString());
    await expectLater(Updater.check(dir.path, '1.2.0'),
        throwsA(isA<LocalizedError>().having((e) => e.key, 'key', 'err_signature')));
  });

  test('firma hecha con otra clave se rechaza', () async {
    final other = _newKeyDifferent();
    final h = sha256.convert(payload).toString();
    File('${dir.path}${Platform.pathSeparator}latest.json').writeAsStringSync(jsonEncode({
      'version': '1.3.0',
      'url': 'Lumora-Setup-1.3.0.exe',
      'sha256': h,
      'sig': signManifestPayload(other.privateKey, manifestPayload('1.3.0', 'Lumora-Setup-1.3.0.exe', h)),
    }));
    await expectLater(Updater.check(dir.path, '1.2.0'),
        throwsA(isA<LocalizedError>().having((e) => e.key, 'key', 'err_signature')));
  });

  test('manifiesto inexistente da un error claro', () async {
    await expectLater(Updater.check('${dir.path}${Platform.pathSeparator}nada', '1.0.0'), throwsA(isA<Exception>()));
  });
}
