import '../../domain/entities/entitlement.dart';
import '../../domain/entities/package_feature.dart';

class EntitlementDto {
  const EntitlementDto({
    required this.subscriptionId,
    required this.packageCode,
    this.packageName,
    required this.status,
    required this.startAt,
    required this.endAt,
    required this.features,
    this.maxStaff,
    this.daysRemaining,
  });

  factory EntitlementDto.fromJson(Map<String, dynamic> json) {
    final features = json['features'];
    return EntitlementDto(
      subscriptionId: json['subscriptionId'] as String?,
      packageCode: json['packageCode'] as String?,
      packageName: json['packageName'] as String?,
      maxStaff: json['maxStaff'] as int?,
      status: json['status'] as String? ?? 'INACTIVE',
      startAt: DateTime.tryParse(json['startAt'] as String? ?? ''),
      endAt: DateTime.tryParse(json['endAt'] as String? ?? ''),
      daysRemaining: (json['daysRemaining'] as num?)?.toInt(),
      features: features is List
          ? features
                .whereType<Map<String, dynamic>>()
                .map(PackageFeatureDto.fromJson)
                .toList()
          : const [],
    );
  }

  final String? subscriptionId;
  final int? maxStaff;
  final String? packageCode;
  final String? packageName;
  final String status;
  final DateTime? startAt;
  final DateTime? endAt;
  final int? daysRemaining;
  final List<PackageFeatureDto> features;

  Entitlement toDomain() => Entitlement(
    subscriptionId: subscriptionId,
    packageCode: packageCode,
    packageName: packageName,
    maxStaff: maxStaff,
    status: status == 'ACTIVE'
        ? SubscriptionStatus.active
        : SubscriptionStatus.inactive,
    startAt: startAt,
    endAt: endAt,
    daysRemaining: daysRemaining,
    features: features.map((item) => item.toDomain()).toList(),
  );
}

class PackageFeatureDto {
  const PackageFeatureDto({required this.code, required this.limits});

  factory PackageFeatureDto.fromJson(Map<String, dynamic> json) {
    final limits = json['limits'];
    return PackageFeatureDto(
      code: json['code'] as String? ?? '',
      limits: limits is Map<String, dynamic> ? limits : const {},
    );
  }

  final String code;
  final Map<String, dynamic> limits;

  PackageFeature toDomain() => PackageFeature(code: code, limits: limits);
}
