import '../../../../core/result/result.dart';
import '../entities/staff_role.dart';
import '../repositories/staff_repository.dart';

class GetAssignableRoles {
  const GetAssignableRoles(this._repository);

  final StaffRepository _repository;

  Future<Result<List<StaffRole>>> call() {
    return _repository.getAssignableRoles();
  }
}
