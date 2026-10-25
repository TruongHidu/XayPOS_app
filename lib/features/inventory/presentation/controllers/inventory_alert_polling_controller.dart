import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../../../../core/auth/access_policy.dart';
import '../../../../core/auth/app_session.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/inventory_alert.dart';
import '../../domain/entities/inventory_alert_query.dart';
import '../../domain/entities/inventory_entities.dart';
import '../../domain/use_cases/inventory_alert_use_cases.dart';
import 'inventory_alert_notice.dart';
import 'inventory_events.dart';

enum InventoryAlertPollingState { stopped, checking, active, error }

typedef InventoryAlertPollingNoticeListener =
    void Function(InventoryAlertNotice notice);

/// A read-only, scope-owned fallback for servers without a WebSocket endpoint.
/// Each foreground run starts with a silent baseline. REST remains authoritative.
class InventoryAlertPollingController extends ChangeNotifier {
  InventoryAlertPollingController({
    required this.get,
    required this.events,
    required this.session,
    this.onAccessDenied,
    this.interval = const Duration(seconds: 20),
  }) : assert(interval > Duration.zero),
       scope = AccessPolicy.inventoryScope(session()),
       _revision = events.revision {
    events.addListener(_event);
  }

  static const _pageSize = 100, _maxPages = 10, _localAckCapacity = 512;
  static const _invalidResponse = Failure(
    type: FailureType.internal,
    code: 'INVALID_INVENTORY_ALERT_POLL_RESPONSE',
    message: 'Chưa tải được cập nhật cảnh báo. Hệ thống sẽ thử lại.',
  );
  final GetInventoryAlerts get;
  final InventoryEvents events;
  final AppSession? Function() session;
  final Future<void> Function(Failure)? onAccessDenied;
  final Duration interval;
  final Object? scope;
  final Set<InventoryAlertPollingNoticeListener> _listeners = {};
  final LinkedHashMap<String, int> _localAcknowledgements = LinkedHashMap();
  Set<String> _headIds = {};
  String? _headTailId;
  DateTime? _headNewest;
  bool _baseline = false, _wholeFeedBaseline = false;
  bool _enabled = false, _foreground = true, _disposed = false;
  bool _running = false, _pending = false, _accessBlocked = false;
  int _generation = 0, _revision, _failures = 0;
  Timer? _timer, _debounce;

  InventoryAlertPollingState state = InventoryAlertPollingState.stopped;
  Failure? failure;

  bool get _current =>
      !_disposed &&
      scope == AccessPolicy.inventoryScope(session()) &&
      AccessPolicy.canViewInventoryAlerts(session());
  bool get _wanted => _current && _enabled && _foreground;
  bool _accepts(int generation) => _wanted && generation == _generation;

  void addNoticeListener(InventoryAlertPollingNoticeListener listener) {
    if (!_disposed) _listeners.add(listener);
  }

  void removeNoticeListener(InventoryAlertPollingNoticeListener listener) {
    _listeners.remove(listener);
  }

  void configure({
    required bool enabled,
    required bool foreground,
    bool notify = true,
  }) {
    if (_disposed) return;
    final changed = enabled != _enabled || foreground != _foreground;
    final wasEnabled = _enabled;
    _enabled = enabled;
    _foreground = foreground;
    if (!_wanted) {
      _halt(notify: notify);
      return;
    }
    if (!wasEnabled && enabled) _accessBlocked = false;
    if (changed) refresh();
  }

  /// Coalesces requests made while a page scan is still in flight.
  void refresh() {
    if (_disposed) return;
    if (!_wanted) {
      _halt();
      return;
    }
    if (_accessBlocked) return;
    _timer?.cancel();
    _timer = null;
    _debounce?.cancel();
    _debounce = null;
    if (_running) {
      _pending = true;
      return;
    }
    _pending = false;
    _running = true;
    final generation = ++_generation;
    state = InventoryAlertPollingState.checking;
    failure = null;
    notifyListeners();
    unawaited(_poll(generation));
  }

  void _halt({bool notify = true}) {
    ++_generation;
    _timer?.cancel();
    _timer = null;
    _debounce?.cancel();
    _debounce = null;
    _pending = false;
    _baseline = false;
    _wholeFeedBaseline = false;
    _headIds.clear();
    _headTailId = null;
    _headNewest = null;
    _localAcknowledgements.clear();
    _failures = 0;
    _accessBlocked = false;
    final changed =
        state != InventoryAlertPollingState.stopped || failure != null;
    state = InventoryAlertPollingState.stopped;
    failure = null;
    if (changed && notify && !_disposed) notifyListeners();
  }

