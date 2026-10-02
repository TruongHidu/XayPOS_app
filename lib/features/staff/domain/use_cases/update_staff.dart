import '../../../../core/result/result.dart';
import '../entities/staff_member.dart';
import '../repositories/staff_repository.dart';

class UpdateStaff {
  const UpdateStaff(this._repository);

  final StaffRepository _repository;

  Future<Result<StaffMember>> call({
    required String staffId,
    String? name,
    String? email,
    String? phone,
    String? roleCode,
  }) {
    return _repository.updateStaff(
      staffId: staffId,
      name: name,
      email: email,
      phone: phone,
      roleCode: roleCode,
    );
  }
}
