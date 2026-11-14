import 'dart:async';

import 'package:flutter/foundation.dart';

/// One clock for every "đã chờ 12 phút" on screen. It ticks on the minute
/// only while something listens, so a board of 40 tables runs one timer and
/// rebuilds only the labels that show the time, not the whole screen.
class MinuteClock extends ChangeNotifier implements ValueListenable<DateTime> {
  MinuteClock({DateTime Function()? now}) : _now = now ?? DateTime.now;

  /// The app-wide clock; tests may pass their own to the widgets instead.
  static final shared = MinuteClock();

  final DateTime Function() _now;
  Timer? _timer;

  @override
  DateTime get value => _now();

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    if (_timer == null) _schedule();
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    if (!hasListeners) {
      _timer?.cancel();
      _timer = null;
    }
  }

  void _schedule() {
    final now = _now();
    final next = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute + 1,
    );
    _timer = Timer(next.difference(now), () {
      _timer = null;
      if (!hasListeners) return;
      notifyListeners();
      if (hasListeners) _schedule();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }
}
