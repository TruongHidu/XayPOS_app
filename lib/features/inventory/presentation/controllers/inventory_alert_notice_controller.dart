import 'dart:async';
import 'package:flutter/foundation.dart';
import 'inventory_alert_notice.dart';

/// One short-lived notice per scope; later bursts update it instead of queuing.
class InventoryAlertNoticeController extends ChangeNotifier {
  InventoryAlertNoticeController({
    this.duration = const Duration(seconds: 5),
    this.capacity = 512,
  });
  final Duration duration;
  final int capacity;
  InventoryAlertNotice? _notice;
  InventoryAlertNotice? get notice => _notice;
  Timer? _expiry;
  bool _disposed = false;

  void show(InventoryAlertNotice batch) {
    if (_disposed || batch.alertIds.isEmpty) return;
    final previous = _notice;
    final all = {...?previous?.alertIds, ...batch.alertIds};
    final hasMore =
        (previous?.hasMore ?? false) || batch.hasMore || all.length > capacity;
    if (previous != null &&
        previous.alertIds.containsAll(batch.alertIds) &&
        previous.hasMore == hasMore) {
      return;
    }
    final next = InventoryAlertNotice(
      alertIds: all.take(capacity).toSet(),
      hasMore: hasMore,
    );
    _notice = next;
    _expiry?.cancel();
    _expiry = Timer(duration, () => dismiss(next));
    notifyListeners();
  }

  void dismiss([InventoryAlertNotice? expected]) {
    if (_disposed || expected != null && !identical(expected, _notice)) return;
    _expiry?.cancel();
    _expiry = null;
    if (_notice == null) return;
    _notice = null;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _expiry?.cancel();
    _notice = null;
    super.dispose();
  }
}
