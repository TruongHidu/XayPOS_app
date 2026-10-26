import 'dart:async';
import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import '../../../order/domain/entities/order_entities.dart';
import '../../domain/entities/kitchen_queue.dart';
import '../../domain/use_cases/kitchen_use_cases.dart';
import 'kitchen_controller.dart';

enum KitchenViewMode { items, orders }

class KitchenDisplayController extends KitchenController {
  KitchenDisplayController({
    required super.session,
    super.onAccessDenied,
    required this.getQueue,
    this.pollInterval = const Duration(seconds: 12),
    this.readBlocked,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;
  final GetKitchenQueue getQueue;
  final Duration pollInterval;
  final bool Function()? readBlocked;
  bool _socketConnected = false;
  void setRealtimeConnected(bool value) {
    if (_socketConnected == value) return;
    _socketConnected = value;
    _schedulePoll();
  }

  final DateTime Function() clock;
  final Map<String, KitchenQueueItem> _items = {};
  final Map<String, int> _minimumVersions = {};
  final Map<String, OrderStatus> orderStatuses = {};
  final Map<OrderItemStatus, Failure> failures = {};
  final Set<String> inconsistentOrders = {};
  KitchenViewMode mode = KitchenViewMode.items;
  OrderItemStatus? filter;
  String search = '';
  bool loading = false, complete = false, isPolling = false;
  DateTime? lastUpdated;
  int loadedPages = 0, _generation = 0, _backoff = 0;
  Future<void>? _reading;
  bool _refreshRequested = false, _visible = false, _foreground = true;
  Timer? _poll, _debounce;

  List<KitchenQueueItem> get items {
    if (!current) return [];
    return _items.values.toList()..sort((a, b) {
      final time = a.queuedAt.compareTo(b.queuedAt);
      return time != 0 ? time : a.key.compareTo(b.key);
    });
  }

  List<KitchenQueueItem> get visibleItems {
    final q = search.toLowerCase();
    return items
        .where(
          (item) =>
              (filter == null || item.itemStatus == filter) &&
              (q.isEmpty ||
                  '${item.itemName} ${item.orderCode} ${item.tableName ?? ''} ${item.tableCode ?? ''}'
                      .toLowerCase()
                      .contains(q)),
        )
        .toList();
  }

  Map<String, List<KitchenQueueItem>> get visibleOrders {
    final ids = visibleItems.map((item) => item.orderId).toSet();
    final result = <String, List<KitchenQueueItem>>{};
    for (final item in items) {
      if (ids.contains(item.orderId)) (result[item.orderId] ??= []).add(item);
    }
    return result;
  }

  List<KitchenQueueItem> forOrder(String id) =>
      items.where((item) => item.orderId == id).toList();
  KitchenQueueItem? find(String key) => _items[key];
  bool orderComplete(String id) => complete && !inconsistentOrders.contains(id);
  void setMode(KitchenViewMode value) {
    mode = value;
    changed();
  }

  void setFilter(OrderItemStatus? value) {
    filter = value;
    changed();
  }

  void setSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      search = value.trim();
      changed();
    });
  }

  void setVisible(bool value) {
    if (_visible == value) return;
    _visible = value;
    _poll?.cancel();
    if (value && _foreground) unawaited(refresh());
  }

  void setForeground(bool value) {
    if (_foreground == value) return;
    _foreground = value;
    _poll?.cancel();
    if (value && _visible) unawaited(refresh());
  }

  void _schedulePoll() {
    _poll?.cancel();
    if (!current || !_visible || !_foreground || !can('KITCHEN_VIEW')) return;
    _poll = Timer(
      (_socketConnected ? const Duration(seconds: 60) : pollInterval) *
          (1 << _backoff),
      () => unawaited(refresh(silent: true)),
    );
  }

  Future<void> refresh({bool silent = false}) {
    if (!can('KITCHEN_VIEW')) return Future.value();
    if (readBlocked?.call() == true) {
      _refreshRequested = true;
      return Future.value();
    }
    if (_reading != null) {
      if (_readingGeneration != _generation) _refreshRequested = true;
      return _reading!;
    }
    final future = _readLoop(silent: silent).whenComplete(() {
      _reading = null;
      _schedulePoll();
    });
    _reading = future;
    return future;
  }

  int _readingGeneration = 0;
  Future<void> _readLoop({bool silent = false}) async {
    do {
      _refreshRequested = false;
      _readingGeneration = _generation + 1;
      await _load(silent: silent);
    } while (_refreshRequested &&
        can('KITCHEN_VIEW') &&
        readBlocked?.call() != true);
  }

  /// Any reads already running must not overwrite a subsequent POST response.
  void invalidateReads() {
    ++_generation;
    complete = false;
    changed();
  }

  void eventRefresh() {
    invalidateReads();
    _refreshRequested = true;
    if (_visible && _foreground) unawaited(refresh(silent: true));
  }

  void resumeQueuedRefresh() {
    if (_refreshRequested &&
        _visible &&
        _foreground &&
        readBlocked?.call() != true) {
      unawaited(refresh(silent: true));
    }
  }

  Future<void> _load({bool silent = false}) async {
    final generation = ++_generation;
    _poll?.cancel();
    final background = silent && _items.isNotEmpty;
    if (!background) {
      loading = true;
      complete = false;
    } else {
      isPolling = true;
    }
    loadedPages = 0;
    failures.clear();
    final streams = <OrderItemStatus, List<KitchenQueueItem>>{};
    changed();
    await Future.wait(
      kitchenStatuses.map((status) async {
        final rows = <KitchenQueueItem>[];
        var page = 0;
        while (current && generation == _generation) {
          final result = await getQueue(
            KitchenQueueQuery(status: status, page: page),
          );
          if (!current || generation != _generation) return;
          if (result case Error(failure: final failure)) {
            failures[status] = failure;
            await report(failure);
            changed();
            return;
          }
          final value = (result as Success<KitchenQueuePage>).value;
          if (value.page != page ||
              value.content.any((item) => item.itemStatus != status)) {
            failures[status] = const Failure(
              type: FailureType.internal,
              code: 'INVALID_KITCHEN_PAGE',
              message:
                  'Hàng đợi bếp trả về trang hoặc trạng thái không hợp lệ.',
            );
            changed();
            return;
          }
          rows.addAll(value.content);
          streams[status] = rows;
          ++loadedPages;
          if (_items.isEmpty) {
            _merge(streams, finished: false);
            changed();
          }
          if (page + 1 >= value.totalPages) return;
          ++page;
        }
      }),
    );
    if (!current || generation != _generation) {
      if (current) {
        loading = false;
        isPolling = false;
        changed();
      }
      return;
    }
    _merge(streams, finished: true);
    loading = false;
    isPolling = false;
    complete = failures.isEmpty && streams.length == kitchenStatuses.length;
    if (complete) {
      lastUpdated = clock();
      _backoff = 0;
    } else {
      _backoff = (_backoff + 1).clamp(0, 3);
    }
    changed();
  }

  void _merge(
    Map<OrderItemStatus, List<KitchenQueueItem>> streams, {
    required bool finished,
  }) {
    final next = <String, KitchenQueueItem>{};
    final versions = <String, Set<int>>{};
    for (final item in streams.values.expand((v) => v)) {
      (versions[item.orderId] ??= {}).add(item.orderVersion);
      if (item.orderVersion < (_minimumVersions[item.orderId] ?? -1)) continue;
      final previous = next[item.key];
      if (previous == null ||
          item.orderVersion > previous.orderVersion ||
          item.orderVersion == previous.orderVersion &&
              item.itemStatus.index > previous.itemStatus.index) {
        next[item.key] = item;
      }
    }
    inconsistentOrders.clear();
    for (final e in versions.entries) {
      if (e.value.length > 1 ||
          e.value.any((v) => v < (_minimumVersions[e.key] ?? -1))) {
        inconsistentOrders.add(e.key);
      }
    }
    if (!finished || failures.isNotEmpty) {
      for (final old in _items.values) {
        next.putIfAbsent(old.key, () => old);
      }
    } else {
      for (final old in _items.values) {
        if (inconsistentOrders.contains(old.orderId)) {
          next.putIfAbsent(old.key, () => old);
        }
      }
    }
    // A higher-version mutation/queue always wins over an old row or partial refresh.
    for (final old in _items.values) {
      final incoming = next[old.key];
      if (incoming != null && incoming.orderVersion < old.orderVersion) {
        next[old.key] = old;
      }
    }
    _items
      ..clear()
      ..addAll(next);
    for (final e in versions.entries) {
      final max = e.value.reduce((a, b) => a > b ? a : b);
      if (max > (_minimumVersions[e.key] ?? -1)) _minimumVersions[e.key] = max;
    }
    // A queue has no root status; never retain an older READY claim after append.
    orderStatuses.removeWhere(
      (id, _) =>
          versions[id]?.any((v) => v > (_statusVersions[id] ?? -1)) == true,
    );
  }

  final Map<String, int> _statusVersions = {};

  void applyOrder(OrderDetail order) {
    if (!current || order.version < (_minimumVersions[order.id] ?? -1)) return;
    final source = forOrder(order.id);
    _minimumVersions[order.id] = order.version;
    orderStatuses[order.id] = order.summary.status;
    _statusVersions[order.id] = order.version;
    _items.removeWhere((_, item) => item.orderId == order.id);
    if (source.isNotEmpty &&
        !const {
          OrderStatus.completed,
          OrderStatus.cancelled,
          OrderStatus.open,
        }.contains(order.summary.status)) {
      for (final line in order.items) {
        if (!kitchenStatuses.contains(line.status)) continue;
        final origin =
            source.where((row) => row.orderItemId == line.id).firstOrNull ??
            source.first;
        final row = origin.fromOrder(order, line);
        _items[row.key] = row;
      }
    }
    inconsistentOrders.remove(order.id);
    changed();
  }

  @override
  void dispose() {
    ++_generation;
    _poll?.cancel();
    _debounce?.cancel();
    super.dispose();
  }
}
