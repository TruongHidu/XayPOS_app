import 'package:flutter/foundation.dart';
import 'order_invalidation.dart';

class OrderEvents extends ChangeNotifier {
  String? changedId, sessionId;
  int revision = 0;
  Object? source;
  OrderInvalidation? remote;
  bool get hasPending => _pending.isNotEmpty;
  bool affectsOrder(String id) => remote?.affectsOrder(id) ?? changedId == id;
  bool affectsSession(String? id) =>
      remote?.affectsSession(id) ?? sessionId == id;
  void invalidateRemote(OrderInvalidation hint) {
    remote = hint;
    source = hint;
    changedId = null;
    sessionId = null;
    revision++;
    notifyListeners();
  }

  final Set<String> _pending = {};
  final Set<String> _unresolved = {};
  bool unresolved(String id) => _unresolved.contains(id);
  void markUnresolved(String id, bool value) {
    final changed = value ? _unresolved.add(id) : _unresolved.remove(id);
    if (changed) notifyListeners();
  }

  bool pending(String id) => _pending.contains(id);
  bool lock(String id) {
    final added = _pending.add(id);
    if (added) notifyListeners();
    return added;
  }

  void unlock(String id) {
    _pending.remove(id);
    notifyListeners();
  }

  void emit(String id, String? session, {Object? source}) {
    remote = null;
    this.source = source;
    changedId = id;
    sessionId = session;
    revision++;
    notifyListeners();
  }
}
