import 'dart:async';

import '../../../../core/ui/controllers/refresh_throttle.dart';
import 'order_events.dart';

/// Keeps the sidebar's takeaway badge current without listing every active
/// takeaway order each time the sidebar opens. The board publishes the count
/// it already has; opening the sidebar asks the server only when that count
/// is old or a takeaway order changed here since.
class TakeawayCountRefresher {
  TakeawayCountRefresher({
    required Future<int?> Function() read,
    required void Function(int count) publish,
    required OrderEvents events,
    RefreshThrottle? freshness,
  }) : _read = read,
       _publish = publish,
       _events = events,
       _fresh = freshness ?? RefreshThrottle(),
       _revision = events.revision {
    events.addListener(_event);
  }

  final Future<int?> Function() _read;
  final void Function(int count) _publish;
  final OrderEvents _events;
  final RefreshThrottle _fresh;
  int _revision;

  void _event() {
    if (_revision == _events.revision) return;
    _revision = _events.revision;
    // A change made on this device outside a table session can be a takeaway
    // order. Remote hints carry no service type; the time window covers them.
    if (_events.remote == null && _events.sessionId == null) _fresh.markStale();
  }

  /// A count known elsewhere (the takeaway board) is as good as a fetch.
  void record(int count) {
    _publish(count);
    _fresh.markLoaded();
  }

  /// When the badge is about to be seen.
  Future<void> refreshIfStale() => _fresh.isFresh ? Future.value() : refresh();

  /// Always asks the server, e.g. on pull-to-refresh.
  Future<void> refresh() async {
    final count = await _read();
    if (count == null) {
      _fresh.markStale();
    } else {
      record(count);
    }
  }

  void dispose() => _events.removeListener(_event);
}
