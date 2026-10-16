import 'dart:convert';
import 'package:flutter/foundation.dart' show compute, Uint8List;

import '../models.dart';
import 'errors.dart';
import 'http_client.dart';

/// Xtream Codes API client (player_api.php). Requests run in parallel and the
/// big JSON payloads are decoded and mapped on a background isolate.
class XtreamClient {
  final String server; // e.g. http://host:port
  final String username;
  final String password;
  final String src; // list name, used to namespace ids

  XtreamClient(String server, this.username, this.password, {this.src = ''}) : server = _normalize(server);

  static String _normalize(String s) {
    var v = s.trim();
    if (!v.startsWith('http')) v = 'http://$v';
    while (v.endsWith('/')) {
      v = v.substring(0, v.length - 1);
    }
    return v;
  }

  Uri _api([Map<String, String> extra = const {}]) => Uri.parse('$server/player_api.php').replace(
        queryParameters: {'username': username, 'password': password, ...extra},
      );

  Future<Uint8List> _raw(Map<String, String> extra, {int timeoutSec = 60}) async {
    final r = await sharedClient.get(_api(extra)).timeout(Duration(seconds: timeoutSec));
    if (r.statusCode != 200) {
      throw LocalizedError('err_status', {'code': '${r.statusCode}'});
    }
    return r.bodyBytes;
  }

  Future<Uint8List?> _optional(Map<String, String> extra) async {
    try {
      return await _raw(extra);
    } catch (_) {
      return null; // a section the provider does not offer must not break the others
    }
  }

  /// Validates credentials. Throws if invalid.
  Future<void> authenticate() async => _checkAuth(await _raw({}, timeoutSec: 30));

  static void _checkAuth(Uint8List body) {
    final data = jsonDecode(utf8.decode(body, allowMalformed: true));
    final info = data is Map ? data['user_info'] : null;
    if (info == null || info['auth'].toString() != '1') {
      throw const LocalizedError('err_bad_credentials');
    }
  }

  String get epgUrl => '$server/xmltv.php?username=$username&password=$password';

  Future<LoadedLibrary> load() async {
    // Everything in parallel: auth + (categories, streams) for live, movies and series.
    final results = await Future.wait<Uint8List?>([
      _raw({}, timeoutSec: 30),
      _optional({'action': 'get_live_categories'}),
      _optional({'action': 'get_live_streams'}),
      _optional({'action': 'get_vod_categories'}),
      _optional({'action': 'get_vod_streams'}),
      _optional({'action': 'get_series_categories'}),
      _optional({'action': 'get_series'}),
    ]);
    _checkAuth(results[0]!);
    final job = _BuildJob(server, username, password, src, results.sublist(1));
    return compute(_build, job);
  }

  /// Returns episodes of a series as playable channels, ordered by season.
  Future<List<Channel>> seriesEpisodes(String seriesId, String categoryId) async {
    final body = await _raw({'action': 'get_series_info', 'series_id': seriesId});
    final data = jsonDecode(utf8.decode(body, allowMalformed: true));
    final eps = data is Map ? data['episodes'] : null;
    final out = <Channel>[];
    final p = src.isEmpty ? '' : '$src|';
    if (eps is Map) {
      final seasons = eps.keys.toList()..sort((a, b) => int.parse('$a').compareTo(int.parse('$b')));
      for (final season in seasons) {
        for (final e in (eps[season] as List)) {
          out.add(Channel(
            id: '${p}ep_${e['id']}',
            name: 'T$season · E${e['episode_num']} · ${e['title'] ?? ''}',
            url: '$server/series/$username/$password/${e['id']}.${e['container_extension'] ?? 'mp4'}',
            categoryId: categoryId,
            type: ContentType.movie,
            source: src,
          ));
        }
      }
    }
    return out;
  }
}

class _BuildJob {
  final String server, username, password, src;
  final List<Uint8List?> bodies; // liveCats, live, vodCats, vod, seriesCats, series
  _BuildJob(this.server, this.username, this.password, this.src, this.bodies);
}

LoadedLibrary _build(_BuildJob j) {
  final p = j.src.isEmpty ? '' : '${j.src}|';
  final cats = <Category>[];
  final items = <Channel>[];

  dynamic decode(Uint8List? b) => b == null ? null : jsonDecode(utf8.decode(b, allowMalformed: true));

  void section(ContentType t, dynamic catData, dynamic list, String ext) {
    final names = <String, String>{};
    if (catData is List) {
      for (final c in catData) {
        final id = '$p${t.name}_${c['category_id']}';
        names[c['category_id'].toString()] = id;
        cats.add(Category(id, c['category_name'].toString()));
      }
    }
    if (list is! List) return;
    for (final s in list) {
      final sid = (s['stream_id'] ?? s['series_id']).toString();
      final String url;
      switch (t) {
        case ContentType.live:
          url = '${j.server}/live/${j.username}/${j.password}/$sid.m3u8';
        case ContentType.movie:
          url = '${j.server}/movie/${j.username}/${j.password}/$sid.${s['container_extension'] ?? ext}';
        case ContentType.series:
          url = 'series:$sid'; // episodes resolved lazily
      }
      items.add(Channel(
        id: '$p${t.name}_$sid',
        name: (s['name'] ?? '').toString(),
        url: url,
        logo: (s['stream_icon'] ?? s['cover'])?.toString(),
        epgId: s['epg_channel_id']?.toString(),
        categoryId: names[s['category_id'].toString()] ?? '$p${t.name}_${s['category_id']}',
        type: t,
        source: j.src,
      ));
    }
  }

  section(ContentType.live, decode(j.bodies[0]), decode(j.bodies[1]), 'm3u8');
  section(ContentType.movie, decode(j.bodies[2]), decode(j.bodies[3]), 'mp4');
  section(ContentType.series, decode(j.bodies[4]), decode(j.bodies[5]), 'mp4');
  if (items.isEmpty) throw const LocalizedError('err_no_channels');
  return LoadedLibrary(cats, items,
      epgUrl: '${j.server}/xmltv.php?username=${j.username}&password=${j.password}');
}
