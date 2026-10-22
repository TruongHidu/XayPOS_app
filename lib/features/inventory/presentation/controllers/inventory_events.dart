import 'package:flutter/foundation.dart';
import '../../../../core/errors/failure.dart';
import '../../domain/entities/inventory_entities.dart';

enum InventoryChangeKind {
  warehouse,
  balance,
  document,
  orderStock,
  alert,
  audit,
}

class InventoryChange {
  const InventoryChange(
    this.kind,
    this.warehouseId, {
    this.ingredientId,
    this.warehouse,
    this.deleted = false,
    this.documentId,
    this.orderId,
    this.orderItemId,
    this.alertId,
    this.auditId,
  });
  final InventoryChangeKind kind;
  final String? warehouseId;
  final String? orderId, orderItemId;
  final String? alertId, auditId;
  final String? ingredientId;
  final Warehouse? warehouse;
  final bool deleted;
  final String? documentId;
}

/// Scoped coordination; phase 2 can emit balance changes after confirming a document.
class InventoryEvents extends ChangeNotifier {
  int revision = 0;
  InventoryChange? change;
  final Set<String> _pending = {};
  final Map<String, Failure> _review = {};
  bool pending(String key) => _pending.contains(key);
  Failure? verification(String key) => _review[key];
  bool lock(String key) {
    if (!_pending.add(key)) return false;
    notifyListeners();
    return true;
  }

  void unlock(String key) {
    if (_pending.remove(key)) notifyListeners();
  }

  void requireVerification(String key, Failure failure) {
    _review[key] = failure;
    notifyListeners();
  }

  void resolve(String key) {
    if (_review.remove(key) != null) notifyListeners();
  }

  void emit(InventoryChange value) {
    change = value;
    revision++;
    notifyListeners();
  }

  static String warehouseKey(String id) => 'warehouse:$id';
  static String balanceKey(String w, String i) => 'balance:$w:$i';
  static const createKey = 'warehouse:create';
  static String documentKey(String id) => 'stock-document:$id';
  static const stockCreateKey = 'stock-document:create';
  static String alertKey(String id) => 'inventory-alert:$id';
  static String auditKey(String id) => 'stock-audit:$id';
  static const stockAuditCreateKey = 'stock-audit:create';
}
