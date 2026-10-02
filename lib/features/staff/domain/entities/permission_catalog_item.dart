class PermissionCatalogItem {
  const PermissionCatalogItem({
    required this.code,
    required this.module,
    required this.name,
    this.description,
  });

  final String code;
  final String module;
  final String name;
  final String? description;
}
