import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// RSA public key used to check update manifests.
class UpdatePublicKey {
  final BigInt modulus, exponent;
  const UpdatePublicKey(this.modulus, this.exponent);

  factory UpdatePublicKey.fromBase64(String n, String e) => UpdatePublicKey(_big(base64.decode(n)), _big(base64.decode(e)));

  static BigInt _big(List<int> bytes) {
    var r = BigInt.zero;
    for (final b in bytes) {
      r = (r << 8) | BigInt.from(b);
    }
    return r;
  }
}

/// The exact bytes that are signed: the fields that decide what gets installed.
Uint8List manifestPayload(String version, String url, String sha256) =>
    Uint8List.fromList(utf8.encode('$version\n$url\n${sha256.toLowerCase()}'));

const _sha256Oid = '0609608648016503040201';

/// RSASSA-PKCS1-v1_5 with SHA-256 (what `RSACryptoServiceProvider.SignData` produces).
bool verifyManifestSignature(UpdatePublicKey key, Uint8List payload, String signatureB64) {
  try {
    final signer = RSASigner(SHA256Digest(), _sha256Oid)
      ..init(false, PublicKeyParameter<RSAPublicKey>(RSAPublicKey(key.modulus, key.exponent)));
    return signer.verifySignature(payload, RSASignature(base64.decode(signatureB64)));
  } catch (_) {
    return false;
  }
}

/// Test helper / tooling: signs with a private key.
String signManifestPayload(RSAPrivateKey key, Uint8List payload) {
  final signer = RSASigner(SHA256Digest(), _sha256Oid)..init(true, PrivateKeyParameter<RSAPrivateKey>(key));
  return base64.encode(signer.generateSignature(payload).bytes);
}
