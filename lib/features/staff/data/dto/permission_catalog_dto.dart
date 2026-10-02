import '../../domain/entities/permission_catalog_item.dart';

class PermissionCatalogDto {
  const PermissionCatalogDto({
    required this.code,
    required this.module,
    required this.name,
    this.description,
  });

  final String code;
  final String module;
  final String name;
  final String? description;

  factory PermissionCatalogDto.fromJson(Map<String, dynamic> json) {
    return PermissionCatalogDto(
      code: json['code'] as String? ?? '',
      module: json['module'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String?,
    );
  }

  PermissionCatalogItem toEntity() {
    return PermissionCatalogItem(
      code: code,
      module: module,
      name: name,
      description: description,
    );
  }
}
