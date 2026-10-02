import '../../../../core/result/result.dart';
import '../entities/auth_session.dart';
import '../repositories/auth_repository.dart';

class RefreshSession {
  const RefreshSession(this._repository);

  final AuthRepository _repository;

  Future<Result<AuthSession>> call() => _repository.refreshSession();
}
