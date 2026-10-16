import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show ChangeNotifier, PlatformDispatcher, Uint8List, visibleForTesting;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n.dart' show errorText, supportedLanguages;
import 'models.dart';
import 'services/channel_variants.dart';
import 'services/errors.dart';
import 'services/epg_service.dart';
import 'services/http_client.dart';
import 'services/library_cache.dart';
import 'services/log.dart';
import 'services/secrets.dart';
import 'services/m3u_parser.dart';
import 'services/scheduler.dart';
import 'services/stream_recorder.dart';
import 'services/updater.dart';
import 'services/xtream_client.dart';

const kAllSources = '*';
const _cacheFreshness = Duration(hours: 6);
final _adultRe = RegExp(r'adult|xxx|18\+|porn|erotic|sex|hentai|\+18', caseSensitive: false);

class AppState extends ChangeNotifier {
  late SharedPreferences _prefs;
  SecretStore secretStore = ChunkedSecretStore(WindowsSecretStore()); // replaced in tests

  List<Source> sources = [];
  Source? active; // null while merged or on the sources screen
  bool merged = false;
  LoadedLibrary? library;
  final Map<String, XtreamClient> clients = {};
  final EpgService epg = EpgService();

  // Favorites (ordered), history and continue-watching
  final Set<String> favorites = {};
  List<String> favOrder = [];
  List<Channel> history = [];
  final Map<String, Resume> resume = {};
  DateTime _lastResumeWrite = DateTime.fromMillisecondsSinceEpoch(0);

  bool loading = false; // blocking load (no cache available)
  bool refreshing = false; // silent background refresh
  String? error;

  // Settings
  String lang = 'es';
  String quality = 'auto'; // auto | max | min
  bool hwdec = true;
  bool hideBroken = false;
  final Set<String> broken = {};

  // Updates
  /// Release builds for other people are made with --dart-define=LUMORA_UPDATE_URL=(https folder)
  /// (see installer\build_release.ps1); a developer build looks in the local output folder.
  String updateSource = const String.fromEnvironment('LUMORA_UPDATE_URL', defaultValue: r'D:\Claude\iptv_player\installer\output');
  bool autoUpdate = true;
  UpdateInfo? updateAvailable;
  String appVersion = '';
  bool checkingUpdate = false;

  Future<void> setUpdateSource(String v) async {
    updateSource = v.trim();
    updateAvailable = null;
    await _prefs.setString('updateSource', updateSource);
    notifyListeners();
  }

  Future<void> setAutoUpdate(bool v) async {
    autoUpdate = v;
    await _prefs.setBool('autoUpdate', v);
    notifyListeners();
  }

  /// Checks the update source. Returns an error message, or null when the check worked
  /// (then [updateAvailable] tells whether a newer version exists).
  Future<String?> checkUpdates() async {
    checkingUpdate = true;
    notifyListeners();
    try {
      if (appVersion.isEmpty) appVersion = (await PackageInfo.fromPlatform()).version;
      updateAvailable = updateSource.isEmpty ? null : await Updater.check(updateSource, appVersion);
      await _prefs.setInt('lastUpdateCheck', DateTime.now().millisecondsSinceEpoch);
      return null;
    } catch (e) {
      Log.w('update check failed: $e');
      return errorText(lang, e);
    } finally {
      checkingUpdate = false;
      notifyListeners();
    }
  }

  /// Quiet startup check, at most once every 12 hours.
  Future<void> maybeCheckUpdates() async {
    if (!autoUpdate || updateSource.isEmpty) return;
    final last = _prefs.getInt('lastUpdateCheck') ?? 0;
    if (DateTime.now().millisecondsSinceEpoch - last < const Duration(hours: 12).inMilliseconds) return;
    await checkUpdates();
  }

  // Parental control
  String? _pinHash;
  String? _pinSalt;
  final Set<String> lockedCats = {};
  final Set<String> hiddenCats = {};
  bool unlocked = false;

