import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/services/perf.dart';

void main() {
  test('percentile: rango más cercano', () {
    expect(percentile([], 95), 0);
    expect(percentile([5], 50), 5);
    expect(percentile([10, 20, 30, 40, 50, 60, 70, 80, 90, 100], 50), 50);
    expect(percentile([10, 20, 30, 40, 50, 60, 70, 80, 90, 100], 95), 100);
    expect(percentile([3, 1, 2], 100), 3);
  });

  test('Perf: cuenta fotogramas lentos y arranques de canal en el informe', () {
    final p = Perf.instance..reset();
    p.addFrame(5000, 4000); // ok
    p.addFrame(20000, 3000); // lento (build 20 ms)
    p.addFrame(2000, 40000); // janky (raster 40 ms)
    p.recordZap(800);
    p.recordZap(1200);
    p.recordZap(5000);
    final r = p.report();
    expect(r, contains('UI frames: 3  slow(>16.7ms)=2 (66.7%)  janky(>33ms)=1'));
    expect(r, contains('n=3 avg=2333ms p50=1200ms p95=5000ms'));
    expect(r, contains('Memory: rss='));
    p.reset();
    expect(p.report(), contains('Channel start (open -> first frame): no data'));
  });
}
