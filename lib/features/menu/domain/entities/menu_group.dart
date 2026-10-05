class MenuGroup {
  const MenuGroup({
    required this.id,
    required this.name,
    required this.displayOrder,
    required this.active,
    required this.version,
    required this.createdAt,
    required this.updatedAt,
  });
  final String id;
  final String name;
  final int displayOrder;
  final bool active;
  final int version;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class MenuItemGroupSummary {
  const MenuItemGroupSummary({
    required this.id,
    required this.name,
    required this.active,
  });
  final String id;
  final String name;
  final bool active;
}
