import '../../domain/entities/staff_permission_config.dart';

class StaffPermissionConfigDto {
  const StaffPermissionConfigDto({
    required this.staffId,
    required this.roleCode,
    required this.rolePermissions,
    required this.grants,
    required this.denies,
    required this.effectivePermissions,
  });

  final String staffId;
  final String roleCode;
  final List<String> rolePermissions;
  final List<String> grants;
  final List<String> denies;
  final List<String> effectivePermissions;

  factory StaffPermissionConfigDto.fromJson(Map<String, dynamic> json) {
    return StaffPermissionConfigDto(
      staffId: json['staffId'] as String? ?? '',
      roleCode: json['roleCode'] as String? ?? '',
      rolePermissions:
          (json['rolePermissions'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      grants:
          (json['grants'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      denies:
          (json['denies'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      effectivePermissions:
          (json['effectivePermissions'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
    );
  }

  StaffPermissionConfig toEntity() {
    return StaffPermissionConfig(
      staffId: staffId,
      roleCode: roleCode,
      rolePermissions: rolePermissions,
      grants: grants,
      denies: denies,
      effectivePermissions: effectivePermissions,
    );
  }
}
