import '../../../../core/result/result.dart';
import '../entities/entitlement.dart';
import '../repositories/entitlement_repository.dart';

class GetCurrentEntitlements {
  const GetCurrentEntitlements(this._repository);

  final EntitlementRepository _repository;

  Future<Result<Entitlement>> call() {
    return _repository.getCurrentEntitlements();
  }
}
