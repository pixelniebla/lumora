import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Tiny rotating file logger so playback problems can be diagnosed after the fact.
class Log {
  static File? _file;
  static const _maxBytes = 1024 * 1024;

  static Future<Directory> dir() async {
    final base = await getApplicationSupportDirectory();
    final d = Directory('${base.path}${Platform.pathSeparator}logs');
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  static Future<void> init() async {
    try {
      final d = await dir();
      final f = File('${d.path}${Platform.pathSeparator}lumora.log');
      if (f.existsSync() && f.lengthSync() > _maxBytes) {
        final old = File('${d.path}${Platform.pathSeparator}lumora.old.log');
        if (old.existsSync()) old.deleteSync();
        f.renameSync(old.path);
      }
      _file = f;
      i('--- Lumora started ---');
    } catch (_) {}
  }

  static void i(String msg) => _write('INFO ', msg);
  static void w(String msg) => _write('WARN ', msg);
  static void e(String msg, [Object? err, StackTrace? st]) =>
      _write('ERROR', '$msg${err != null ? ' | $err' : ''}${st != null ? '\n$st' : ''}');

  static void _write(String level, String msg) {
    try {
      _file?.writeAsStringSync('${DateTime.now().toIso8601String()} $level ${redact(msg)}\n', mode: FileMode.append);
    } catch (_) {}
  }

  static Future<String> read({int maxChars = 60000}) async {
    try {
      final t = await _file?.readAsString() ?? '';
      return t.length > maxChars ? t.substring(t.length - maxChars) : t;
    } catch (_) {
      return '';
    }
  }

  /// Strips credentials from URLs before they are logged or shown.
  static String redact(String url) => url
      .replaceAllMapped(
          RegExp(r'(password|username|pass|user|pwd|token|key)(=|%3D)[^&\s"\x27)]*', caseSensitive: false),
          (m) => '${m[1]}${m[2]}***')
      .replaceAllMapped(RegExp(r'/(live|movie|series|timeshift)/[^/\s"\x27]+/[^/\s"\x27]+/'), (m) => '/${m[1]}/***/***/')
      .replaceAllMapped(RegExp(r'://[^/\s:@]+:[^/\s@]*@'), (m) => '://***:***@');
}
