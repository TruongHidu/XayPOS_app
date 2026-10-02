import '../../../../core/result/result.dart';
import '../entities/staff_permission_config.dart';
import '../repositories/staff_repository.dart';

class GetStaffPermissions {
  const GetStaffPermissions(this._repository);

  final StaffRepository _repository;

  Future<Result<StaffPermissionConfig>> call(String staffId) {
    return _repository.getStaffPermissions(staffId);
  }
}
