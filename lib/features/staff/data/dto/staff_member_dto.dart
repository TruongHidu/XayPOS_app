import '../../domain/entities/staff_member.dart';
import 'staff_role_dto.dart';

class StaffMemberDto {
  const StaffMemberDto({
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
  final StaffRoleDto role;
  final String? lastLoginAt;
  final String createdAt;
  final String updatedAt;

  factory StaffMemberDto.fromJson(Map<String, dynamic> json) {
    return StaffMemberDto(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      email: json['email'] as String? ?? '',
      phone: json['phone'] as String?,
      active: json['active'] as bool? ?? false,
      role: StaffRoleDto.fromJson(json['role'] as Map<String, dynamic>? ?? {}),
      lastLoginAt: json['lastLoginAt'] as String?,
      createdAt: json['createdAt'] as String? ?? '',
      updatedAt: json['updatedAt'] as String? ?? '',
    );
  }

  StaffMember toEntity() {
    return StaffMember(
      id: id,
      name: name,
      email: email,
      phone: phone,
      active: active,
      role: role.toEntity(),
      lastLoginAt: lastLoginAt != null ? DateTime.tryParse(lastLoginAt!) : null,
      createdAt: DateTime.tryParse(createdAt) ?? DateTime.now(),
      updatedAt: DateTime.tryParse(updatedAt) ?? DateTime.now(),
    );
  }
}
