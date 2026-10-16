import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'log.dart';

/// Where list passwords live. In production this is the Windows Credential Manager.
abstract class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

// CREDENTIALW (wincred.h), 64-bit layout.
final class _Credential extends Struct {
  @Uint32()
  external int flags;
  @Uint32()
  external int type;
  external Pointer<Utf16> targetName;
  external Pointer<Utf16> comment;
  @Uint32()
  external int lastWrittenLow;
  @Uint32()
  external int lastWrittenHigh;
  @Uint32()
  external int credentialBlobSize;
  external Pointer<Uint8> credentialBlob;
  @Uint32()
  external int persist;
  @Uint32()
  external int attributeCount;
  external Pointer<Void> attributes;
  external Pointer<Utf16> targetAlias;
  external Pointer<Utf16> userName;
}

const _credTypeGeneric = 1;
const _credPersistLocalMachine = 2;

typedef _CredWriteC = Int32 Function(Pointer<_Credential>, Uint32);
typedef _CredWriteD = int Function(Pointer<_Credential>, int);
typedef _CredReadC = Int32 Function(Pointer<Utf16>, Uint32, Uint32, Pointer<Pointer<_Credential>>);
typedef _CredReadD = int Function(Pointer<Utf16>, int, int, Pointer<Pointer<_Credential>>);
typedef _CredDeleteC = Int32 Function(Pointer<Utf16>, Uint32, Uint32);
typedef _CredDeleteD = int Function(Pointer<Utf16>, int, int);
typedef _CredFreeC = Void Function(Pointer<Void>);
typedef _CredFreeD = void Function(Pointer<Void>);

/// Windows Credential Manager through advapi32 (generic credentials, per-user, encrypted by
/// the OS). Entries show up in Control Panel > Credential Manager as "Lumora/(key)".
class WindowsSecretStore implements SecretStore {
  static const _prefix = 'Lumora/';
  static const _maxBlob = 2560; // CRED_MAX_CREDENTIAL_BLOB_SIZE

  late final DynamicLibrary _lib = DynamicLibrary.open('advapi32.dll');
  late final _CredWriteD _write = _lib.lookupFunction<_CredWriteC, _CredWriteD>('CredWriteW');
  late final _CredReadD _read = _lib.lookupFunction<_CredReadC, _CredReadD>('CredReadW');
  late final _CredDeleteD _delete = _lib.lookupFunction<_CredDeleteC, _CredDeleteD>('CredDeleteW');
  late final _CredFreeD _free = _lib.lookupFunction<_CredFreeC, _CredFreeD>('CredFree');

  void _check() {
    if (!Platform.isWindows) throw UnsupportedError('Credential Manager needs Windows');
  }

  @override
  Future<String?> read(String key) async {
    _check();
    final target = '$_prefix$key'.toNativeUtf16();
    final out = calloc<Pointer<_Credential>>();
    try {
      if (_read(target, _credTypeGeneric, 0, out) == 0) return null; // not found
      final cred = out.value;
      try {
        final bytes = Uint8List.fromList(cred.ref.credentialBlob.asTypedList(cred.ref.credentialBlobSize));
        return utf8.decode(bytes);
      } finally {
        _free(cred.cast());
      }
    } finally {
      calloc.free(target);
      calloc.free(out);
    }
  }

  @override
  Future<void> write(String key, String value) async {
    _check();
    final data = utf8.encode(value);
    if (data.length > _maxBlob) throw StateError('secret too large for Credential Manager');
    final target = '$_prefix$key'.toNativeUtf16();
    final user = 'Lumora'.toNativeUtf16();
    final blob = calloc<Uint8>(data.isEmpty ? 1 : data.length);
    final cred = calloc<_Credential>();
    try {
      blob.asTypedList(data.length).setAll(0, data);
      cred.ref
        ..type = _credTypeGeneric
        ..targetName = target
        ..credentialBlobSize = data.length
        ..credentialBlob = blob
        ..persist = _credPersistLocalMachine
        ..userName = user;
      if (_write(cred, 0) == 0) throw StateError('CredWriteW failed');
    } finally {
      calloc.free(cred);
      calloc.free(blob);
      calloc.free(user);
      calloc.free(target);
    }
  }

  @override
  Future<void> delete(String key) async {
    _check();
    final target = '$_prefix$key'.toNativeUtf16();
    try {
      _delete(target, _credTypeGeneric, 0); // 0 = nothing to delete; fine
    } finally {
      calloc.free(target);
    }
  }
}
/// In-memory store, used by tests.
class MemorySecretStore implements SecretStore {
  final Map<String, String> data = {};
  @override
  Future<String?> read(String key) async => data[key];
  @override
  Future<void> write(String key, String value) async => data[key] = value;
  @override
  Future<void> delete(String key) async => data.remove(key);
}

/// Replaces the credentials embedded in Xtream stream URLs with placeholders before they
/// are written to disk, and puts them back (from the secure store) after loading.
class UrlScrubber {
  static const userToken = '{u}';
  static const passToken = '{p}';

  static final _pathRe = RegExp(r'/(live|movie|series|timeshift)/(?:[^/"\\\s]|\\.)+/(?:[^/"\\\s]|\\.)+/');
  static final _queryRe = RegExp(r'username=(?:[^&"\\\s]|\\.)*&password=(?:[^&"\\\s]|\\.)*');

  /// Works on a plain URL or on a whole JSON document (neither / nor & are JSON-escaped).
  static String scrub(String text) => text
      .replaceAllMapped(_pathRe, (m) => '/${m[1]}/$userToken/$passToken/')
      .replaceAll(_queryRe, 'username=$userToken&password=$passToken');

