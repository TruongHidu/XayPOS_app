import 'dart:async';
import '../../../../core/realtime/realtime_connection_service.dart';
import '../../../../core/realtime/realtime_envelope.dart';
import '../../../../core/realtime/realtime_event_window.dart';
import '../../data/dto/order_realtime_payload.dart';
import 'order_invalidation.dart';

/// One cache per channel: order/kitchen fan-out must reach both consumers.
class OrderRealtimeCoordinator {
  OrderRealtimeCoordinator({
    required this.invalidate,
    this.id = 'orders',
    this.debounce = const Duration(milliseconds: 400),
    this.capacity = 512,
    this.onNewItems,
    this.isCurrent,
    DateTime Function()? now,
  }) : window = RealtimeEventWindow(capacity: capacity, now: now);
  final String id;
  final void Function(OrderInvalidation) invalidate;
  final void Function(int)? onNewItems;
  final bool Function()? isCurrent;
  bool get _live => !_disposed && _active && (isCurrent?.call() ?? true);
  final Duration debounce;
  final int capacity;
  final RealtimeEventWindow window;
  final Set<String> _orders = {}, _sessions = {}, _freshEvents = {};
  Timer? _timer;
  bool _all = false, _active = true, _disposed = false;
  RealtimeChannel get channel => RealtimeChannel(
    id: id,
    destination: '/user/queue/$id',
    message: receive,
    resync: resync,
  );
  void receive(String body) {
    if (!_live) return;
    final event = RealtimeEnvelope.parse(body);
    if (event == null) return;
    final payload = OrderRealtimePayload.parse(event);
    if (payload == null || !window.accept(event.eventId)) return;
    if (!_all) {
      _orders.add(event.resourceId);
      if (payload.sessionId != null) _sessions.add(payload.sessionId!);
      if (_orders.length + _sessions.length > capacity) {
        _all = true;
        _orders.clear();
        _sessions.clear();
      }
    }
    if (payload.newKitchenItemIds.isNotEmpty &&
        _freshEvents.length < capacity) {
      _freshEvents.add(event.eventId);
    }
    _schedule();
  }

  void resync() {
    if (!_live) return;
    _all = true;
    // Snapshot recovery is deliberately silent.
    _freshEvents.clear();
    _schedule();
  }

  void setActive(bool value) {
    if (_disposed || value == _active) return;
    _active = value;
    if (!value) cancelPending();
  }

  void cancelPending() {
    _timer?.cancel();
    _timer = null;
    _orders.clear();
    _sessions.clear();
    _freshEvents.clear();
    _all = false;
  }

  void _schedule() {
    if (_timer != null || !_live) return;
    _timer = Timer(debounce, () {
      _timer = null;
      if (!_live) {
        cancelPending();
        return;
      }
      final hint = OrderInvalidation(
        orderIds: _orders,
        sessionIds: _sessions,
        all: _all,
      );
      final fresh = _freshEvents.length;
      _orders.clear();
      _sessions.clear();
      _freshEvents.clear();
      _all = false;
      invalidate(hint);
      if (_live && fresh > 0) onNewItems?.call(fresh);
    });
  }

  void dispose() {
    _disposed = true;
    cancelPending();
    window.clear();
  }
}
