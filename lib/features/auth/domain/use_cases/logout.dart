import '../../../../core/result/result.dart';
import '../repositories/auth_repository.dart';

class Logout {
  const Logout(this._repository);

  final AuthRepository _repository;

  Future<Result<void>> call() => _repository.logout();
}
