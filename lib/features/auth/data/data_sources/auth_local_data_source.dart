import '../../../../core/storage/token_storage.dart';
import '../../domain/entities/auth_tokens.dart';

abstract interface class AuthLocalDataSource {
  Future<AuthTokens?> readTokens();
  Future<void> replaceTokens(AuthTokens tokens);
  Future<void> clear();
}

class AuthLocalDataSourceImpl implements AuthLocalDataSource {
  const AuthLocalDataSourceImpl(this._storage);

  final TokenStorage _storage;

  @override
  Future<AuthTokens?> readTokens() => _storage.read();

  @override
  Future<void> replaceTokens(AuthTokens tokens) => _storage.replace(tokens);

  @override
  Future<void> clear() => _storage.clear();
}
