import 'dart:async';
import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/order_entities.dart';
import '../../domain/use_cases/order_workspace_use_cases.dart';
import 'order_controller.dart';

/// Columns of the takeaway board, in the order an order moves through them.
enum TakeawayStage {
  waiting('Chờ xác nhận', {OrderStatus.open}),
  cooking('Đang làm', {OrderStatus.confirmed, OrderStatus.preparing}),
  handover('Chờ giao / thanh toán', {OrderStatus.ready, OrderStatus.served});

  const TakeawayStage(this.label, this.statuses);
  final String label;
  final Set<OrderStatus> statuses;
}

/// Active takeaway orders, alive while the board or the Gọi món card shows
/// them. Reloads on order events; the board adds a slow poll in case realtime
/// drops. Each successful load also refreshes the sidebar count.
class TakeawayOrdersController extends OrderController {
  TakeawayOrdersController({
    required super.session,
    required super.events,
    super.onAccessDenied,
    required this.get,
    this.onCount,
  }) {
    events.addListener(_event);
  }
  static const pollInterval = Duration(seconds: 30);
  final GetActiveTakeawayOrders get;
  final void Function(int count)? onCount;
  List<OrderSummary> rows = const [];
  Failure? failure;
  bool loading = false, hasLoaded = false;
  int _revision = 0, _visible = 0;
  Future<void>? _reading;
  bool _reloadRequested = false;
  Timer? _poll;

  int get activeCount => rows.length;
  List<OrderSummary> stage(TakeawayStage stage) =>
      rows.where((row) => stage.statuses.contains(row.status)).toList();

  void _event() {
    if (_revision == events.revision) return;
    _revision = events.revision;
    // Remote hints carry no service type and may merge several orders, so any
    // of them reloads. A local change to a dine-in session cannot be takeaway.
    if (events.remote == null && events.sessionId != null) return;
    unawaited(load());
  }

  /// Screens showing the board call this so polling runs only while visible.
  void setVisible(bool visible) {
    _visible += visible ? 1 : -1;
    if (_visible > 0 && current) {
      _poll ??= Timer.periodic(pollInterval, (_) => unawaited(load()));
    } else {
      _visible = 0;
      _poll?.cancel();
      _poll = null;
    }
  }

  Future<void> load() {
    if (_reading != null) {
      _reloadRequested = true;
      return _reading!;
    }
    final future = _readLoop().whenComplete(() => _reading = null);
    _reading = future;
    return future;
  }

  Future<void> _readLoop() async {
    do {
      _reloadRequested = false;
      await _load();
    } while (_reloadRequested && current && can('ORDER_VIEW'));
  }

  Future<void> _load() async {
    if (!can('ORDER_VIEW')) return;
    loading = true;
    failure = null;
    changed();
    final result = await invoke(
      'ORDER_VIEW',
      () => get(isCurrent: () => current),
    );
    if (!current) return;
    switch (result) {
      case Success(value: final value):
        rows = value;
        hasLoaded = true;
        onCount?.call(value.length);
      case Error(failure: final f):
        failure = f;
    }
    loading = false;
    changed();
  }

  @override
  void dispose() {
    _poll?.cancel();
    events.removeListener(_event);
    super.dispose();
  }
}
