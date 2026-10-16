import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show compute, Uint8List;
import 'package:xml/xml_events.dart';

import '../models.dart';
import 'errors.dart';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'http_client.dart';
import 'log.dart';

/// XMLTV guide. The download is parsed on a background isolate with the streaming
/// (event) parser and keeps only the channels of the list and a time window,
/// so a 300 MB guide never lands in memory as a DOM.
class EpgService {
  Map<String, List<Programme>> _byChannel = {};

  bool get isEmpty => _byChannel.isEmpty;

  /// Loads the guide of every URL, merged. Each download is cached on disk (gzip, already
  /// filtered to [wantedIds]) and only fetched again when older than [maxAge] or when the
  /// list of wanted channels changed. A stale cache is still used if the download fails.
  /// Throws only when nothing at all could be loaded.
  Future<void> load(
    Iterable<String> urls,
    Set<String> wantedIds, {
    Directory? cacheDir,
    Duration maxAge = const Duration(hours: 6),
    DateTime? now,
  }) async {
    final dir = cacheDir ?? await _defaultDir();
    final clock = now ?? DateTime.now();
    final wantedKey = _wantedKey(wantedIds);
    final merged = <String, List<Programme>>{};
    Object? lastError;
    var ok = 0;
    for (final url in urls) {
      try {
        final data = await _loadOne(url, wantedIds, wantedKey, dir, maxAge, clock);
        data.forEach((ch, list) => (merged[ch] ??= []).addAll(list));
        ok++;
      } catch (e) {
        lastError = e;
        Log.w('EPG load failed: ${Log.redact(e.toString())}');
      }
    }
    if (ok == 0 && lastError != null) throw lastError;
    for (final l in merged.values) {
      l.sort((a, b) => a.start.compareTo(b.start));
    }
    _byChannel = merged;
  }

  static Future<Directory> _defaultDir() async {
    final base = await getApplicationSupportDirectory();
    return Directory('${base.path}${Platform.pathSeparator}epg');
  }

  static String _wantedKey(Set<String> ids) {
    final sorted = ids.toList()..sort();
    return sha1.convert(utf8.encode(sorted.join('\n'))).toString();
  }

  Future<Map<String, List<Programme>>> _loadOne(
      String url, Set<String> wanted, String wantedKey, Directory dir, Duration maxAge, DateTime now) async {
    final name = sha1.convert(utf8.encode(url)).toString().substring(0, 16);
    final file = File('${dir.path}${Platform.pathSeparator}$name.json.gz');
    EpgCacheEntry? cached;
    if (file.existsSync()) {
      try {
        cached = await compute(decodeEpgCache, await file.readAsBytes());
      } catch (_) {} // corrupt cache: just refetch
    }
    if (cached != null && cached.wantedKey == wantedKey && now.difference(cached.saved) < maxAge) {
      return cached.data;
    }
    try {
      final r = await sharedClient.get(Uri.parse(url)).timeout(const Duration(seconds: 120));
      if (r.statusCode != 200) throw LocalizedError('err_epg', {'code': '${r.statusCode}'});
      final data = await compute(parseXmltv, EpgJob(r.bodyBytes, wanted, now.millisecondsSinceEpoch));
      try {
        if (!dir.existsSync()) dir.createSync(recursive: true);
        await file.writeAsBytes(await compute(encodeEpgCache, EpgCacheEntry(now, wantedKey, data)), flush: true);
      } catch (e) {
        Log.w('EPG cache write failed: $e');
      }
      return data;
    } catch (e) {
      if (cached != null) {
        Log.w('EPG refresh failed, using cached guide: ${Log.redact(e.toString())}');
        return cached.data;
      }
      rethrow;
    }
  }
  void replaceWith(Map<String, List<Programme>> data) => _byChannel = data;

  Programme? nowPlaying(String? epgId) {
    if (epgId == null) return null;
    final now = DateTime.now();
    for (final p in _byChannel[epgId] ?? const <Programme>[]) {
      if (p.isOn(now)) return p;
    }
    return null;
  }

  List<Programme> upcoming(String? epgId, {int max = 8}) {
    if (epgId == null) return const [];
    final now = DateTime.now();
    return (_byChannel[epgId] ?? const <Programme>[]).where((p) => p.stop.isAfter(now)).take(max).toList();
  }

  /// Programmes of a channel overlapping [from, to).
  List<Programme> between(String? epgId, DateTime from, DateTime to) {
    if (epgId == null) return const [];
    return (_byChannel[epgId] ?? const <Programme>[]).where((p) => p.stop.isAfter(from) && p.start.isBefore(to)).toList();
  }

  bool hasGuide(String? epgId) => epgId != null && (_byChannel[epgId]?.isNotEmpty ?? false);
}

