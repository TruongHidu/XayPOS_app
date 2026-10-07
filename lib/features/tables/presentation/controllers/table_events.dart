import 'package:flutter/foundation.dart';
import '../../domain/entities/table_entities.dart';

enum TableChangeKind { area, table, session, qr }

class TableChange {
  const TableChange(this.kind, this.id, {this.deleted = false, this.area});
  final TableChangeKind kind;

  /// Area ID for area changes, table ID for all other changes.
  final String id;
  final bool deleted;
  final TableAreaSummary? area;
}

class TableEvents extends ChangeNotifier {
  TableChange? change;
  final Set<String> _pending = {};
  bool pending(String key) => _pending.contains(key);
  bool lock(String key) => _pending.add(key);
  void unlock(String key) => _pending.remove(key);
  void emit(TableChange value) {
    change = value;
    notifyListeners();
  }
}
