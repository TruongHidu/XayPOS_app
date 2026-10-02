import '../../../../core/result/result.dart';
import '../entities/staff_permission_config.dart';
import '../repositories/staff_repository.dart';

class UpdateStaffPermissions {
  const UpdateStaffPermissions(this._repository);

  final StaffRepository _repository;

  Future<Result<StaffPermissionConfig>> call({
    required String staffId,
    required List<String> grants,
    required List<String> denies,
  }) {
    return _repository.updateStaffPermissions(
      staffId: staffId,
      grants: grants,
      denies: denies,
    );
  }
}
