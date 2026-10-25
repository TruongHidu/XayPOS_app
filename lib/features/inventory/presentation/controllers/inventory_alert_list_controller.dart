import 'dart:async';
import '../../../../core/auth/access_policy.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/inventory_alert.dart';
import '../../domain/entities/inventory_alert_query.dart';
import '../../domain/use_cases/inventory_alert_use_cases.dart';
import 'inventory_controller.dart';
import 'inventory_events.dart';

class InventoryAlertListController extends InventoryController {
  InventoryAlertListController({
    required super.session,
    required super.events,
    super.onAccessDenied,
    required this.get,
  }) {
    events.addListener(_event);
  }
  final GetInventoryAlerts get;
  InventoryAlertQuery query = const InventoryAlertQuery();
  List<InventoryAlert> rows = const [];
  int totalElements = 0, totalPages = 0, _generation = 0, _revision = 0;
  bool loading = false, hasLoaded = false, _scheduled = false;
  bool _refreshPending = false;
  Failure? failure;
  Timer? _debounce;
  bool get allowed => current && AccessPolicy.canViewInventoryAlerts(session());
  void _event() {
    _scheduleRefresh();
    if (_revision == events.revision) return;
    _revision = events.revision;
    final change = events.change;
    if (!allowed ||
        change == null ||
        !const {
          InventoryChangeKind.alert,
          InventoryChangeKind.alertSync,
          InventoryChangeKind.balance,
          InventoryChangeKind.orderStock,
          InventoryChangeKind.warehouse,
        }.contains(change.kind) ||
        query.warehouseId != null &&
            change.warehouseId != null &&
            query.warehouseId != change.warehouseId ||
        query.ingredientId != null &&
            change.ingredientId != null &&
            query.ingredientId != change.ingredientId) {
      return;
    }
    _refreshPending = true;
    _scheduleRefresh();
  }

  void _scheduleRefresh() {
    if (!_refreshPending || _scheduled || loading || !allowed) return;
    _scheduled = true;
    Future.microtask(() {
      _scheduled = false;
      if (_refreshPending && allowed && !loading) unawaited(load());
    });
  }

  void search(String value) {
    _debounce?.cancel();
    ++_generation;
    query = query.copyWith(q: value, page: 0);
    changed();
    _debounce = Timer(const Duration(milliseconds: 350), load);
  }

  void filter(InventoryAlertQuery value) {
    _debounce?.cancel();
    ++_generation;
    query = value.copyWith(page: 0);
    unawaited(load());
  }

  void page(int value) {
    if (value < 0 || value >= totalPages && value != 0) return;
    query = query.copyWith(page: value);
    unawaited(load());
  }

  Future<void> load() async {
    if (!allowed) return;
    _refreshPending = false;
    _debounce?.cancel();
    final generation = ++_generation, q = query;
    if (!q.valid) {
      loading = false;
      failure = InventoryController.invalid({
        'q':
            'Bộ lọc chưa hợp lệ. Từ khóa tối đa 100 ký tự; thời gian bắt đầu phải trước kết thúc.',
      });
      changed();
      return;
    }
    loading = true;
    failure = null;
    changed();
    final result = await read('alerts', () => get(q));
    if (!allowed || generation != _generation) return;
    switch (result) {
      case Success(value: final data):
        if (q.page > 0 && data.content.isEmpty && data.totalPages <= q.page) {
          query = q.copyWith(
            page: data.totalPages == 0 ? 0 : data.totalPages - 1,
          );
          await load();
          return;
        }
        rows = data.content;
        totalElements = data.totalElements;
        totalPages = data.totalPages;
        hasLoaded = true;
      case Error(failure: final error):
        failure = error;
    }
    loading = false;
    changed();
    _scheduleRefresh();
  }

  @override
  void dispose() {
    ++_generation;
    _debounce?.cancel();
    events.removeListener(_event);
    super.dispose();
  }
}
