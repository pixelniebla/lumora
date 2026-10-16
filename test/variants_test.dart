import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/models.dart';
import 'package:iptv_player/services/channel_variants.dart';

Channel _c(String name, {ContentType t = ContentType.live}) =>
    Channel(id: name, name: name, url: 'http://x/$name', categoryId: 'c', type: t);

void main() {
  test('detecta la calidad por el nombre', () {
    expect(tierOf('La 1 4K'), Tier.uhd);
    expect(tierOf('DAZN UHD'), Tier.uhd);
    expect(tierOf('Movistar 2K'), Tier.qhd);
    expect(tierOf('ES| La 1 FHD'), Tier.fhd);
    expect(tierOf('La 1 1080p'), Tier.fhd);
    expect(tierOf('La 1 HD'), Tier.hd);
    expect(tierOf('La 1 SD'), Tier.sd);
    expect(tierOf('La 1'), isNull);
    expect(tierOf('Shd Channel'), isNull); // "hd" dentro de otra palabra no cuenta
  });

  test('nombres base iguales para versiones del mismo canal', () {
    final k = baseName('La 1');
    expect(baseName('ES| La 1 FHD'), k);
    expect(baseName('La 1 HD [Backup]'), k);
    expect(baseName('LA 1 4K H265'), k);
    expect(baseName('La 2'), isNot(k));
  });

  test('índice de variantes: agrupa HD/FHD/4K y descarta canales sin hermanos', () {
    final idx = buildVariantIndex([
      _c('La 1 HD'), _c('La 1 FHD'), _c('La 1 4K'), _c('Cuatro HD'),
      _c('Peli X HD', t: ContentType.movie), _c('Peli X 4K', t: ContentType.movie),
    ]);
    expect(idx.length, 1);
    expect(idx[baseName('La 1')]!.map((c) => c.name), ['La 1 HD', 'La 1 FHD', 'La 1 4K']);
  });
}
