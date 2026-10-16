import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show compute, Uint8List;
import 'package:path_provider/path_provider.dart';

import '../models.dart';
import 'log.dart';
import 'secrets.dart';

/// Disk cache of parsed lists so the app opens instantly and refreshes in the background.
class LibraryCache {
  static Future<File> _file(String name) async {
    final base = await getApplicationSupportDirectory();
    final d = Directory('${base.path}${Platform.pathSeparator}cache');
    if (!d.existsSync()) d.createSync(recursive: true);
    final key = sha1.convert(utf8.encode(name)).toString().substring(0, 16);
    return File('${d.path}${Platform.pathSeparator}$key.json.gz');
  }

  /// [spec]: how to restore the credentials removed by [save].
  static Future<({LoadedLibrary lib, DateTime saved})?> load(String name, {ScrubSpec? spec}) async {
    try {
      final f = await _file(name);
      if (!f.existsSync()) return null;
      final bytes = await f.readAsBytes();
      final lib = await compute(_decode, (bytes, spec));
      return (lib: lib, saved: f.lastModifiedSync());
    } catch (e) {
      Log.w('cache read failed for $name: $e');
      return null;
    }
  }

  /// [scrub]: store the list's credentials as placeholders instead of in clear text.
  static Future<void> save(String name, LoadedLibrary lib, {ScrubSpec? scrub}) async {
    try {
      final f = await _file(name);
      final bytes = await compute(_encode, (lib, scrub));
      await f.writeAsBytes(bytes, flush: true);
    } catch (e) {
      Log.w('cache write failed for $name: $e');
    }
  }

  static Future<void> clear() async {
    try {
      final base = await getApplicationSupportDirectory();
      final d = Directory('${base.path}${Platform.pathSeparator}cache');
      if (d.existsSync()) d.deleteSync(recursive: true);
    } catch (_) {}
  }
}

Uint8List _encode((LoadedLibrary, ScrubSpec?) a) {
  var json = jsonEncode(a.$1.toJson());
  if (a.$2 != null) json = a.$2!.scrubText(json);
  return Uint8List.fromList(gzip.encode(utf8.encode(json)));
}

LoadedLibrary _decode((Uint8List, ScrubSpec?) a) {
  var json = utf8.decode(gzip.decode(a.$1));
  if (a.$2 != null) json = a.$2!.hydrateText(json);
  return LoadedLibrary.fromJson(jsonDecode(json) as Map<String, dynamic>);
}