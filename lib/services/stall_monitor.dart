/// What to do when playback freezes to refill the buffer.
enum StallAction { none, raiseBuffer, suggestLower }

/// Counts mid-playback freezes of the current channel. The first one means the provider (or the
/// connection) cannot keep up in real time, so the player should wait for a bigger buffer before
/// resuming; a second one shortly after suggests switching to a lower-quality version of the channel.
class StallMonitor {
  final Duration settle; // ignore buffering this soon after playback started (initial load)
  final Duration window; // freezes closer than this count as "repeated"
  StallMonitor({this.settle = const Duration(seconds: 3), this.window = const Duration(seconds: 120)});

  DateTime? _playingSince;
  DateTime? _lastStall;
  bool _raised = false, _suggested = false;

  void reset() {
    _playingSince = null;
    _lastStall = null;
    _raised = _suggested = false;
  }

  void onPlaying(DateTime now) => _playingSince ??= now;

  StallAction onBuffering(bool buffering, DateTime now) {
    final since = _playingSince;
    if (!buffering || since == null || now.difference(since) < settle) return StallAction.none;
    final repeated = _lastStall != null && now.difference(_lastStall!) < window;
    _lastStall = now;
    if (!_raised) {
      _raised = true;
      return StallAction.raiseBuffer;
    }
    if (repeated && !_suggested) {
      _suggested = true;
      return StallAction.suggestLower;
    }
    return StallAction.none;
  }
}
