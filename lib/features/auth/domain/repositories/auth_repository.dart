import '../../../../core/result/result.dart';
import '../entities/auth_session.dart';
import '../entities/authenticated_user.dart';
import '../entities/login_credentials.dart';

abstract interface class AuthRepository {
  Future<Result<AuthSession>> login(
    LoginCredentials credentials, {
    String? deviceInfo,
  });

  Future<Result<AuthSession?>> restoreSession();

  Future<Result<AuthSession>> refreshSession();

  Future<Result<AuthenticatedUser>> getCurrentUser();

  Future<Result<void>> logout();
}
