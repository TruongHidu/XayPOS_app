import 'dart:async';
import '../../../../core/realtime/realtime_connection_service.dart';
import '../../../../core/realtime/realtime_envelope.dart';
import '../../../../core/realtime/realtime_event_window.dart';
import '../../data/dto/qr_realtime_payload.dart';
import 'qr_events.dart';

class QrRealtimeCoordinator {
  QrRealtimeCoordinator(
    this.events, {
    this.debounce = const Duration(milliseconds: 400),
    this.capacity = 512,
    this.onCreated,
    this.isCurrent,
    DateTime Function()? now,
  }) : window = RealtimeEventWindow(capacity: capacity, now: now);
  final QrEvents events;
  final Duration debounce;
  final int capacity;
  final void Function(int tables, int takeaway)? onCreated;
  final bool Function()? isCurrent;
  bool get _live => !_disposed && _active && (isCurrent?.call() ?? true);
  final RealtimeEventWindow window;
  final Set<String> _requests = {}, _tables = {}, _sessions = {};
  final Map<String, String> _fresh = {};
  Timer? _timer;
  bool _all = false, _active = true, _disposed = false;
  RealtimeChannel get channel => RealtimeChannel(
    id: 'qr-order-requests',
    destination: '/user/queue/qr-order-requests',
    message: receive,
    resync: resync,
  );
  void receive(String body) {
    if (!_live) return;
    final event = RealtimeEnvelope.parse(body);
    if (event == null) return;
    final payload = QrRealtimePayload.parse(event);
    if (payload == null || !window.accept(event.eventId)) return;
    if (!_all) {
      _requests.add(event.resourceId);
      if (payload.tableId != null) _tables.add(payload.tableId!);
      if (payload.observedSessionId != null) {
        _sessions.add(payload.observedSessionId!);
      }
      if (payload.approvedSessionId != null) {
        _sessions.add(payload.approvedSessionId!);
      }
      if (_requests.length + _tables.length + _sessions.length > capacity) {
        _all = true;
        _requests.clear();
        _tables.clear();
        _sessions.clear();
      }
    }
    if (payload.changeKind == 'CREATED') {
      if (_fresh.length < capacity) {
        _fresh[event.resourceId] = payload.entryType;
      }
    } else {
      _fresh.remove(event.resourceId);
    }
    _schedule();
  }

  void resync() {
    if (!_live) return;
    _all = true;
    _fresh.clear();
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
    _requests.clear();
    _tables.clear();
    _sessions.clear();
    _fresh.clear();
    _all = false;
  }

  void _schedule() {
    if (!_live || _timer != null) return;
    _timer = Timer(debounce, () {
      _timer = null;
      if (!_live) {
        cancelPending();
        return;
      }
      final hint = QrInvalidation(
        requestIds: _requests,
        tableIds: _tables,
        sessionIds: _sessions,
        all: _all,
      );
      final table = _fresh.values.where((v) => v == 'TABLE').length,
          takeaway = _fresh.values.where((v) => v == 'RESTAURANT').length;
      _requests.clear();
      _tables.clear();
      _sessions.clear();
      _fresh.clear();
      _all = false;
      events.emit(hint);
      if (_live && table + takeaway > 0) {
        onCreated?.call(table, takeaway);
      }
    });
  }

  void dispose() {
    _disposed = true;
    cancelPending();
    window.clear();
  }
}
