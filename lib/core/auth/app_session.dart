import '../../features/auth/domain/entities/auth_tokens.dart';
import '../../features/auth/domain/entities/authenticated_user.dart';
import '../../features/subscription/domain/entities/entitlement.dart';

class AppSession {
  const AppSession({
    required this.authenticatedUser,
    required this.tokens,
    required this.permissions,
    required this.features,
    this.maxStaff,
    required this.subscriptionStatus,
    this.subscriptionId,
    this.packageCode,
  });

  factory AppSession.withoutEntitlement({
    required AuthenticatedUser user,
    required AuthTokens tokens,
  }) {
    return AppSession(
      authenticatedUser: user,
      tokens: tokens,
      permissions: user.permissions,
      features: const {},
      subscriptionStatus: SubscriptionStatus.notApplicable,
    );
  }

  factory AppSession.fromEntitlement({
    required AuthenticatedUser user,
    required AuthTokens tokens,
    required Entitlement entitlement,
  }) {
    return AppSession(
      authenticatedUser: user,
      tokens: tokens,
      permissions: user.permissions,
      features: entitlement.featureCodes,
      subscriptionId: entitlement.subscriptionId,
      packageCode: entitlement.packageCode,
      maxStaff: entitlement.maxStaff,
      subscriptionStatus: entitlement.status,
    );
  }

  final AuthenticatedUser authenticatedUser;
  final AuthTokens tokens;
  final Set<String> permissions;
  final Set<String> features;
  final String? subscriptionId;
  final int? maxStaff;
  final String? packageCode;
  final SubscriptionStatus subscriptionStatus;

  AppSession copyWithAuth({
    required AuthenticatedUser user,
    required AuthTokens tokens,
  }) {
    return AppSession(
      authenticatedUser: user,
      tokens: tokens,
      permissions: user.permissions,
      features: features,
      subscriptionId: subscriptionId,
      packageCode: packageCode,
      maxStaff: maxStaff,
      subscriptionStatus: subscriptionStatus,
    );
  }
}
