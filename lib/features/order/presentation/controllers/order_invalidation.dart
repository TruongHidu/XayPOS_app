/// A remote read hint. It never releases mutation or unknown-outcome locks.
class OrderInvalidation {
  OrderInvalidation({
    Iterable<String> orderIds = const [],
    Iterable<String> sessionIds = const [],
    this.all = false,
  }) : orderIds = Set.unmodifiable(orderIds),
       sessionIds = Set.unmodifiable(sessionIds);
  final Set<String> orderIds, sessionIds;
  final bool all;
  bool affectsOrder(String id) => all || orderIds.contains(id);
  bool affectsSession(String? id) =>
      all || id != null && sessionIds.contains(id);
}
