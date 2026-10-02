import '../../features/auth/domain/entities/auth_tokens.dart';

abstract interface class TokenStorage {
  Future<AuthTokens?> read();

  Future<void> replace(AuthTokens tokens);

  Future<void> clear();
}
