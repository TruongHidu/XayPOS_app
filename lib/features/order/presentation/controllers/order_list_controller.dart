import 'dart:async';
import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/order_entities.dart';
import '../../domain/entities/order_inputs.dart';
import '../../domain/use_cases/order_use_cases.dart';
import 'order_controller.dart';

class OrderListController extends OrderController {
  OrderListController({
    required super.session,
    required super.events,
    super.onAccessDenied,
    required this.get,
    this.query = const OrderQuery(),
  }) {
    events.addListener(_event);
  }
  final GetOrders get;
  OrderQuery query;
  OrderPage? page;
  Failure? failure;
  bool loading = false;
  int _generation = 0, _revision = 0;
  Future<void>? _reading;
  bool _reloadRequested = false;
  Timer? _debounce;
  void _event() {
    if (_revision == events.revision) return;
    _revision = events.revision;
    if (query.tableSessionId == null ||
        events.affectsSession(query.tableSessionId)) {
      ++_generation;
      _reloadRequested = true;
      unawaited(load());
    }
  }

  void search(String q) {
    _debounce?.cancel();
    ++_generation;
    query = query.copyWith(q: q, page: 0);
    page = null;
    loading = false;
    changed();
    _debounce = Timer(const Duration(milliseconds: 350), load);
  }

  void filter({
    OrderStatus? status,
    ServiceType? type,
    String sortBy = 'createdAt',
    String direction = 'desc',
  }) {
    _debounce?.cancel();
    ++_generation;
    page = null;
    query = query.copyWith(
      status: () => status,
      serviceType: () => type,
      page: 0,
      sortBy: sortBy,
      direction: direction,
    );
    unawaited(load());
  }

  Future<void> go(int index) {
    query = query.copyWith(page: index);
    return load();
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
    if (!query.valid) {
      loading = false;
      failure = OrderController.invalid({'query': 'Bộ lọc không hợp lệ.'});
      changed();
      return;
    }
    final g = ++_generation;
    loading = true;
    failure = null;
    changed();
    final response = await invoke('ORDER_VIEW', () => get(query));
    if (!current || g != _generation) return;
    switch (response) {
      case Success(value: final value):
        page = value;
        if (query.page > 0 &&
            value.content.isEmpty &&
            query.page >= value.totalPages) {
          query = query.copyWith(
            page: value.totalPages > 0 ? value.totalPages - 1 : 0,
          );
          _reloadRequested = true;
        }
      case Error(failure: final f):
        failure = f;
    }
    loading = false;
    changed();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    ++_generation;
    page = null;
    events.removeListener(_event);
    super.dispose();
  }
}
