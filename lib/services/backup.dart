import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:pointycastle/export.dart';

import 'errors.dart';

/// Encrypted backup file: PBKDF2-HMAC-SHA256 from the user's passphrase, AES-256-GCM.
/// The file holds list passwords, so it is useless without the passphrase.
class BackupCodec {
  static const magic = 'LUMORA-BACKUP';
  static const _iterations = 150000;

  static Future<Uint8List> encrypt(Map<String, dynamic> data, String passphrase, {int iterations = _iterations}) async {
    final rnd = Random.secure();
    Uint8List rand(int n) => Uint8List.fromList(List.generate(n, (_) => rnd.nextInt(256)));
    final salt = rand(16), nonce = rand(12);
    final plain = Uint8List.fromList(utf8.encode(jsonEncode(data)));
    final sealed = await compute(_seal, _Job(passphrase, salt, nonce, iterations, plain, true));
    return Uint8List.fromList(utf8.encode(jsonEncode({
      'magic': magic,
      'v': 1,
      'iter': iterations,
      'salt': base64.encode(salt),
      'nonce': base64.encode(nonce),
      'data': base64.encode(sealed),
    })));
  }

  static Future<Map<String, dynamic>> decrypt(Uint8List file, String passphrase) async {
    final Map<String, dynamic> env;
    try {
      env = jsonDecode(utf8.decode(file)) as Map<String, dynamic>;
      if (env['magic'] != magic) throw const FormatException();
    } catch (_) {
      throw const LocalizedError('err_backup_file');
    }
    try {
      final opened = await compute(
          _seal,
          _Job(passphrase, base64.decode(env['salt'] as String), base64.decode(env['nonce'] as String),
              env['iter'] as int, base64.decode(env['data'] as String), false));
      return jsonDecode(utf8.decode(opened)) as Map<String, dynamic>;
    } on InvalidCipherTextException {
      throw const LocalizedError('err_backup_pass'); // wrong passphrase or damaged file
    } catch (_) {
      throw const LocalizedError('err_backup_file');
    }
  }
}

class _Job {
  final String passphrase;
  final Uint8List salt, nonce, data;
  final int iterations;
  final bool encrypt;
  _Job(this.passphrase, this.salt, this.nonce, this.iterations, this.data, this.encrypt);
}

Uint8List _seal(_Job j) {
  final kdf = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))..init(Pbkdf2Parameters(j.salt, j.iterations, 32));
  final key = kdf.process(Uint8List.fromList(utf8.encode(j.passphrase)));
  final gcm = GCMBlockCipher(AESEngine())..init(j.encrypt, AEADParameters(KeyParameter(key), 128, j.nonce, Uint8List(0)));
  return gcm.process(j.data);
}
