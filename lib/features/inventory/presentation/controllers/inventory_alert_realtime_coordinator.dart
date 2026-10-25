import 'dart:async';
import 'dart:collection';
import '../../../../core/realtime/realtime_connection_service.dart';
import '../../../../core/realtime/realtime_envelope.dart';
import 'inventory_alert_notice.dart';
import 'inventory_events.dart';

typedef InventoryAlertNoticeListener =
    void Function(InventoryAlertNotice notice);

/// Scope-owned hint cache. REST DTOs remain exclusively in existing controllers.
class InventoryAlertRealtimeCoordinator {
  InventoryAlertRealtimeCoordinator(
    this.events, {
    this.debounce = const Duration(milliseconds: 400),
    this.capacity = 512,
    this.ttl = const Duration(minutes: 10),
    this.onNewAlerts,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now {
    events.addListener(_local);
  }
  final InventoryEvents events;
  final Duration debounce, ttl;
  final int capacity;
  final InventoryAlertNoticeListener? onNewAlerts;
  final DateTime Function() _now;
  final Set<InventoryAlertNoticeListener> _noticeListeners = {};
  final LinkedHashMap<String, DateTime> _seen = LinkedHashMap();
  final LinkedHashMap<String, ({int version, DateTime time})> _versions =
      LinkedHashMap();
  final Map<String, int> _dirty = {};
  final Set<String> _newAlertIds = {};
  Timer? _timer;
  bool _all = false, _disposed = false, _foreground = true;
  bool _moreNewAlerts = false;
  int _revision = 0;
  int get cachedEventCount => _seen.length;
  int get cachedResourceCount => _versions.length;
  RealtimeChannel get channel => RealtimeChannel(
    id: 'inventory-alerts',
    destination: '/user/queue/inventory-alerts',
    message: receive,
    resync: resync,
  );

  void addNoticeListener(InventoryAlertNoticeListener listener) {
    if (_disposed) return;
    _noticeListeners.add(listener);
  }

  void removeNoticeListener(InventoryAlertNoticeListener listener) {
    _noticeListeners.remove(listener);
  }

  void setForeground(bool value) {
    if (_disposed || _foreground == value) return;
    _foreground = value;
    if (!value) {
      _timer?.cancel();
      _timer = null;
      _clearNotices();
    } else {
      resync();
    }
  }

  void receive(String body) {
    if (_disposed || !_foreground) return;
    final event = RealtimeEnvelope.parse(body);
    if (event == null ||
        event.schemaVersion != 1 ||
        event.type != 'INVENTORY_LOW_STOCK_ALERT_CHANGED' ||
        event.resourceType != 'LOW_STOCK_ALERT') {
      return;
    }
    final payload = event.payload;
    if (payload['warehouseId'] is! String ||
        (payload['warehouseId'] as String).isEmpty ||
        payload['ingredientId'] is! String ||
        (payload['ingredientId'] as String).isEmpty ||
        !const {
          'OPEN',
          'ACKNOWLEDGED',
          'RESOLVED',
        }.contains(payload['status']) ||
        payload['resolutionReason'] != null &&
            payload['resolutionReason'] is! String) {
      return;
    }
    _prune();
    if (_seen.containsKey(event.eventId)) return;
    _rememberEvent(event.eventId);
    final previous = _versions[event.resourceId];
    if (previous != null && event.resourceVersion <= previous.version) return;
    _rememberVersion(event.resourceId, event.resourceVersion);
    if (payload['status'] == 'OPEN') {
      if (previous == null) {
        if (_newAlertIds.length < capacity) {
          _newAlertIds.add(event.resourceId);
        } else {
          _moreNewAlerts = true;
        }
      }
    } else {
      _newAlertIds.remove(event.resourceId);
    }
    _dirty[event.resourceId] = event.resourceVersion;
    if (_dirty.length > capacity) {
      _all = true;
      _dirty.clear();
    }
    _schedule();
  }

  void _prune() {
    final cutoff = _now().subtract(ttl);
    _seen.removeWhere((_, time) => time.isBefore(cutoff));
    _versions.removeWhere((_, value) => value.time.isBefore(cutoff));
  }

  void _rememberEvent(String id) {
    _seen[id] = _now();
    while (_seen.length > capacity) {
      _seen.remove(_seen.keys.first);
    }
  }

  void _rememberVersion(String id, int version) {
    _versions.remove(id);
    _versions[id] = (version: version, time: _now());
    while (_versions.length > capacity) {
      _versions.remove(_versions.keys.first);
    }
  }

  void _local() {
    if (_disposed || _revision == events.revision) return;
    _revision = events.revision;
    final change = events.change;
    if (change?.kind != InventoryChangeKind.alert ||
        change?.alertId == null ||
        change?.resourceVersion == null) {
      return;
    }
    _prune();
    final id = change!.alertId!, version = change.resourceVersion!;
    if (version < (_versions[id]?.version ?? -1)) return;
    _rememberVersion(id, version);
    _newAlertIds.remove(id);
    if ((_dirty[id] ?? version + 1) <= version) _dirty.remove(id);
  }

  void resync() {
    if (_disposed) return;
    _clearNotices();
    _all = true;
    _schedule();
  }

  void cancelPending() {
    if (_disposed) return;
    _timer?.cancel();
    _timer = null;
    _dirty.clear();
    _all = false;
    _clearNotices();
  }

  void _clearNotices() {
    _newAlertIds.clear();
    _moreNewAlerts = false;
  }

  void _schedule() {
    if (_disposed || !_foreground || _timer != null) return;
    _timer = Timer(debounce, () {
      _timer = null;
      if (_disposed || !_foreground || !_all && _dirty.isEmpty) return;
      final ids = _all ? <String>{} : _dirty.keys.toSet();
      // Keep overflow conservative: if every retained OPEN was superseded,
      // an untracked overflow ID alone must not produce a stale notice.
      final notice = _newAlertIds.isNotEmpty
          ? InventoryAlertNotice(
              alertIds: _newAlertIds,
              hasMore: _moreNewAlerts,
            )
          : null;
      _dirty.clear();
      _all = false;
      _clearNotices();
      events.emit(
        InventoryChange(
          InventoryChangeKind.alertSync,
          null,
          alertIds: Set.unmodifiable(ids),
        ),
      );
      if (!_disposed && _foreground && notice != null) {
        onNewAlerts?.call(notice);
        for (final listener in _noticeListeners.toList()) {
          if (_disposed || !_foreground) break;
          if (_noticeListeners.contains(listener)) listener(notice);
        }
      }
    });
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    events.removeListener(_local);
    _seen.clear();
    _versions.clear();
    _dirty.clear();
    _clearNotices();
    _noticeListeners.clear();
  }
}
