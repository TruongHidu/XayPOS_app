/// What makes two cart entries the same line: the dish and how it is made.
/// Adding the same configuration again raises that line's quantity; any
/// difference starts a new line, which the kitchen then sees separately.
///
/// Toppings will join [note] here (as a sorted list of chosen options) and in
/// [==], without changing how carts add or merge lines.
class OrderLineConfiguration {
  OrderLineConfiguration({required this.menuItemId, String? note})
    : note = normalizeNote(note);

  final String menuItemId;

  /// Trimmed; blank counts as no note.
  final String? note;

  static String? normalizeNote(String? note) {
    final trimmed = note?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  @override
  bool operator ==(Object other) =>
      other is OrderLineConfiguration &&
      other.menuItemId == menuItemId &&
      other.note == note;

  @override
  int get hashCode => Object.hash(menuItemId, note);
}