class EpgJob {
  final Uint8List bytes;
  final Set<String> wanted;
  final int nowMs;
  EpgJob(this.bytes, this.wanted, this.nowMs);
}

/// Top-level so it can run inside [compute].
Map<String, List<Programme>> parseXmltv(EpgJob job) {
  var bytes = job.bytes;
  if (bytes.length > 2 && bytes[0] == 0x1f && bytes[1] == 0x8b) {
    bytes = Uint8List.fromList(gzip.decode(bytes));
  }
  final text = utf8.decode(bytes, allowMalformed: true);
  final now = DateTime.fromMillisecondsSinceEpoch(job.nowMs);
  final from = now.subtract(const Duration(hours: 3));
  final to = now.add(const Duration(hours: 36));
  final out = <String, List<Programme>>{};

  String? ch;
  DateTime? start, stop;
  var keep = false;
  var tag = '';
  var title = '';
  String? desc;
  final buf = StringBuffer();

  for (final e in parseEvents(text)) {
    if (e is XmlStartElementEvent) {
      if (e.name == 'programme') {
        ch = null;
        start = stop = null;
        title = '';
        desc = null;
        for (final a in e.attributes) {
          if (a.name == 'channel') ch = a.value;
          if (a.name == 'start') start = parseXmltvTime(a.value);
          if (a.name == 'stop') stop = parseXmltvTime(a.value);
        }
        keep = ch != null &&
            start != null &&
            stop != null &&
            stop.isAfter(from) &&
            start.isBefore(to) &&
            (job.wanted.isEmpty || job.wanted.contains(ch));
      } else if (keep && (e.name == 'title' || e.name == 'desc')) {
        tag = e.name;
        buf.clear();
      }
    } else if (e is XmlTextEvent || e is XmlCDATAEvent) {
      if (keep && tag.isNotEmpty) buf.write(e is XmlTextEvent ? e.value : (e as XmlCDATAEvent).value);
    } else if (e is XmlEndElementEvent) {
      if (e.name == 'title' && keep && tag == 'title') {
        title = buf.toString();
        tag = '';
      } else if (e.name == 'desc' && keep && tag == 'desc') {
        desc = buf.toString();
        tag = '';
      } else if (e.name == 'programme' && keep) {
        out.putIfAbsent(ch!, () => []).add(Programme(ch, title, desc, start!, stop!));
        keep = false;
      }
    }
  }
  for (final l in out.values) {
    l.sort((a, b) => a.start.compareTo(b.start));
  }
  return out;
}

/// XMLTV time: 20240101120000 +0100
DateTime? parseXmltvTime(String? s) {
  if (s == null) return null;
  final m = RegExp(r'^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})\s*([+-]\d{4})?').firstMatch(s.trim());
  if (m == null) return null;
  final utc = DateTime.utc(
      int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!), int.parse(m[4]!), int.parse(m[5]!), int.parse(m[6]!));
  final off = m[7];
  if (off == null) return utc.toLocal();
  final sign = off.startsWith('-') ? -1 : 1;
  final minutes = int.parse(off.substring(1, 3)) * 60 + int.parse(off.substring(3, 5));
  return utc.subtract(Duration(minutes: sign * minutes)).toLocal();
}

/// What is stored on disk for one guide URL.
class EpgCacheEntry {
  final DateTime saved;
  final String wantedKey;
  final Map<String, List<Programme>> data;
  const EpgCacheEntry(this.saved, this.wantedKey, this.data);
}

Uint8List encodeEpgCache(EpgCacheEntry e) {
  final json = jsonEncode({
    'saved': e.saved.millisecondsSinceEpoch,
    'wanted': e.wantedKey,
    'p': {
      for (final en in e.data.entries)
        en.key: [
          for (final p in en.value) [p.start.millisecondsSinceEpoch, p.stop.millisecondsSinceEpoch, p.title, p.description]
        ],
    },
  });
  return Uint8List.fromList(gzip.encode(utf8.encode(json)));
}

EpgCacheEntry decodeEpgCache(Uint8List bytes) {
  final j = jsonDecode(utf8.decode(gzip.decode(bytes))) as Map<String, dynamic>;
  final p = j['p'] as Map<String, dynamic>;
  return EpgCacheEntry(
    DateTime.fromMillisecondsSinceEpoch(j['saved'] as int),
    j['wanted'] as String,
    {
      for (final en in p.entries)
        en.key: [
          for (final x in en.value as List)
            Programme(en.key, x[2] as String, x[3] as String?, DateTime.fromMillisecondsSinceEpoch(x[0] as int),
                DateTime.fromMillisecondsSinceEpoch(x[1] as int)),
        ],
    },
  );
}