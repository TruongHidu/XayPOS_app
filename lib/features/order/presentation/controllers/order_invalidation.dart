/// A remote read hint. It never releases mutation or unknown-outcome locks.
class OrderInvalidation {
  OrderInvalidation({
    Iterable<String> orderIds = const [],
    Iterable<String> sessionIds = const [],
    this.all = false,
    this.affectsTables = true,
  }) : orderIds = Set.unmodifiable(orderIds),
       sessionIds = Set.unmodifiable(sessionIds);
  final Set<String> orderIds, sessionIds;
  final bool all;

  /// False when every change in the batch leaves table cards as they were
  /// (dishes moving through the kitchen), so the table board can skip a
  /// reload. Order and kitchen readers still use the hint as usual.
  final bool affectsTables;
  bool affectsOrder(String id) => all || orderIds.contains(id);
  bool affectsSession(String? id) =>
      all || id != null && sessionIds.contains(id);
}
