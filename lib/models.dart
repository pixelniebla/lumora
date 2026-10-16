enum ContentType { live, movie, series }

class Category {
  final String id;
  final String name;
  const Category(this.id, this.name);

  Map<String, dynamic> toJson() => {'id': id, 'name': name};
  factory Category.fromJson(Map<String, dynamic> j) => Category(j['id'] as String, j['name'] as String);
}

class Channel {
  final String id;
  final String name;
  final String url;
  final String? logo;
  final String categoryId;
  final String? epgId;
  final ContentType type;
  final String source; // name of the list it belongs to

  /// Lower-cased name, computed once so searching does not allocate per keystroke.
  late final String lower = name.toLowerCase();

  Channel({
    required this.id,
    required this.name,
    required this.url,
    required this.categoryId,
    this.logo,
    this.epgId,
    this.type = ContentType.live,
    this.source = '',
  });

  Channel copyWith({String? id, String? categoryId, String? source, String? url}) => Channel(
        id: id ?? this.id,
        name: name,
        url: url ?? this.url,
        logo: logo,
        categoryId: categoryId ?? this.categoryId,
        epgId: epgId,
        type: type,
        source: source ?? this.source,
      );

  /// [scrub] rewrites [url] without its credentials (for disk).
  Map<String, dynamic> toJson({String Function(String url)? scrub}) => {
        'id': id,
        'name': name,
        'url': scrub != null ? scrub(url) : url,
        'logo': logo,
        'cat': categoryId,
        'epg': epgId,
        'type': type.index,
        'src': source,
      };

  factory Channel.fromJson(Map<String, dynamic> j) => Channel(
        id: j['id'] as String,
        name: j['name'] as String,
        url: j['url'] as String,
        logo: j['logo'] as String?,
        categoryId: j['cat'] as String? ?? '',
        epgId: j['epg'] as String?,
        type: ContentType.values[j['type'] as int? ?? 0],
        source: j['src'] as String? ?? '',
      );
}

class Programme {
  final String channelId;
  final String title;
  final String? description;
  final DateTime start;
  final DateTime stop;
  const Programme(this.channelId, this.title, this.description, this.start, this.stop);

  bool isOn(DateTime t) => !t.isBefore(start) && t.isBefore(stop);
}

enum SourceKind { m3u, xtream }

/// A saved provider: either an M3U URL/file or an Xtream Codes account.
class Source {
  final String name;
  final SourceKind kind;
  final String? m3uUrl; // URL or local file path
  final String? server;
  final String? username;
  final String? password;
  final String? epgUrl;

  const Source({
    required this.name,
    required this.kind,
    this.m3uUrl,
    this.server,
    this.username,
    this.password,
    this.epgUrl,
  });

  /// [secrets] false leaves the password and remote M3U URL out (they live in the secure store).
  Map<String, dynamic> toJson({bool secrets = true}) => {
        'name': name,
        'kind': kind.index,
        'm3u': secrets || !hasRemoteM3u ? m3uUrl : null,
        'server': server,
        'user': username,
        'pass': secrets ? password : null,
        'epg': epgUrl,
      };

  bool get hasRemoteM3u => m3uUrl != null && m3uUrl!.startsWith('http');

  Source withSecrets({String? password, String? m3uUrl}) => Source(
        name: name,
        kind: kind,
        m3uUrl: m3uUrl ?? this.m3uUrl,
        server: server,
        username: username,
        password: password ?? this.password,
        epgUrl: epgUrl,
      );

  factory Source.fromJson(Map<String, dynamic> j) => Source(
        name: j['name'] as String,
        kind: SourceKind.values[j['kind'] as int],
        m3uUrl: j['m3u'] as String?,
        server: j['server'] as String?,
        username: j['user'] as String?,
        password: j['pass'] as String?,
        epgUrl: j['epg'] as String?,
      );
}

class LoadedLibrary {
  final List<Category> categories;
  final List<Channel> items;
  final String? epgUrl;
  const LoadedLibrary(this.categories, this.items, {this.epgUrl});

  Map<String, dynamic> toJson() => {
        'cats': categories.map((c) => c.toJson()).toList(),
        'items': items.map((c) => c.toJson()).toList(),
        'epg': epgUrl,
      };

  factory LoadedLibrary.fromJson(Map<String, dynamic> j) => LoadedLibrary(
        (j['cats'] as List).map((e) => Category.fromJson(e as Map<String, dynamic>)).toList(),
        (j['items'] as List).map((e) => Channel.fromJson(e as Map<String, dynamic>)).toList(),
        epgUrl: j['epg'] as String?,
      );

  static LoadedLibrary merge(List<LoadedLibrary> libs) => LoadedLibrary(
        [for (final l in libs) ...l.categories],
        [for (final l in libs) ...l.items],
        epgUrl: libs.map((l) => l.epgUrl).whereType<String>().firstOrNull,
      );
}

/// Playback position for continue-watching.
class Resume {
  final int posMs;
  final int durMs;
  final int ts; // epoch ms of last update
  const Resume(this.posMs, this.durMs, this.ts);

  double get fraction => durMs <= 0 ? 0 : posMs / durMs;
  bool get resumable => posMs > 10000 && fraction < 0.95;

  Map<String, dynamic> toJson() => {'p': posMs, 'd': durMs, 't': ts};
  factory Resume.fromJson(Map<String, dynamic> j) => Resume(j['p'] as int, j['d'] as int, j['t'] as int);
}
