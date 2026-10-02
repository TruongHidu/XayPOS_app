import 'staff_role.dart';

class StaffMember {
  const StaffMember({
    required this.id,
    required this.name,
    required this.email,
    this.phone,
    required this.active,
    required this.role,
    this.lastLoginAt,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String email;
  final String? phone;
  final bool active;
  final StaffRole role;
  final DateTime? lastLoginAt;
  final DateTime createdAt;
  final DateTime updatedAt;
}
