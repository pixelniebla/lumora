import 'dart:convert';
import 'package:flutter/foundation.dart' show compute, Uint8List;

import '../models.dart';

/// Parses extended M3U playlists (#EXTM3U / #EXTINF). Ids and category ids are
/// prefixed with [src] so several lists can be merged without collisions.
LoadedLibrary parseM3u(String text, {String src = ''}) {
  final lines = text.split(RegExp(r'\r?\n'));
  final categories = <String, Category>{};
  final items = <Channel>[];
  String? epgUrl;
  final p = src.isEmpty ? '' : '$src|';

  if (lines.isNotEmpty && lines.first.startsWith('#EXTM3U')) {
    epgUrl = _attr(lines.first, 'url-tvg') ?? _attr(lines.first, 'x-tvg-url');
  }

  Map<String, String>? pending;
  String pendingName = '';
  var index = 0;

  for (final raw in lines) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    if (line.startsWith('#EXTINF')) {
      final comma = line.lastIndexOf(',');
      pendingName = comma >= 0 ? line.substring(comma + 1).trim() : '';
      pending = {
        for (final k in ['tvg-id', 'tvg-name', 'tvg-logo', 'group-title'])
          if (_attr(line, k) != null) k: _attr(line, k)!,
      };
    } else if (line.startsWith('#')) {
      continue;
    } else if (pending != null) {
      final group = pending['group-title']?.trim();
      final catName = (group == null || group.isEmpty) ? 'Sin categoría' : group;
      final catId = '$p$catName';
      categories.putIfAbsent(catId, () => Category(catId, catName));
      final name = pendingName.isNotEmpty ? pendingName : (pending['tvg-name'] ?? 'Canal ${index + 1}');
      items.add(Channel(
        id: '${p}m3u_${index++}',
        name: name,
        url: line,
        logo: pending['tvg-logo'],
        epgId: pending['tvg-id'],
        categoryId: catId,
        type: _guessType(line),
        source: src,
      ));
      pending = null;
    }
  }
  return LoadedLibrary(categories.values.toList(), items, epgUrl: epgUrl);
}

/// Parses off the UI thread: a 50k-channel playlist takes long enough to freeze the window.
Future<LoadedLibrary> parseM3uAsync(String text, {String src = ''}) =>
    compute(_parseArgs, (text, src));

LoadedLibrary _parseArgs((String, String) a) => parseM3u(a.$1, src: a.$2);

/// Decodes and parses raw bytes in one background job.
Future<LoadedLibrary> parseM3uBytesAsync(Uint8List bytes, {String src = ''}) => compute(_parseBytes, (bytes, src));

LoadedLibrary _parseBytes((Uint8List, String) a) =>
    parseM3u(utf8.decode(a.$1, allowMalformed: true), src: a.$2);

ContentType _guessType(String url) {
  final u = url.toLowerCase();
  if (u.contains('/movie/')) return ContentType.movie;
  if (u.contains('/series/')) return ContentType.series;
  return ContentType.live;
}

String? _attr(String line, String key) {
  final m = RegExp('$key="([^"]*)"', caseSensitive: false).firstMatch(line);
  return m?.group(1);
}
