import 'package:pos_saas_app/core/auth/app_session.dart';
import 'package:pos_saas_app/core/auth/session_events.dart';
import 'package:pos_saas_app/core/errors/failure.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/core/storage/token_storage.dart';
import 'package:pos_saas_app/features/auth/domain/entities/auth_session.dart';
import 'package:pos_saas_app/features/auth/domain/entities/auth_tokens.dart';
import 'package:pos_saas_app/features/auth/domain/entities/authenticated_user.dart';
import 'package:pos_saas_app/features/auth/domain/entities/login_credentials.dart';
import 'package:pos_saas_app/features/auth/domain/entities/user_role.dart';
import 'package:pos_saas_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:pos_saas_app/features/auth/domain/use_cases/login_use_case.dart';
import 'package:pos_saas_app/features/auth/domain/use_cases/logout.dart';
import 'package:pos_saas_app/features/auth/domain/use_cases/restore_session.dart';
import 'package:pos_saas_app/features/auth/presentation/controllers/auth_controller.dart';
import 'package:pos_saas_app/features/subscription/domain/entities/entitlement.dart';
import 'package:pos_saas_app/features/subscription/domain/entities/package_feature.dart';
import 'package:pos_saas_app/features/subscription/domain/repositories/entitlement_repository.dart';
import 'package:pos_saas_app/features/subscription/domain/use_cases/get_current_entitlements.dart';

const networkFailure = Failure(
  type: FailureType.network,
  message: 'Không thể kết nối đến máy chủ. Vui lòng thử lại.',
);

AuthenticatedUser makeUser({
  UserRole role = UserRole.owner,
  String? restaurantId = 'restaurant-1',
  Set<String> permissions = const {'MENU_VIEW'},
}) {
  return AuthenticatedUser(
    id: 'user-1',
    restaurantId: restaurantId,
    restaurantCode: restaurantId == null ? null : 'NH01',
    restaurantName: restaurantId == null ? null : 'Nhà hàng',
    name: 'Nguyễn Văn A',
    email: 'owner@example.com',
    role: role,
    permissions: permissions,
  );
}

AuthTokens makeTokens({
  String accessToken = 'access-token',
  String refreshToken = 'refresh-token',
  DateTime? expiresAt,
}) {
  return AuthTokens(
    accessToken: accessToken,
    refreshToken: refreshToken,
    expiresAt: expiresAt ?? DateTime.now().add(const Duration(minutes: 15)),
  );
}

AuthSession makeAuthSession({
  UserRole role = UserRole.owner,
  String? restaurantId = 'restaurant-1',
  Set<String> permissions = const {'MENU_VIEW'},
  AuthTokens? tokens,
}) {
  return AuthSession(
    user: makeUser(
      role: role,
      restaurantId: restaurantId,
      permissions: permissions,
    ),
    tokens: tokens ?? makeTokens(),
  );
}

Entitlement makeEntitlement({
  SubscriptionStatus status = SubscriptionStatus.active,
  Set<String> features = const {'MENU_MANAGEMENT'},
}) {
  return Entitlement(
    subscriptionId: status == SubscriptionStatus.active ? 'sub-1' : null,
    packageCode: status == SubscriptionStatus.active ? 'PRO' : null,
    status: status,
    features: features.map((code) => PackageFeature(code: code)).toList(),
  );
}

AppSession makeAppSession({
  UserRole role = UserRole.owner,
  String? restaurantId = 'restaurant-1',
  Set<String> permissions = const {'MENU_VIEW'},
  Set<String> features = const {'MENU_MANAGEMENT'},
  SubscriptionStatus status = SubscriptionStatus.active,
}) {
  final auth = makeAuthSession(
    role: role,
    restaurantId: restaurantId,
    permissions: permissions,
  );
  return AppSession.fromEntitlement(
    user: auth.user,
    tokens: auth.tokens,
    entitlement: makeEntitlement(status: status, features: features),
  );
}

class FakeAuthRepository implements AuthRepository {
  Result<AuthSession> loginResult = Success(makeAuthSession());
  Result<AuthSession?> restoreResult = const Success(null);
  Result<AuthSession> refreshResult = Success(makeAuthSession());
  Result<AuthenticatedUser> meResult = Success(makeUser());
  Result<void> logoutResult = const Success(null);

  int loginCalls = 0;
  int restoreCalls = 0;
  int refreshCalls = 0;
  int logoutCalls = 0;

  @override
  Future<Result<AuthenticatedUser>> getCurrentUser() async => meResult;

  @override
  Future<Result<AuthSession>> login(
    LoginCredentials credentials, {
    String? deviceInfo,
  }) async {
    loginCalls++;
    return loginResult;
  }

  @override
  Future<Result<void>> logout() async {
    logoutCalls++;
    return logoutResult;
  }

  @override
  Future<Result<AuthSession>> refreshSession() async {
    refreshCalls++;
    return refreshResult;
  }

  @override
  Future<Result<AuthSession?>> restoreSession() async {
    restoreCalls++;
    return restoreResult;
  }
}

class FakeEntitlementRepository implements EntitlementRepository {
  Result<Entitlement> result = Success(makeEntitlement());
  int calls = 0;

  @override
  Future<Result<Entitlement>> getCurrentEntitlements() async {
    calls++;
    return result;
  }
}

class FakeTokenStorage implements TokenStorage {
  FakeTokenStorage([this.tokens]);

  AuthTokens? tokens;
  int replaceCalls = 0;
  int clearCalls = 0;

  @override
  Future<void> clear() async {
    clearCalls++;
    tokens = null;
  }

  @override
  Future<AuthTokens?> read() async => tokens;

  @override
  Future<void> replace(AuthTokens value) async {
    replaceCalls++;
    tokens = value;
  }
}

AuthController makeController({
  FakeAuthRepository? authRepository,
  FakeEntitlementRepository? entitlementRepository,
  SessionEvents? sessionEvents,
}) {
  final auth = authRepository ?? FakeAuthRepository();
  final entitlement = entitlementRepository ?? FakeEntitlementRepository();
  return AuthController(
    login: LoginUseCase(auth),
    restoreSession: RestoreSession(auth),
    logout: Logout(auth),
    getEntitlements: GetCurrentEntitlements(entitlement),
    sessionEvents: sessionEvents ?? SessionEvents(),
    deviceInfoLoader: () async => 'Test device',
  );
}
