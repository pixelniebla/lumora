import '../models.dart';

/// Quality tiers, ordered from lowest to highest.
enum Tier { sd, hd, fhd, qhd, uhd }

extension TierLabel on Tier {
  String get label => switch (this) {
        Tier.sd => 'SD',
        Tier.hd => '720p',
        Tier.fhd => '1080p',
        Tier.qhd => '2K',
        Tier.uhd => '4K',
      };
}

final _tierPatterns = <Tier, RegExp>{
  Tier.uhd: RegExp(r'(?<![a-z0-9])(4k|uhd|2160p?)(?![a-z0-9])', caseSensitive: false),
  Tier.qhd: RegExp(r'(?<![a-z0-9])(2k|qhd|1440p?)(?![a-z0-9])', caseSensitive: false),
  Tier.fhd: RegExp(r'(?<![a-z0-9])(fhd|full\s?hd|1080[pi]?)(?![a-z0-9])', caseSensitive: false),
  Tier.hd: RegExp(r'(?<![a-z0-9])(hd|720p?)(?![a-z0-9])', caseSensitive: false),
  Tier.sd: RegExp(r'(?<![a-z0-9])(sd|480p?|576p?)(?![a-z0-9])', caseSensitive: false),
};

/// Highest quality tier mentioned in the channel name, or null when it says nothing.
Tier? tierOf(String name) {
  for (final t in [Tier.uhd, Tier.qhd, Tier.fhd, Tier.hd, Tier.sd]) {
    if (_tierPatterns[t]!.hasMatch(name)) return t;
  }
  return null;
}

final _noise = RegExp(
  r'(?<![a-z0-9])(4k|uhd|2160p?|2k|qhd|1440p?|fhd|full\s?hd|1080[pi]?|hd|720p?|sd|480p?|576p?|'
  r'h\.?26[45]|hevc|raw|50\s?fps|60\s?fps|multi|backup|alt)(?![a-z0-9])',
  caseSensitive: false,
);
final _prefix = RegExp(r'^\s*[a-z]{2,3}\s*[|:\-]\s*', caseSensitive: false);
final _brackets = RegExp(r'[\[\(][^\]\)]*[\]\)]');
final _nonAlnum = RegExp(r'[^a-z0-9áéíóúñ]+');

/// Name with quality markers, country prefixes and decorations removed, so that
/// "ES| La 1 FHD" and "La 1 HD [Backup]" end up as the same key.
String baseName(String name) {
  var s = name.toLowerCase().replaceAll(_brackets, ' ').replaceFirst(_prefix, '');
  s = s.replaceAll(_noise, ' ').replaceAll(_nonAlnum, '');
  return s;
}

/// Groups live channels by [baseName]; only groups with 2+ entries are kept.
Map<String, List<Channel>> buildVariantIndex(Iterable<Channel> channels) {
  final map = <String, List<Channel>>{};
  for (final c in channels) {
    if (c.type != ContentType.live) continue;
    final k = baseName(c.name);
    if (k.length < 2) continue;
    (map[k] ??= []).add(c);
  }
  map.removeWhere((_, v) => v.length < 2);
  return map;
}
