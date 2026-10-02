import '../../domain/entities/staff_role.dart';

class StaffRoleDto {
  const StaffRoleDto({
    required this.id,
    required this.code,
    required this.name,
  });

  final String id;
  final String code;
  final String name;

  factory StaffRoleDto.fromJson(Map<String, dynamic> json) {
    return StaffRoleDto(
      id: json['id'] as String? ?? '',
      code: json['code'] as String? ?? '',
      name: json['name'] as String? ?? '',
    );
  }

  StaffRole toEntity() {
    return StaffRole(id: id, code: code, name: name);
  }
}