  bool get pinEnabled => _pinHash != null;
  String get activeName => merged ? '★' : (active?.name ?? '');

  // ---------------------------------------------------------------- init

  /// Fast: only reads preferences. The UI can start right after this.
  Future<void> initPrefs() async {
    _prefs = await SharedPreferences.getInstance();
    try {
      appVersion = (await PackageInfo.fromPlatform()).version;
    } catch (_) {} // unavailable in unit tests
    final sys = PlatformDispatcher.instance.locale.languageCode;
    lang = _prefs.getString('lang') ?? (supportedLanguages.containsKey(sys) ? sys : 'es');
    quality = _prefs.getString('quality') ?? 'auto';
    hwdec = _prefs.getBool('hwdec') ?? true;
    hideBroken = _prefs.getBool('hideBroken') ?? false;
    broken.addAll(_prefs.getStringList('broken') ?? const []);

    sources = _decodeList('sources', Source.fromJson);
    await _restoreSecrets();
    await _migrateCacheFormat();
    favorites.addAll(_prefs.getStringList('favorites') ?? const []);
    favOrder = [...(_prefs.getStringList('favOrder') ?? const [])];
    history = _decodeList('history', Channel.fromJson).map(_hydrate).toList();
    try {
      final raw = jsonDecode(_prefs.getString('resume') ?? '{}') as Map<String, dynamic>;
      raw.forEach((k, v) => resume[k] = Resume.fromJson(v as Map<String, dynamic>));
    } catch (_) {}

    _loadScheduled();
    _pinHash = _prefs.getString('pinHash');
    _pinSalt = _prefs.getString('pinSalt');
    updateSource = _prefs.getString('updateSource') ?? updateSource;
    autoUpdate = _prefs.getBool('autoUpdate') ?? true;
    lockedCats.addAll(_prefs.getStringList('lockedCats') ?? const []);
    hiddenCats.addAll(_prefs.getStringList('hiddenCats') ?? const []);
  }

