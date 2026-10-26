import 'dart:collection';

/// Bounded, scope-owned event deduplication. Versions are not global cursors.
class RealtimeEventWindow {
  RealtimeEventWindow({
    this.capacity = 512,
    this.ttl = const Duration(minutes: 10),
    DateTime Function()? now,
  }) : assert(capacity > 0),
       _now = now ?? DateTime.now;
  final int capacity;
  final Duration ttl;
  final DateTime Function() _now;
  final LinkedHashMap<String, DateTime> _seen = LinkedHashMap();
  int get length => _seen.length;
  bool accept(String id) {
    final now = _now();
    _seen.removeWhere((_, time) => now.difference(time) >= ttl);
    if (_seen.containsKey(id)) return false;
    _seen[id] = now;
    while (_seen.length > capacity) {
      _seen.remove(_seen.keys.first);
    }
    return true;
  }

  void clear() => _seen.clear();
}
