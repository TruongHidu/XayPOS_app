class StaffPermissionConfig {
  const StaffPermissionConfig({
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
}
