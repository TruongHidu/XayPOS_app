class StaffRole {
  const StaffRole({required this.id, required this.code, required this.name});

  final String id;
  final String code;
  final String name;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StaffRole &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          code == other.code &&
          name == other.name;

  @override
  int get hashCode => id.hashCode ^ code.hashCode ^ name.hashCode;
}
