/// What happened to an order, as announced by the server.
enum OrderChangeKind {
  created,
  updated,
  submitted,
  itemsAdded,
  itemUpdated,
  itemCancelled,

  /// The kitchen moved a dish along (cooking, ready, served). The bill and
  /// the order's place at its table stay the same.
  itemStatusChanged,
  cancelled,
  completed,
}
