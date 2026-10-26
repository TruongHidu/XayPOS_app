import 'dart:async';

import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/inventory_queries.dart';
import '../../domain/use_cases/inventory_use_cases.dart';
import 'inventory_controller.dart';
import 'inventory_events.dart';

/// Global low-stock row count, independent of list filters and pagination.
class InventoryLowStockCountController extends InventoryController {
  InventoryLowStockCountController({
    required super.session,
    required super.events,
    super.onAccessDenied,
    required this.get,
    bool foreground = true,
  }) : _foreground = foreground,
       _revision = events.revision {
    events.addListener(_event);
  }

  final GetLowStockBalances get;
  int? _count;
  int? get count => canLowStock ? _count : null;
  Failure? failure;
  bool loading = false;
  bool _foreground, _again = false, _scheduled = false;
  int _revision, _generation = 0;
  Future<void>? _pending;

  void _event() {
    if (_revision == events.revision) return;
    _revision = events.revision;
    if (!const {
      InventoryChangeKind.warehouse,
      InventoryChangeKind.balance,
      InventoryChangeKind.orderStock,
      InventoryChangeKind.alertSync,
    }.contains(events.change?.kind)) {
      return;
    }
    if (!canLowStock || !_foreground) return;
    if (_pending != null) {
      ++_generation;
      _again = true;
      return;
    }
    if (_scheduled) return;
    _scheduled = true;
    Future.microtask(() {
      _scheduled = false;
      if (canLowStock && _foreground) unawaited(load());
    });
  }

  void setForeground(bool value) {
    if (_foreground == value) return;
    _foreground = value;
    if (value) {
      unawaited(load());
    } else {
      ++_generation;
      _again = false;
    }
  }

  Future<void> load() {
    if (!canLowStock || !_foreground) return Future.value();
    ++_generation;
    final pending = _pending;
    if (pending != null) {
      _again = true;
      return pending;
    }
    final done = Completer<void>();
    _pending = done.future;
    unawaited(_load(done));
    return done.future;
  }

  Future<void> _load(Completer<void> done) async {
    try {
      do {
        _again = false;
        final generation = _generation;
        loading = true;
        failure = null;
        changed();
        try {
          final result = await read(
            'low-stock-count',
            () => get(
              const LowStockQuery(
                filters: InventoryBalanceQuery(size: 1, sortBy: 'quantity'),
              ),
            ),
            lowStock: true,
          );
          if (!canLowStock || !_foreground || generation != _generation) {
            continue;
          }
          switch (result) {
            case Success(value: final page):
              _count = page.totalElements;
            case Error(failure: final error):
              _count = null;
              failure = error;
          }
        } catch (_) {
          if (canLowStock && _foreground && generation == _generation) {
            _count = null;
            failure = InventoryController.invalidResponse;
          }
        }
      } while (_again && canLowStock && _foreground);
    } finally {
      _pending = null;
      loading = false;
      changed();
      done.complete();
    }
  }

  @override
  void dispose() {
    ++_generation;
    _again = false;
    _count = null;
    events.removeListener(_event);
    super.dispose();
  }
}
