import 'dart:async';
import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import '../../../order/presentation/controllers/order_controller.dart';
import '../../domain/entities/qr_request.dart';
import '../../domain/use_cases/qr_request_use_cases.dart';

class QrInboxController extends OrderController {
  QrInboxController({
    required super.session,
    required super.events,
    super.onAccessDenied,
    required this.getPending,
    this.pollInterval = const Duration(seconds: 12),
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;
  final GetPendingTableQrRequests getPending;
  final Duration pollInterval;
  final DateTime Function() clock;
  List<QrRequest> _rows = const [];
  List<QrRequest> get pending => !can('ORDER_VIEW')
      ? const []
      : _rows.where((row) => row.pendingAt(clock())).toList(growable: false);
  List<QrRequest> forTable(String id, String? sessionId) => pending
      .where(
        (row) =>
            row.tableId == id &&
            (row.observedSessionId == null ||
                row.observedSessionId == sessionId),
      )
      .toList();
  bool loading = false;
  Failure? failure;
  DateTime? lastUpdated, retryAt;
  int arrivals = 0, _generation = 0, _backoff = 0;
  final Set<Object> _visible = {};
  bool _foreground = true, _initialized = false;
  final Set<String> _seen = {};
  Timer? _timer;
  Future<void>? _reading;
  bool _reloadRequested = false;
  bool get coolingDown => retryAt?.isAfter(clock()) == true;

  void setVisible(Object owner, bool value) {
    final changed = value ? _visible.add(owner) : _visible.remove(owner);
    if (!changed) return;
    _timer?.cancel();
    if (value && _visible.isNotEmpty && _foreground) {
      unawaited(refresh());
    } else {
      _schedule();
    }
  }

  void setForeground(bool value) {
    if (_foreground == value) return;
    _foreground = value;
    _timer?.cancel();
    if (value && _visible.isNotEmpty) unawaited(refresh());
  }

  void invalidate() {
    ++_generation;
    if (_reading != null) _reloadRequested = true;
    if (_visible.isNotEmpty && _foreground) unawaited(refresh());
  }

  void resolve(String id) {
    _rows = List.unmodifiable(_rows.where((row) => row.id != id));
    changed();
    invalidate();
  }

  Future<void> refresh() {
    if (!can('ORDER_VIEW')) return Future.value();
    if (coolingDown) {
      _schedule();
      return Future.value();
    }
    if (_reading != null) return _reading!;
    final future = _readLoop().whenComplete(() {
      _reading = null;
      _schedule();
    });
    _reading = future;
    return future;
  }

  Future<void> _readLoop() async {
    do {
      _reloadRequested = false;
      final generation = ++_generation;
      loading = true;
      changed();
      final result = await getPending(
        isCurrent: () =>
            current && generation == _generation && can('ORDER_VIEW'),
      );
      if (!current || !can('ORDER_VIEW')) return;
      if (generation != _generation) continue;
      switch (result) {
        case Success(value: final rows):
          final fresh = rows
              .where((r) => r.pendingAt(clock()))
              .map((r) => r.id)
              .toSet();
          arrivals = _initialized ? fresh.difference(_seen).length : 0;
          _seen.addAll(fresh);
          _initialized = true;
          _rows = rows;
          lastUpdated = clock();
          failure = null;
          retryAt = null;
          _backoff = 0;
        case Error(failure: final error):
          failure = error;
          arrivals = 0;
          _backoff = (_backoff + 1).clamp(0, 3);
          if (error is QrCooldownFailure) {
            retryAt = clock().add(error.retryAfter);
          }
          await report(error);
          if (!current) return;
      }
      loading = false;
      changed();
    } while (_reloadRequested && current && !coolingDown);
    loading = false;
  }

  void _schedule() {
    _timer?.cancel();
    if (!can('ORDER_VIEW') || _visible.isEmpty || !_foreground) return;
    final wait = coolingDown
        ? retryAt!.difference(clock())
        : pollInterval * (1 << _backoff);
    _timer = Timer(wait, () => unawaited(refresh()));
  }

  @override
  void dispose() {
    ++_generation;
    _timer?.cancel();
    super.dispose();
  }
}