  List<T> _decodeList<T>(String key, T Function(Map<String, dynamic>) f) {
    try {
      return (jsonDecode(_prefs.getString(key) ?? '[]') as List).map((e) => f(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Reopens the last list. Cached lists show up immediately.
  Future<void> restoreLast() async {
    final last = _prefs.getString('active');
    if (last == kAllSources && sources.length > 1) {
      await openAll();
    } else if (last != null) {
      for (final s in sources) {
        if (s.name == last) {
          await open(s);
          return;
        }
      }
    }
  }

  // ------------------------------------------------------------- sources

  /// Passwords (and remote M3U URLs, which usually embed a token) go to the Windows
  /// Credential Manager. If the store is unavailable they stay in the preferences, as before.
  /// Returns true when no secret had to be left in the preferences.
  Future<bool> _saveSources() async {
    final out = <Map<String, dynamic>>[];
    var allSafe = true;
    for (final s in sources) {
      var safe = true;
      if (s.password?.isNotEmpty ?? false) {
        safe &= await trySecretWrite(secretStore, secretKey(s.name, 'pass'), s.password!);
      }
      if (s.hasRemoteM3u) safe &= await trySecretWrite(secretStore, secretKey(s.name, 'm3u'), s.m3uUrl!);
      allSafe &= safe;
      out.add(s.toJson(secrets: !safe));
    }
    await _prefs.setString('sources', jsonEncode(out));
    return allSafe;
  }

  /// Fills in passwords from the secure store; lists saved by older versions (password in
  /// the preferences) are migrated into it on the spot.
  Future<void> _restoreSecrets() async {
    var legacy = false;
    for (var i = 0; i < sources.length; i++) {
      final s = sources[i];
      String? pass = s.password, m3u = s.m3uUrl;
      if (pass?.isNotEmpty ?? false) {
        legacy = true; // was stored in clear text
      } else {
        pass = await _readSecret(secretKey(s.name, 'pass'));
      }
      if (s.hasRemoteM3u) {
        legacy = true;
      } else if (s.kind == SourceKind.m3u && (m3u == null || m3u.isEmpty)) {
        m3u = await _readSecret(secretKey(s.name, 'm3u'));
      }
      sources[i] = s.withSecrets(password: pass, m3uUrl: m3u);
    }
    if (legacy && await _saveSources()) {
      await LibraryCache.clear(); // old caches hold full stream URLs with the credentials
      Log.i('credentials migrated to the secure store');
    }
  }

  /// Caches written before format 2 kept M3U tokens in clear text: drop them (they are rebuilt
  /// on the next load) and rewrite the history without credentials.
  Future<void> _migrateCacheFormat() async {
    if ((_prefs.getInt('cacheFormat') ?? 0) >= 2) return;
    await LibraryCache.clear();
    history = _decodeList('history', Channel.fromJson).map(_hydrate).toList();
    await _saveHistory();
    await _prefs.setInt('cacheFormat', 2);
  }

  Future<String?> _readSecret(String key) async {
    try {
      return await secretStore.read(key);
    } catch (e) {
      Log.w('secure store read failed: ${e.runtimeType}');
      return null;
    }
  }

  Source? _sourceNamed(String name) {
    for (final s in sources) {
      if (s.name == name) return s;
    }
    return null;
  }

  /// What must be kept out of the disk for a list (null = nothing secret in its URLs).
  ScrubSpec? _specFor(Source s) {
    if (s.kind == SourceKind.xtream) return ScrubSpec(user: s.username ?? '', pass: s.password ?? '');
    final secrets = s.hasRemoteM3u ? ScrubSpec.m3uSecrets(s.m3uUrl!) : const <String, String>{};
    return secrets.isEmpty ? null : ScrubSpec(secrets: secrets);
  }

  ScrubSpec? _specForName(String sourceName) {
    final s = _sourceNamed(sourceName);
    return s == null ? null : _specFor(s);
  }

  /// Puts the credentials back into a URL that was stored without them.
  Channel _hydrate(Channel c) {
    final spec = _specForName(c.source);
    if (spec == null || !c.url.contains('{')) return c;
    return c.copyWith(url: spec.hydrateUrl(c.url));
  }

  Future<void> _cacheSave(Source s, LoadedLibrary lib) => LibraryCache.save(s.name, lib, scrub: _specFor(s));

  Future<({LoadedLibrary lib, DateTime saved})?> _cacheLoad(Source s) =>
      LibraryCache.load(s.name, spec: _specFor(s));

  Future<void> addSource(Source s) async {
    sources.removeWhere((e) => e.name == s.name);
    sources.add(s);
    await _saveSources();
    await open(s, force: true);
  }

  Future<void> removeSource(Source s) async {
    sources.remove(s);
    await _saveSources();
    for (final field in ['pass', 'm3u']) {
      try {
        await secretStore.delete(secretKey(s.name, field));
      } catch (_) {}
    }
    if (active == s) {
      closeSource();
      await _prefs.remove('active');
    }
    notifyListeners();
  }

  void closeSource() {
    active = null;
    merged = false;
    library = null;
    epg.replaceWith({});
    notifyListeners();
  }

  Future<LoadedLibrary> _fetch(Source s) async {
    if (s.kind == SourceKind.xtream) {
      final c = XtreamClient(s.server!, s.username!, s.password!, src: s.name);
      final lib = await c.load();
      clients[s.name] = c;
      return lib;
    }
    final src = s.m3uUrl!;
    final Uint8List bytes;
    if (src.startsWith('http')) {
      final r = await sharedClient.get(Uri.parse(src)).timeout(const Duration(seconds: 90));
      if (r.statusCode != 200) throw LocalizedError('err_status', {'code': '${r.statusCode}'});
      bytes = r.bodyBytes;
    } else {
      bytes = await File(src).readAsBytes();
    }
    final lib = await parseM3uBytesAsync(bytes, src: s.name);
    if (lib.items.isEmpty) throw const LocalizedError('err_list_empty');
    return lib;
  }

  /// Makes sure the Xtream client of a cached source exists (needed for series episodes).
  void _ensureClient(Source s) {
    if (s.kind == SourceKind.xtream && !clients.containsKey(s.name)) {
      clients[s.name] = XtreamClient(s.server!, s.username!, s.password!, src: s.name);
    }
  }

  /// Opens one list: instant from cache when available, then refreshes in the background.
  Future<void> open(Source s, {bool force = false}) async {
    error = null;
    merged = false;
    final cached = await _cacheLoad(s);
    if (cached != null) {
      _ensureClient(s);
      library = cached.lib;
      active = s;
      await _prefs.setString('active', s.name);
      _loadEpg();
      notifyListeners();
      final stale = DateTime.now().difference(cached.saved) > _cacheFreshness;
      if (force || stale) {
        refreshing = true;
        notifyListeners();
        try {
          final lib = await _fetch(s);
          if (active == s) {
            library = lib;
            _loadEpg();
          }
          await _cacheSave(s, lib);
        } catch (e) {
          Log.w('background refresh failed for ${s.name}: $e'); // cached copy keeps working
        } finally {
          refreshing = false;
          notifyListeners();
        }
      }
      return;
    }

    loading = true;
    notifyListeners();
    try {
      final lib = await _fetch(s);
      library = lib;
      active = s;
      await _prefs.setString('active', s.name);
      await _cacheSave(s, lib);
      _loadEpg();
    } catch (e) {
      error = errorText(lang, e);
      Log.e('open ${s.name} failed', e);
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// Merges every saved list into a single library.
  Future<void> openAll() async {
    error = null;
    loading = true;
    notifyListeners();
    try {
      final libs = await Future.wait(sources.map((s) async {
        _ensureClient(s);
        final cached = await _cacheLoad(s);
        if (cached != null) return cached.lib;
        final lib = await _fetch(s);
        await _cacheSave(s, lib);
        return lib;
      }));
      library = LoadedLibrary.merge(libs);
      merged = true;
      active = null;
      await _prefs.setString('active', kAllSources);
      _loadEpg();
    } catch (e) {
      error = errorText(lang, e);
      Log.e('openAll failed', e);
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> reload() async {
    if (merged) {
      await LibraryCache.clear();
      await openAll();
    } else if (active != null) {
      await open(active!, force: true);
    }
  }

  void _loadEpg() {
    final lib = library;
    if (lib == null) return;
    final urls = epgUrlsFor(merged ? sources : [?active], lib);
    if (urls.isEmpty) return;
    final wanted = {for (final c in lib.items) if (c.type == ContentType.live && c.epgId != null) c.epgId!};
    () async {
      try {
        await epg.load(urls, wanted);
        notifyListeners();
      } catch (e) {
        Log.w('EPG load failed: $e');
      }
    }();
  }

  /// Guide URLs of every list in scope (all of them in the merged view): the one set on the
  /// list, the Xtream xmltv.php, or — for M3U lists with none — the one named in the playlist.
  @visibleForTesting
  static Set<String> epgUrlsFor(Iterable<Source> scope, LoadedLibrary lib) {
    final urls = <String>{};
    var needsLibraryUrl = false;
    for (final s in scope) {
      if (s.epgUrl?.isNotEmpty ?? false) {
        urls.add(s.epgUrl!);
      } else if (s.kind == SourceKind.xtream && s.server != null) {
        urls.add(XtreamClient(s.server!, s.username ?? '', s.password ?? '').epgUrl);
      } else {
        needsLibraryUrl = true;
      }
    }
    if ((urls.isEmpty || needsLibraryUrl) && lib.epgUrl != null) urls.add(lib.epgUrl!);
    return urls;
  }

  Object? _variantsFor;
  Map<String, List<Channel>> _variants = const {};

  /// Other versions of the same channel (HD / FHD / 4K ...) found in the list, best first.
  List<Channel> variantsOf(Channel c) {
    final lib = library;
    if (lib == null || c.type != ContentType.live) return const [];
    if (!identical(_variantsFor, lib)) {
      _variants = buildVariantIndex(lib.items); // built once per library, on first use
      _variantsFor = lib;
    }
    final list = _variants[baseName(c.name)];
    if (list == null) return const [];
    final out = list.where((x) => x.source == c.source || c.source.isEmpty).toList();
    out.sort((a, b) => (tierOf(b.name)?.index ?? -1).compareTo(tierOf(a.name)?.index ?? -1));
    return out;
  }

  XtreamClient? xtreamFor(Channel c) => clients[c.source] ?? (active != null ? clients[active!.name] : null);

  // ----------------------------------------------------------- settings

  Future<void> setLang(String v) async {
    lang = v;
    await _prefs.setString('lang', v);
    notifyListeners();
  }

  Future<void> setQuality(String v) async {
    quality = v;
    await _prefs.setString('quality', v);
    notifyListeners();
  }

  Future<void> setHwdec(bool v) async {
    hwdec = v;
    await _prefs.setBool('hwdec', v);
    notifyListeners();
  }

  Future<void> setHideBroken(bool v) async {
    hideBroken = v;
    await _prefs.setBool('hideBroken', v);
    notifyListeners();
  }

  /// Merges a (possibly partial) test run into the broken set: only the [tested] channels
  /// change — the ones now failing are added, the ones now fine are dropped. Anything
  /// marked before and not retested stays.
  Future<void> updateBroken({required Set<String> tested, required Set<String> failed}) async {
    broken
      ..removeAll(tested)
      ..addAll(failed);
    await _prefs.setStringList('broken', broken.toList());
    notifyListeners();
  }

  Future<void> setBroken(Set<String> ids) async {
    broken
      ..clear()
      ..addAll(ids);
    await _prefs.setStringList('broken', broken.toList());
    notifyListeners();
  }

  // ------------------------------------------------------------ schedule

  List<ScheduledItem> scheduled = [];
  final Set<String> _notified = {};
  final Map<String, Recorder> _recorders = {};
  Timer? _schedTimer;
  Recorder Function() recorderFactory = StreamRecorder.new; // replaced in tests
  String Function(String channel, String title, DateTime start) recordingPath = recordingFileFor;
  void Function(ScheduledItem item)? onReminder; // set by the UI to show it
  void Function(ScheduledItem item, String? path)? onRecordingFinished;

  bool isScheduled(String id) => scheduled.any((s) => s.id == id);
  bool isRecordingNow(String id) => _recorders.containsKey(id);

  static String scheduleId(ScheduleKind k, String channelId, DateTime start) =>
      '${k.name}|$channelId|${start.millisecondsSinceEpoch}';

  Future<void> addScheduled(ScheduledItem it) async {
    scheduled.removeWhere((s) => s.id == it.id);
    scheduled.add(it);
    scheduled.sort((a, b) => a.start.compareTo(b.start));
    await _saveScheduled();
    notifyListeners();
    unawaited(scheduleTick());
  }

  Future<void> removeScheduled(String id) async {
    final rec = _recorders.remove(id);
    if (rec != null) await rec.stop();
    scheduled.removeWhere((s) => s.id == id);
    await _saveScheduled();
    notifyListeners();
  }

  Future<void> _saveScheduled() => _prefs.setString(
      'scheduled', jsonEncode(scheduled.map((e) => e.toJson(scrub: _specForName(e.source)?.scrubUrl)).toList()));

  void _loadScheduled() {
    scheduled = _decodeList('scheduled', ScheduledItem.fromJson).map((it) {
      final spec = _specForName(it.source);
      return spec == null ? it : it.copyWith(url: spec.hydrateUrl(it.url));
    }).toList();
  }

  /// Checks every 15 s whether a recording must start/stop or a reminder is due.
  void startScheduler() {
    _schedTimer ??= Timer.periodic(const Duration(seconds: 15), (_) => scheduleTick());
    unawaited(scheduleTick());
  }

  @visibleForTesting
  Future<void> scheduleTick({DateTime? now}) async {
    final plan = planSchedule(scheduled, now ?? DateTime.now(), recording: _recorders.keys.toSet(), notified: _notified);
    if (plan.isEmpty) return;
    for (final it in plan.startRecording) {
      try {
        final rec = recorderFactory();
        _recorders[it.id] = rec;
        await rec.start(it.url, recordingPath(it.channelName, it.title, it.start));
      } catch (e) {
        Log.e('scheduled recording failed to start', e);
        _recorders.remove(it.id);
        scheduled.removeWhere((s) => s.id == it.id);
      }
    }
    for (final it in plan.stopRecording) {
      final rec = _recorders.remove(it.id);
      scheduled.removeWhere((s) => s.id == it.id);
      if (rec != null) {
        final path = rec.path;
        await rec.stop();
        onRecordingFinished?.call(it, path);
      }
    }
    for (final it in plan.remind) {
      _notified.add(it.id);
      onReminder?.call(it);
    }
    for (final it in plan.expired) {
      scheduled.removeWhere((s) => s.id == it.id);
      _notified.remove(it.id);
    }
    await _saveScheduled();
    notifyListeners();
  }

  // -------------------------------------------------------------- backup

  /// Everything the user would miss on a new PC. The file is encrypted by [BackupCodec].
  Map<String, dynamic> exportData() => {
        'app': 'lumora',
        'version': appVersion,
        'sources': sources.map((s) => s.toJson()).toList(),
        'favorites': favorites.toList(),
        'favOrder': favOrder,
        'resume': resume.map((k, v) => MapEntry(k, v.toJson())),
        'broken': broken.toList(),
        'lockedCats': lockedCats.toList(),
        'hiddenCats': hiddenCats.toList(),
        'pinHash': _pinHash,
        'pinSalt': _pinSalt,
        'scheduled': scheduled.map((e) => e.toJson()).toList(),
        'settings': {
          'lang': lang,
          'quality': quality,
          'hwdec': hwdec,
          'hideBroken': hideBroken,
          'updateSource': updateSource,
          'autoUpdate': autoUpdate,
        },
      };

  /// Merges a backup into the current data: lists with the same name are replaced,
  /// favorites / blocks / broken marks are added, the newest playback position wins.
  Future<void> importData(Map<String, dynamic> d) async {
    if (d['app'] != 'lumora') throw const LocalizedError('err_backup_file');
    for (final j in (d['sources'] as List? ?? const [])) {
      final s = Source.fromJson(j as Map<String, dynamic>);
      sources.removeWhere((e) => e.name == s.name);
      sources.add(s);
    }
    await _saveSources();
    final favIds = [...(d['favOrder'] as List? ?? const []).cast<String>(), ...(d['favorites'] as List? ?? const []).cast<String>()];
    for (final id in favIds) {
      if (favorites.add(id)) favOrder.add(id);
    }
    await _prefs.setStringList('favorites', favorites.toList());
    await _prefs.setStringList('favOrder', favOrder);
    (d['resume'] as Map<String, dynamic>? ?? const {}).forEach((k, v) {
      final r = Resume.fromJson(v as Map<String, dynamic>);
      final mine = resume[k];
      if (mine == null || r.ts > mine.ts) resume[k] = r;
    });
    await _prefs.setString('resume', jsonEncode(resume.map((k, v) => MapEntry(k, v.toJson()))));
    broken.addAll((d['broken'] as List? ?? const []).cast<String>());
    lockedCats.addAll((d['lockedCats'] as List? ?? const []).cast<String>());
    hiddenCats.addAll((d['hiddenCats'] as List? ?? const []).cast<String>());
    await _prefs.setStringList('broken', broken.toList());
    await _prefs.setStringList('lockedCats', lockedCats.toList());
    await _prefs.setStringList('hiddenCats', hiddenCats.toList());
    if (_pinHash == null && d['pinHash'] is String && d['pinSalt'] is String) {
      _pinHash = d['pinHash'] as String;
      _pinSalt = d['pinSalt'] as String;
      await _prefs.setString('pinHash', _pinHash!);
      await _prefs.setString('pinSalt', _pinSalt!);
    }
    for (final j in (d['scheduled'] as List? ?? const [])) {
      final it = ScheduledItem.fromJson(j as Map<String, dynamic>);
      if (it.stop.isAfter(DateTime.now()) && !isScheduled(it.id)) scheduled.add(it);
    }
    scheduled.sort((a, b) => a.start.compareTo(b.start));
    await _saveScheduled();
    final st = d['settings'] as Map<String, dynamic>? ?? const {};
    if (st['lang'] is String && supportedLanguages.containsKey(st['lang'])) await setLang(st['lang'] as String);
    if (st['quality'] is String) await setQuality(st['quality'] as String);
    if (st['hwdec'] is bool) await setHwdec(st['hwdec'] as bool);
    if (st['hideBroken'] is bool) await setHideBroken(st['hideBroken'] as bool);
    notifyListeners();
  }

  // --------------------------------------------------------- diagnostics

  /// A text report to paste into a bug report. Credentials are stripped.
  Future<String> diagnostics() async {
    final lib = library;
    final b = StringBuffer()
      ..writeln('Lumora $appVersion')
      ..writeln('OS: ${Platform.operatingSystemVersion}')
      ..writeln('Language: $lang  quality: $quality  hwdec: $hwdec  hideBroken: $hideBroken')
      ..writeln('Lists: ${sources.length} (${sources.map((s) => s.kind.name).join(', ')})  merged: $merged  active: ${active?.name ?? '-'}')
      ..writeln('Channels: ${lib?.items.length ?? 0}  categories: ${lib?.categories.length ?? 0}  broken marked: ${broken.length}')
      ..writeln('EPG loaded: ${!epg.isEmpty}')
      ..writeln('Favorites: ${favorites.length}  history: ${history.length}  scheduled: ${scheduled.length}')
      ..writeln('Update source: $updateSource  auto: $autoUpdate  parental PIN: $pinEnabled')
      ..writeln()
      ..writeln('--- log (tail) ---')
      ..write(await Log.read(maxChars: 20000));
    return Log.redact(b.toString());
  }
  // ----------------------------------------------------------- favorites

  bool isFavorite(Channel c) => favorites.contains(c.id);

  Future<void> toggleFavorite(Channel c) async {
    if (favorites.remove(c.id)) {
      favOrder.remove(c.id);
    } else {
      favorites.add(c.id);
      favOrder.add(c.id);
    }
    await _prefs.setStringList('favorites', favorites.toList());
    await _prefs.setStringList('favOrder', favOrder);
    notifyListeners();
  }

  /// Favorites in the user's custom order.
  List<Channel> orderedFavorites() {
    final lib = library;
    if (lib == null) return const [];
    final byId = {for (final c in lib.items) if (favorites.contains(c.id)) c.id: c};
    final out = <Channel>[
      for (final id in favOrder) ?byId.remove(id),
    ];
    out.addAll(byId.values); // favorites saved before ordering existed
    return out;
  }

  Future<void> reorderFavorites(int oldIndex, int newIndex) async {
    final list = orderedFavorites().map((c) => c.id).toList();
    list.insert(newIndex, list.removeAt(oldIndex));
    favOrder = list;
    await _prefs.setStringList('favOrder', favOrder);
    notifyListeners();
  }

  // ------------------------------------------------------------- history

  Future<void> addToHistory(Channel c) async {
    history.removeWhere((e) => e.id == c.id);
    history.insert(0, c);
    if (history.length > 50) history = history.sublist(0, 50);
    await _saveHistory();
    notifyListeners();
  }

  Future<void> _saveHistory() => _prefs.setString(
      'history', jsonEncode(history.map((e) => e.toJson(scrub: _specForName(e.source)?.scrubUrl)).toList()));

  Future<void> clearHistory() async {
    history = [];
    await _prefs.remove('history');
    notifyListeners();
  }

  // ------------------------------------------------------ continue watching

  Resume? resumeFor(String id) => resume[id];

  /// Throttled: persists at most every 10 s unless [force].
  Future<void> saveResume(String id, int posMs, int durMs, {bool force = false}) async {
    if (durMs <= 0) return;
    resume[id] = Resume(posMs, durMs, DateTime.now().millisecondsSinceEpoch);
    if (resume.length > 300) {
      final oldest = resume.entries.toList()..sort((a, b) => a.value.ts.compareTo(b.value.ts));
      for (final e in oldest.take(resume.length - 300)) {
        resume.remove(e.key);
      }
    }
    final now = DateTime.now();
    if (!force && now.difference(_lastResumeWrite) < const Duration(seconds: 10)) return;
    _lastResumeWrite = now;
    await _prefs.setString('resume', jsonEncode(resume.map((k, v) => MapEntry(k, v.toJson()))));
  }

  /// History entries that still have an unfinished position.
  List<Channel> continueWatching() => history.where((c) => resume[c.id]?.resumable ?? false).toList();

  // ------------------------------------------------------------- parental

  static String _hash(String salt, String pin) => sha256.convert(utf8.encode('$salt:$pin')).toString();

  Future<void> setPin(String pin) async {
    final rnd = Random.secure();
    _pinSalt = List.generate(12, (_) => rnd.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    _pinHash = _hash(_pinSalt!, pin);
    unlocked = true;
    await _prefs.setString('pinHash', _pinHash!);
    await _prefs.setString('pinSalt', _pinSalt!);
    notifyListeners();
  }

  Future<void> clearPin() async {
    _pinHash = _pinSalt = null;
    unlocked = false;
    await _prefs.remove('pinHash');
    await _prefs.remove('pinSalt');
    notifyListeners();
  }

  bool verifyPin(String pin) => _pinHash != null && _hash(_pinSalt!, pin) == _pinHash;

  void unlock() {
    unlocked = true;
    notifyListeners();
  }

  void lockAgain() {
    unlocked = false;
    notifyListeners();
  }

  bool isCategoryLocked(String id) => pinEnabled && !unlocked && lockedCats.contains(id);

  /// Whether a channel may be listed right now (not hidden, not behind the PIN).
  bool visible(Channel c) => !hiddenCats.contains(c.categoryId) && !isCategoryLocked(c.categoryId);

  Future<void> setCategoryFlags(String id, {bool? locked, bool? hidden}) async {
    if (locked != null) locked ? lockedCats.add(id) : lockedCats.remove(id);
    if (hidden != null) hidden ? hiddenCats.add(id) : hiddenCats.remove(id);
    await _prefs.setStringList('lockedCats', lockedCats.toList());
    await _prefs.setStringList('hiddenCats', hiddenCats.toList());
    notifyListeners();
  }

  /// Locks every category whose name looks adult. Returns how many were locked.
  Future<int> autoLockAdult() async {
    var n = 0;
    for (final c in library?.categories ?? const <Category>[]) {
      if (_adultRe.hasMatch(c.name) && lockedCats.add(c.id)) n++;
    }
    await _prefs.setStringList('lockedCats', lockedCats.toList());
    notifyListeners();
    return n;
  }
}
