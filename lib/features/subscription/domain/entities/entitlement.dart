import 'package_feature.dart';

enum SubscriptionStatus { active, inactive, missing, notApplicable }

class Entitlement {
  const Entitlement({
    required this.subscriptionId,
    required this.packageCode,
    this.packageName,
    required this.status,
    required this.features,
    this.maxStaff,
    this.startAt,
    this.endAt,
    this.daysRemaining,
  });

  final String? subscriptionId;
  final int? maxStaff;
  final String? packageCode;

  /// Display name of the package; null on servers that do not send it.
  final String? packageName;
  final SubscriptionStatus status;
  final DateTime? startAt;
  final DateTime? endAt;

  /// Whole days left until [endAt] as counted by the server, 0 once expired.
  final int? daysRemaining;
  final List<PackageFeature> features;

  Set<String> get featureCodes => features.map((item) => item.code).toSet();
}
