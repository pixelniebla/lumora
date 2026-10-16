import 'dart:io';

import 'package:flutter/scheduler.dart';

/// Nearest-rank percentile of [values] (0-100). Empty list -> 0.
int percentile(List<int> values, double p) {
  if (values.isEmpty) return 0;
  final s = [...values]..sort();
  final i = ((p / 100) * s.length).ceil().clamp(1, s.length) - 1;
  return s[i];
}

/// Cheap always-on performance counters, shown in "Copy diagnostics": time from opening a channel
/// to its first video frame, how many UI frames were slow, and memory use.
class Perf {
  Perf._();
  static final Perf instance = Perf._();

  static const _keep = 60;
  final List<int> zapMs = [];
  int frames = 0, slow = 0, jank = 0;
  int _buildUs = 0, _rasterUs = 0, worstUs = 0;
  bool _started = false;

  /// Starts collecting frame timings (idempotent).
  void start() {
    if (_started) return;
    _started = true;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  void _onTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      addFrame(t.buildDuration.inMicroseconds, t.rasterDuration.inMicroseconds);
    }
  }

  /// A frame is "slow" over 16.7 ms (a 60 Hz miss) and "janky" over 33.4 ms.
  void addFrame(int buildUs, int rasterUs) {
    frames++;
    _buildUs += buildUs;
    _rasterUs += rasterUs;
    final total = buildUs > rasterUs ? buildUs : rasterUs; // build and raster run in parallel threads
    if (total > 16700) slow++;
    if (total > 33400) jank++;
    if (total > worstUs) worstUs = total;
  }

  void recordZap(int ms) {
    zapMs.add(ms);
    if (zapMs.length > _keep) zapMs.removeAt(0);
  }

  void reset() {
    zapMs.clear();
    frames = slow = jank = _buildUs = _rasterUs = worstUs = 0;
  }

  String report() {
    final b = StringBuffer();
    if (zapMs.isEmpty) {
      b.writeln('Channel start (open -> first frame): no data');
    } else {
      final avg = zapMs.reduce((a, c) => a + c) ~/ zapMs.length;
      b.writeln('Channel start (open -> first frame): n=${zapMs.length} avg=${avg}ms '
          'p50=${percentile(zapMs, 50)}ms p95=${percentile(zapMs, 95)}ms max=${percentile(zapMs, 100)}ms');
    }
    if (frames == 0) {
      b.writeln('UI frames: no data');
    } else {
      b.writeln('UI frames: $frames  slow(>16.7ms)=$slow (${(slow * 100 / frames).toStringAsFixed(1)}%)  '
          'janky(>33ms)=$jank  avg build=${(_buildUs / frames / 1000).toStringAsFixed(1)}ms '
          'raster=${(_rasterUs / frames / 1000).toStringAsFixed(1)}ms  worst=${(worstUs / 1000).toStringAsFixed(0)}ms');
    }
    try {
      b.writeln('Memory: rss=${ProcessInfo.currentRss ~/ 1048576} MiB  peak=${ProcessInfo.maxRss ~/ 1048576} MiB');
    } catch (_) {}
    return b.toString().trimRight();
  }
}
