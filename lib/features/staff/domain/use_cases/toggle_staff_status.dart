import '../../../../core/result/result.dart';
import '../entities/staff_member.dart';
import '../repositories/staff_repository.dart';

class ToggleStaffStatus {
  const ToggleStaffStatus(this._repository);

  final StaffRepository _repository;

  Future<Result<StaffMember>> call({
    required String staffId,
    required bool active,
    String? reason,
  }) {
    return _repository.toggleStaffStatus(
      staffId: staffId,
      active: active,
      reason: reason,
    );
  }
}
