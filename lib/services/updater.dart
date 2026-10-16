import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'errors.dart';
import 'update_key.dart';
import 'update_signature.dart';
import 'log.dart';

class UpdateInfo {
  final String version;
  final String url; // absolute URL / path, or relative to the update source
  final String sha256;
  final String notes;
  final String? sig; // base64 RSA signature over version/url/sha256
  const UpdateInfo(this.version, this.url, this.sha256, this.notes, [this.sig]);

  factory UpdateInfo.fromJson(Map<String, dynamic> j) => UpdateInfo(
        j['version'] as String,
        j['url'] as String,
        (j['sha256'] as String).toLowerCase(),
        (j['notes'] as String?) ?? '',
        j['sig'] as String?,
      );
}

/// Self-update from a folder or HTTPS location holding `latest.json` plus the installer.
///
/// latest.json: { "version": "1.2.0", "url": "Lumora-Setup-1.2.0.exe", "sha256": "...", "notes": "..." }
/// The installer is only run after its SHA-256 matches the manifest.
class Updater {
  /// Key that manifests must be signed with. Tests replace it.
  static UpdatePublicKey? publicKey = UpdatePublicKey.fromBase64(updateKeyModulus, updateKeyExponent);

  /// With a key set, an unsigned or wrongly signed manifest is rejected: a tampered folder or
  /// server can no longer make the app run an arbitrary installer.
  static bool verified(UpdateInfo info) {
    final key = publicKey;
    if (key == null) return true;
    final sig = info.sig;
    return sig != null && verifyManifestSignature(key, manifestPayload(info.version, info.url, info.sha256), sig);
  }

  /// True when [a] is a newer version than [b] ("1.10.0" > "1.9.2"; build suffix "+n" ignored).
  static bool isNewer(String a, String b) => compare(a, b) > 0;

  static int compare(String a, String b) {
    List<int> parts(String v) => v.split('+').first.split('.').map((e) => int.tryParse(e.trim()) ?? 0).toList();
    final x = parts(a), y = parts(b);
    for (var i = 0; i < 3; i++) {
      final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
      if (d != 0) return d;
    }
    return 0;
  }

  static bool _isRemote(String s) => s.startsWith('http://') || s.startsWith('https://');

  /// Remote sources must be HTTPS (an installer is executable code), except loopback for tests.
  static void _requireSafe(Uri u) {
    final loopback = u.host == '127.0.0.1' || u.host == 'localhost';
    if (u.scheme != 'https' && !loopback) {
      throw const LocalizedError('err_https');
    }
  }

  static String _manifestLocation(String source) {
    final s = source.trim();
    if (s.toLowerCase().endsWith('.json')) return s;
    return _isRemote(s) ? '${s.endsWith('/') ? s : '$s/'}latest.json' : p.join(s, 'latest.json');
  }

  static Future<UpdateInfo> fetchManifest(String source) async {
    final loc = _manifestLocation(source);
    final String text;
    if (_isRemote(loc)) {
      final u = Uri.parse(loc);
      _requireSafe(u);
      final r = await http.get(u).timeout(const Duration(seconds: 20));
      if (r.statusCode != 200) throw LocalizedError('err_status', {'code': '${r.statusCode}'});
      text = utf8.decode(r.bodyBytes);
    } else {
      final f = File(loc);
      if (!f.existsSync()) throw LocalizedError('err_not_found', {'path': Log.redact(loc)});
      text = await f.readAsString();
    }
    final info = UpdateInfo.fromJson(jsonDecode(text) as Map<String, dynamic>);
    if (!verified(info)) {
      Log.e('update manifest signature invalid');
      throw const LocalizedError('err_signature');
    }
    return info;
  }

  /// Returns the update when a newer version than [current] is published, else null.
  static Future<UpdateInfo?> check(String source, String current) async {
    final info = await fetchManifest(source);
    return isNewer(info.version, current) ? info : null;
  }

  /// Downloads (or copies) the installer to a temp folder and verifies its checksum.
  static Future<File> download(UpdateInfo info, String source, {void Function(double)? onProgress}) async {
    final dir = Directory(p.join(Directory.systemTemp.path, 'lumora_update'));
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    dir.createSync(recursive: true);

    final loc = _manifestLocation(source);
    final out = File(p.join(dir.path, 'Lumora-Setup-${info.version}.exe'));

    if (_isRemote(info.url) || _isRemote(loc)) {
      final u = _isRemote(info.url) ? Uri.parse(info.url) : Uri.parse(loc).resolve(info.url);
      _requireSafe(u);
      final req = http.Request('GET', u);
      final res = await http.Client().send(req).timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) throw LocalizedError('err_status', {'code': '${res.statusCode}'});
      final total = res.contentLength ?? 0;
      var got = 0;
      final sink = out.openWrite();
      await for (final chunk in res.stream) {
        sink.add(chunk);
        got += chunk.length;
        if (total > 0) onProgress?.call(got / total);
      }
      await sink.close();
    } else {
      final src = File(p.isAbsolute(info.url) ? info.url : p.join(p.dirname(loc), info.url));
      if (!src.existsSync()) throw LocalizedError('err_not_found', {'path': src.path});
      await src.copy(out.path);
      onProgress?.call(1);
    }

    final digest = (await sha256.bind(out.openRead()).first).toString();
    if (digest != info.sha256) {
      out.deleteSync();
      Log.e('update checksum mismatch: expected ${info.sha256} got $digest');
      throw const LocalizedError('err_checksum');
    }
    return out;
  }

  /// Starts the installer detached and quits so it can replace the running files.
  static Future<void> installAndExit(File installer) async {
    Log.i('launching updater ${installer.path}');
    await Process.start(
      installer.path,
      ['/SILENT', '/CLOSEAPPLICATIONS', '/NORESTART', '/LAUNCH=1'],
      mode: ProcessStartMode.detached,
    );
    await Future<void>.delayed(const Duration(milliseconds: 800));
    exit(0);
  }
}
