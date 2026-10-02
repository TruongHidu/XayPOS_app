import 'package_feature.dart';

enum SubscriptionStatus { active, inactive, missing, notApplicable }

class Entitlement {
  const Entitlement({
    required this.subscriptionId,
    required this.packageCode,
    required this.status,
    required this.features,
    this.maxStaff,
    this.startAt,
    this.endAt,
  });

  final String? subscriptionId;
  final int? maxStaff;
  final String? packageCode;
  final SubscriptionStatus status;
  final DateTime? startAt;
  final DateTime? endAt;
  final List<PackageFeature> features;

  Set<String> get featureCodes => features.map((item) => item.code).toSet();
}