  Future<void> _poll(int generation) async {
    try {
      if (!_accepts(generation)) return;
      InventoryPage<InventoryAlert>? head;
      final candidates = <String, InventoryAlert>{};
      var reachedBoundary = false, exhausted = false;
      for (var page = 0; page < _maxPages; page++) {
        final result = await get(
          InventoryAlertQuery(status: null, page: page, size: _pageSize),
        );
        if (!_accepts(generation)) return;
        if (result case Error(failure: final error)) {
          _failed(generation, error);
          return;
        }
        final data = (result as Success<InventoryPage<InventoryAlert>>).value;
        head ??= data;
        if (!_baseline) break;
        for (final alert in data.content) {
          if (!_wholeFeedBaseline && alert.id == _headTailId) {
            reachedBoundary = true;
            break;
          }
          if (!_headIds.contains(alert.id)) candidates[alert.id] = alert;
        }
        exhausted = data.content.isEmpty || page + 1 >= data.totalPages;
        if (reachedBoundary || exhausted) break;
      }
      if (!_accepts(generation) || head == null) return;

      final wasBaseline = _baseline;
      final previousNewest = _headNewest;
      final previousWholeFeed = _wholeFeedBaseline;
      final truncated = wasBaseline && !reachedBoundary && !exhausted;
      final newOpenIds = <String>{};
      if (wasBaseline) {
        for (final alert in candidates.values) {
          // Without a retained boundary, historical/tied rows are ambiguous.
          // A complete prior feed has no unseen historical tail.
          final confirmed =
              reachedBoundary ||
              previousWholeFeed ||
              previousNewest != null &&
                  alert.triggeredAt.isAfter(previousNewest);
          if (confirmed &&
              alert.status == InventoryAlertStatus.open &&
              alert.version > (_localAcknowledgements[alert.id] ?? -1)) {
            newOpenIds.add(alert.id);
          }
        }
      }

      // Commit only after every requested page succeeded. Keep at most one head.
      final latest = head.content.take(_pageSize).toList();
      _headIds = latest.map((alert) => alert.id).toSet();
      _headTailId = latest.isEmpty ? null : latest.last.id;
      _headNewest = latest.isEmpty
          ? null
          : latest
                .map((alert) => alert.triggeredAt)
                .reduce((a, b) => a.isAfter(b) ? a : b);
      _wholeFeedBaseline = head.totalPages <= 1;
      _baseline = true;
      _failures = 0;
      failure = null;
      state = InventoryAlertPollingState.active;
      notifyListeners();
      if (!_accepts(generation)) return;
      // Current balances can change without an alert version change.
      events.emit(const InventoryChange(InventoryChangeKind.alertSync, null));
      if (!_accepts(generation) || newOpenIds.isEmpty) return;
      final notice = InventoryAlertNotice(
        alertIds: newOpenIds,
        hasMore: truncated,
      );
      for (final listener in _listeners.toList()) {
        if (!_accepts(generation)) break;
        if (_listeners.contains(listener)) listener(notice);
      }
    } catch (_) {
      if (_accepts(generation)) _failed(generation, _invalidResponse);
    } finally {
      _running = false;
      if (!_disposed && !_wanted) {
        _halt();
      } else if (!_disposed && !_accessBlocked) {
        if (_pending) {
          refresh();
        } else if (generation == _generation) {
          final exponent = _failures == 0
              ? 0
              : (_failures > 5 ? 4 : _failures - 1);
          final multiplier = 1 << exponent;
          final delay = interval * multiplier;
          _timer = Timer(
            delay > const Duration(minutes: 5)
                ? const Duration(minutes: 5)
                : delay,
            refresh,
          );
        }
      }
    }
  }

  void _failed(int generation, Failure error) {
    if (!_accepts(generation)) return;
    _failures++;
    failure = error;
    state = InventoryAlertPollingState.error;
    _accessBlocked = const {
      FailureType.unauthorized,
      FailureType.invalidRefreshToken,
      FailureType.forbidden,
      FailureType.featureNotEntitled,
      FailureType.subscriptionNotActive,
      FailureType.restaurantInactive,
    }.contains(error.type);
    notifyListeners();
    if (_accessBlocked && _accepts(generation)) {
      unawaited(_reportAccessDenied(error));
    }
  }

  Future<void> _reportAccessDenied(Failure error) async {
    try {
      await onAccessDenied?.call(error);
    } catch (_) {
      // Authentication alone decides recovery/logout. Do not retry a denial.
    }
  }

  void _event() {
    if (_disposed || _revision == events.revision) return;
    _revision = events.revision;
    final change = events.change;
    if (change == null || change.kind == InventoryChangeKind.alertSync) return;
    if (change.kind == InventoryChangeKind.alert &&
        change.alertId != null &&
        change.resourceVersion != null) {
      final id = change.alertId!, version = change.resourceVersion!;
      _localAcknowledgements.remove(id);
      _localAcknowledgements[id] = version;
      while (_localAcknowledgements.length > _localAckCapacity) {
        _localAcknowledgements.remove(_localAcknowledgements.keys.first);
      }
    }
    if (!_wanted || _accessBlocked) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), refresh);
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    ++_generation;
    _timer?.cancel();
    _debounce?.cancel();
    events.removeListener(_event);
    _listeners.clear();
    _headIds.clear();
    _localAcknowledgements.clear();
    super.dispose();
  }
}
