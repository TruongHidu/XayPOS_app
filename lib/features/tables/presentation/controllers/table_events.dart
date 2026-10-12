import 'package:flutter/foundation.dart';
import '../../domain/entities/table_entities.dart';

enum TableChangeKind { area, table, session, qr }

class TableChange {
  const TableChange(
    this.kind,
    this.id, {
    this.deleted = false,
    this.area,
    this.sessionId,
    this.relatedTableIds = const {},
  });
  final TableChangeKind kind;

  /// Area ID for area changes, table ID for all other changes.
  final String id;
  final bool deleted;
  final TableAreaSummary? area;
  final String? sessionId;
  final Set<String> relatedTableIds;
}

class TableEvents extends ChangeNotifier {
  TableChange? change;
  int revision = 0;
  final Set<String> _pending = {};
  final Set<String> _transferPending = {};
  final Set<String> _transferUnresolved = {};
  final Map<Object, String> _externalSessionBlocks = {};
  bool pending(String key) => _pending.contains(key);
  bool lock(String key) => _pending.add(key);
  void unlock(String key) => _pending.remove(key);
  bool transferPending(String sessionId) =>
      _transferPending.contains(sessionId);
  bool transferUnresolved(String sessionId) =>
      _transferUnresolved.contains(sessionId);
  bool sessionTransferBlocked(String? sessionId) =>
      sessionId != null &&
      (transferPending(sessionId) || transferUnresolved(sessionId));
  bool externalSessionBlocked(String sessionId) =>
      _externalSessionBlocks.containsValue(sessionId);
  void markExternalSessionBlocked(
    Object source,
    String? sessionId,
    bool value,
  ) {
    final previous = _externalSessionBlocks[source];
    if (value && sessionId != null) {
      if (previous == sessionId) return;
      _externalSessionBlocks[source] = sessionId;
    } else {
      if (_externalSessionBlocks.remove(source) == null) return;
    }
    notifyListeners();
  }

  bool lockTransfer(String sessionId) {
    final added = _transferPending.add(sessionId);
    if (added) notifyListeners();
    return added;
  }

  void unlockTransfer(String sessionId) {
    if (_transferPending.remove(sessionId)) notifyListeners();
  }

  void markTransferUnresolved(String sessionId, bool value) {
    final changed = value
        ? _transferUnresolved.add(sessionId)
        : _transferUnresolved.remove(sessionId);
    if (changed) notifyListeners();
  }

  void emit(TableChange value) {
    change = value;
    revision++;
    notifyListeners();
  }
}
