import 'dart:async';
import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/table_entities.dart';
import '../../domain/use_cases/restaurant_table_use_cases.dart';
import 'table_controller.dart';
import 'table_events.dart';

class TableDetailController extends TableController {
  TableDetailController({
    required super.session,
    required super.events,
    super.onAccessDenied,
    required this.id,
    required this.get,
  }) {
    _eventRevision = events.revision;
    events.addListener(_event);
  }
  final String id;
  final DetailRestaurantTable get;
  RestaurantTable? value;
  Failure? failure;
  bool loading = false;
  int _generation = 0;
  int _eventRevision = 0;
  void _event() {
    if (_eventRevision == events.revision) return;
    _eventRevision = events.revision;
    if (events.change?.kind == TableChangeKind.refresh ||
        events.change?.kind == TableChangeKind.area ||
        events.change?.id == id ||
        events.change?.relatedTableIds.contains(id) == true) {
      unawaited(load());
    }
  }

  Future<void> load() async {
    final generation = ++_generation;
    loading = true;
    failure = null;
    changed();
    final result = await read('detail', () => get(id));
    if (!isCurrent || generation != _generation) return;
    switch (result) {
      case Success(value: final v):
        value = v;
      case Error(failure: final f):
        failure = f;
        if (f.type == FailureType.notFound) value = null;
    }
    loading = false;
    changed();
  }

  @override
  void dispose() {
    events.removeListener(_event);
    value = null;
    super.dispose();
  }
}

class TableQrController extends TableController {
  TableQrController({
    required super.session,
    required super.events,
    super.onAccessDenied,
    required this.id,
    required this.get,
    required this.rotate,
  }) {
    _eventRevision = events.revision;
    events.addListener(_event);
  }
  final String id;
  final QrRestaurantTable get;
  final RotateQrRestaurantTable rotate;
  TableQrPayload? value;
  Failure? failure;
  bool loading = false;
  int _generation = 0;
  int _eventRevision = 0;
  bool _rotating = false;
  void _event() {
    if (_eventRevision == events.revision) return;
    _eventRevision = events.revision;
    if (!_rotating &&
        events.change?.id == id &&
        events.change?.kind != TableChangeKind.session) {
      value = null;
      unawaited(load());
    }
  }

  Future<void> load() async {
    final generation = ++_generation;
    loading = true;
    failure = null;
    changed();
    final result = await read('qr', () => get(id), permission: 'TABLE_UPDATE');
    if (!isCurrent || generation != _generation) return;
    switch (result) {
      case Success(value: final v):
        value = v;
      case Error(failure: final f):
        failure = f;
        value = null;
    }
    loading = false;
    changed();
  }

  Future<Result<TableQrPayload>> rotateCurrent(TableQrPayload baseline) async {
    // A GET started before rotation must not overwrite the returned new token.
    ++_generation;
    loading = false;
    _rotating = true;
    try {
      final result = await mutate(
        'table:$id',
        'TABLE_UPDATE',
        () => rotate(id, baseline.version),
        change: (v) => TableChange(TableChangeKind.qr, id),
      );
      if (isCurrent) {
        switch (result) {
          case Success(value: final v):
            value = v;
            failure = null;
          case Error(failure: final f):
            failure = f;
            if (f.isNetwork ||
                f.type == FailureType.notFound ||
                f.code == 'CONCURRENT_TABLE_UPDATE') {
              value = null;
            }
        }
        changed();
      }
      return result;
    } finally {
      _rotating = false;
    }
  }

  @override
  void dispose() {
    events.removeListener(_event);
    value = null;
    super.dispose();
  }
}
