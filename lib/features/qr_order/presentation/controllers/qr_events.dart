import 'package:flutter/foundation.dart';

class QrInvalidation {
  QrInvalidation({
    Iterable<String> requestIds = const [],
    Iterable<String> tableIds = const [],
    Iterable<String> sessionIds = const [],
    this.all = false,
  }) : requestIds = Set.unmodifiable(requestIds),
       tableIds = Set.unmodifiable(tableIds),
       sessionIds = Set.unmodifiable(sessionIds);
  final Set<String> requestIds, tableIds, sessionIds;
  final bool all;
}

class QrEvents extends ChangeNotifier {
  int revision = 0;
  QrInvalidation? hint;
  void emit(QrInvalidation value) {
    hint = value;
    revision++;
    notifyListeners();
  }
}
