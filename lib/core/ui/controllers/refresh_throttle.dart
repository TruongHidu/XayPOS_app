/// Lets a "refresh when shown" skip the request when the last successful load
/// is recent, e.g. the counts behind sidebar badges that open many times a
/// minute. Loads driven by real changes (realtime events, pull-to-refresh)
/// should bypass it.
class RefreshThrottle {
  RefreshThrottle({
    this.window = const Duration(seconds: 30),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final Duration window;
  final DateTime Function() _now;
  DateTime? _loadedAt;

  /// Loaded successfully less than [window] ago, with nothing known changed.
  bool get isFresh {
    final at = _loadedAt;
    return at != null && _now().difference(at) < window;
  }

  void markLoaded() => _loadedAt = _now();

  /// After a failure or a change the value may no longer be right.
  void markStale() => _loadedAt = null;
}
