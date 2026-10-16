import 'dart:async';
import 'dart:ui' show Offset;

/// Visible by default; hides after [idle] without [poke]. Used for the player's top bar.
class IdleVisibility {
  final Duration idle;
  final void Function(bool visible) onChanged;
  IdleVisibility({required this.idle, required this.onChanged});

  bool visible = true;
  Timer? _timer;

  /// Call on any mouse movement: shows the bar and restarts the countdown.
  void poke() {
    _timer?.cancel();
    if (!visible) {
      visible = true;
      onChanged(true);
    }
    _timer = Timer(idle, () {
      visible = false;
      onChanged(false);
    });
  }

  void dispose() => _timer?.cancel();
}

/// Detects a double click from raw pointer-down events (no gesture-arena competition).
class DoubleClickDetector {
  final Duration maxGap;
  final double maxDistance;
  final DateTime Function() clock;
  DoubleClickDetector({this.maxGap = const Duration(milliseconds: 350), this.maxDistance = 12, DateTime Function()? clock})
      : clock = clock ?? DateTime.now;

  DateTime? _last;
  Offset _pos = Offset.zero;

  /// Returns true when this press completes a double click.
  bool press(Offset position) {
    final now = clock();
    final prev = _last;
    if (prev != null && now.difference(prev) < maxGap && (position - _pos).distance < maxDistance) {
      _last = null;
      return true;
    }
    _last = now;
    _pos = position;
    return false;
  }
}