  /// Same for one plain (not JSON-encoded) URL, where any character but / is allowed in the credentials.
  static String scrubUrl(String url) => url
      .replaceAllMapped(RegExp(r'/(live|movie|series|timeshift)/[^/\s]+/[^/\s]+/'), (m) => '/${m[1]}/$userToken/$passToken/')
      .replaceAll(RegExp(r'username=[^&\s]*&password=[^&\s]*'), 'username=$userToken&password=$passToken');

  static String hydrate(String text, String user, String pass) =>
      text.replaceAll(userToken, user).replaceAll(passToken, pass);

  /// Same, for text embedded in a JSON document (values must be JSON-escaped).
  static String hydrateJson(String json, String user, String pass) =>
      hydrate(json, _jsonEscape(user), _jsonEscape(pass));

  static String _jsonEscape(String v) => jsonEscapeString(v);
}

/// Escapes [v] the way it appears inside a JSON string literal (without the quotes).
String jsonEscapeString(String v) {
  final b = StringBuffer();
  for (final c in v.runes) {
    switch (c) {
      case 0x22:
        b.write(r'\"');
      case 0x5c:
        b.write(r'\\');
      default:
        if (c < 0x20) {
          b.write('\\u${c.toRadixString(16).padLeft(4, '0')}');
        } else {
          b.writeCharCode(c);
        }
    }
  }
  return b.toString();
}

/// Query parameters that carry credentials in M3U URLs.
const _secretParams = {'token', 'key', 'password', 'pass', 'pwd', 'username', 'user', 'auth', 'apikey', 'api_key', 'access_token'};

/// Everything that must not reach the disk for one list, and how to put it back:
/// Xtream user/password embedded in stream URLs, and token-like values copied from an M3U URL.
class ScrubSpec {
  final String? user, pass; // Xtream
  final Map<String, String> secrets; // placeholder -> value (M3U)
  const ScrubSpec({this.user, this.pass, this.secrets = const {}});

  bool get isEmpty => user == null && secrets.isEmpty;

  /// Placeholders for the credential-looking query values of [m3uUrl] (values of 6+ chars).
  static Map<String, String> m3uSecrets(String m3uUrl) {
    final q = m3uUrl.indexOf('?');
    if (q < 0) return const {};
    final out = <String, String>{};
    for (final kv in m3uUrl.substring(q + 1).split('&')) {
      final eq = kv.indexOf('=');
      if (eq <= 0) continue;
      final k = kv.substring(0, eq).toLowerCase(), v = kv.substring(eq + 1);
      if (_secretParams.contains(k) && v.length >= 6 && !out.containsValue(v)) out['{s${out.length}}'] = v;
    }
    return out;
  }

  /// A whole JSON document.
  String scrubText(String json) {
    var t = user != null ? UrlScrubber.scrub(json) : json;
    secrets.forEach((ph, v) => t = t.replaceAll(jsonEscapeString(v), ph));
    return t;
  }

  String hydrateText(String json) {
    var t = user != null ? UrlScrubber.hydrateJson(json, user!, pass ?? '') : json;
    secrets.forEach((ph, v) => t = t.replaceAll(ph, jsonEscapeString(v)));
    return t;
  }

  /// One plain URL.
  String scrubUrl(String url) {
    var t = user != null ? UrlScrubber.scrubUrl(url) : url;
    secrets.forEach((ph, v) => t = t.replaceAll(v, ph));
    return t;
  }

  String hydrateUrl(String url) {
    if (!url.contains('{')) return url;
    var t = user != null ? UrlScrubber.hydrate(url, user!, pass ?? '') : url;
    secrets.forEach((ph, v) => t = t.replaceAll(ph, v));
    return t;
  }
}

/// Splits values too big for one Credential Manager entry (2560 bytes) over several entries.
class ChunkedSecretStore implements SecretStore {
  static const _marker = '\u0001chunks:';
  static const _chunk = 1800;
  final SecretStore inner;
  ChunkedSecretStore(this.inner);

  @override
  Future<String?> read(String key) async {
    final v = await inner.read(key);
    if (v == null || !v.startsWith(_marker)) return v;
    final n = int.tryParse(v.substring(_marker.length));
    if (n == null) return null;
    final b = StringBuffer();
    for (var i = 0; i < n; i++) {
      final part = await inner.read('$key#$i');
      if (part == null) return null;
      b.write(part);
    }
    return utf8.decode(base64.decode(b.toString()));
  }

  @override
  Future<void> write(String key, String value) async {
    await _dropChunks(key);
    if (utf8.encode(value).length <= _chunk && !value.startsWith(_marker)) return inner.write(key, value);
    final enc = base64.encode(utf8.encode(value));
    var n = 0;
    for (var i = 0; i < enc.length; i += _chunk) {
      await inner.write('$key#$n', enc.substring(i, i + _chunk > enc.length ? enc.length : i + _chunk));
      n++;
    }
    await inner.write(key, '$_marker$n');
  }

  Future<void> _dropChunks(String key) async {
    final v = await inner.read(key);
    if (v != null && v.startsWith(_marker)) {
      final n = int.tryParse(v.substring(_marker.length)) ?? 0;
      for (var i = 0; i < n; i++) {
        await inner.delete('$key#$i');
      }
    }
  }

  @override
  Future<void> delete(String key) async {
    await _dropChunks(key);
    await inner.delete(key);
  }
}
String secretKey(String sourceName, String field) => 'lumora.$field.$sourceName';

Future<bool> trySecretWrite(SecretStore s, String key, String value) async {
  try {
    await s.write(key, value);
    return await s.read(key) == value;
  } catch (e) {
    Log.w('secure store unavailable: ${e.runtimeType}');
    return false;
  }
}
