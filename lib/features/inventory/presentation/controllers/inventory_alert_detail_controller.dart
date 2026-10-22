import 'dart:async';
import '../../../../core/auth/access_policy.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/inventory_alert.dart';
import '../../domain/entities/inventory_alert_query.dart';
import '../../domain/use_cases/inventory_alert_use_cases.dart';
import 'inventory_controller.dart';
import 'inventory_events.dart';

class InventoryAlertDetailController extends InventoryController {
  InventoryAlertDetailController({
    required super.session,
    required super.events,
    super.onAccessDenied,
    required this.id,
    required this.get,
    required this.ack,
  }) {
    events.addListener(_event);
  }
  final String id;
  final GetInventoryAlert get;
  final AcknowledgeInventoryAlert ack;
  InventoryAlert? _value;
  InventoryAlert? get value => allowed ? _value : null;
  Failure? failure;
  bool loading = false,
      hasLoaded = false,
      _scheduled = false,
      _applying = false;
  int _generation = 0, _revision = 0;
  String get key => InventoryEvents.alertKey(id);
  bool get allowed => current && AccessPolicy.canViewInventoryAlerts(session());
  bool get busy => events.pending(key);
  bool get requiresReview => events.verification(key) != null;
  bool get canAcknowledge =>
      allowed &&
      AccessPolicy.canAcknowledgeInventoryAlert(session()) &&
      _value?.status == InventoryAlertStatus.open &&
      !busy &&
      !loading &&
      !requiresReview;
  void _event() {
    if (_revision == events.revision) return;
    _revision = events.revision;
    final change = events.change, old = _value;
    if (_applying ||
        !allowed ||
        change == null ||
        change.kind == InventoryChangeKind.alert && change.alertId != id ||
        !const {
          InventoryChangeKind.alert,
          InventoryChangeKind.balance,
          InventoryChangeKind.orderStock,
          InventoryChangeKind.warehouse,
        }.contains(change.kind) ||
        old != null &&
            change.warehouseId != null &&
            change.warehouseId != old.warehouseId ||
        old != null &&
            change.ingredientId != null &&
            change.ingredientId != old.ingredientId) {
      return;
    }
    ++_generation;
    if (_scheduled) return;
    _scheduled = true;
    Future.microtask(() {
      _scheduled = false;
      if (allowed && !busy) unawaited(load());
    });
  }

  Future<void> load() async {
    if (!allowed || busy) return;
    final generation = ++_generation;
    loading = true;
    failure = null;
    changed();
    final result = await read('alert:$id', () => get(id));
    if (!allowed || generation != _generation) return;
    switch (result) {
      case Success(value: final row):
        if (row.id != id) {
          failure = InventoryController.invalidResponse;
          break;
        }
        _value = row;
        hasLoaded = true;
        events.resolve(key);
      case Error(failure: final error):
        failure = error;
        if (error.type == FailureType.notFound) {
          _value = null;
          events.resolve(key);
        }
    }
    loading = false;
    changed();
  }

  Future<Result<InventoryAlert>> acknowledge() async {
    if (!canAcknowledge) {
      return Error(
        events.verification(key) ??
            (busy ? InventoryController.busy : InventoryController.denied),
      );
    }
    final row = _value!;
    ++_generation;
    failure = null;
    final result = await mutate(
      key,
      'INVENTORY_ALERT_ACKNOWLEDGE',
      () => ack(id, AcknowledgeInventoryAlertInput(row.version)),
      applied: (fresh) {
        if (!allowed || !AccessPolicy.canAcknowledgeInventoryAlert(session())) {
          return;
        }
        if (fresh.id != id ||
            fresh.status != InventoryAlertStatus.acknowledged) {
          events.requireVerification(key, InventoryController.invalidResponse);
          return;
        }
        _value = fresh;
        _applying = true;
        events.emit(
          InventoryChange(
            InventoryChangeKind.alert,
            fresh.warehouseId,
            ingredientId: fresh.ingredientId,
            alertId: id,
          ),
        );
        _applying = false;
      },
    );
    if (!allowed) return const Error(InventoryController.denied);
    if (result case Error(failure: final error)) {
      failure = error;
      if (InventoryController.unknown(error) ||
          error.type == FailureType.conflict) {
        events.requireVerification(key, error);
      }
    }
    changed();
    return result;
  }

  @override
  void dispose() {
    ++_generation;
    events.removeListener(_event);
    super.dispose();
  }
}
