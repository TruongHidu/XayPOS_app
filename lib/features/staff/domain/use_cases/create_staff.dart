import '../../../../core/result/result.dart';
import '../entities/staff_member.dart';
import '../repositories/staff_repository.dart';

class CreateStaff {
  const CreateStaff(this._repository);

  final StaffRepository _repository;

  Future<Result<StaffMember>> call({
    required String name,
    required String email,
    String? phone,
    required String roleCode,
    required String initialPassword,
  }) {
    return _repository.createStaff(
      name: name,
      email: email,
      phone: phone,
      roleCode: roleCode,
      initialPassword: initialPassword,
    );
  }
}
