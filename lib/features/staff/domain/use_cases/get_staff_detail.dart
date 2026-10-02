import '../../../../core/result/result.dart';
import '../entities/staff_member.dart';
import '../repositories/staff_repository.dart';

class GetStaffDetail {
  const GetStaffDetail(this._repository);

  final StaffRepository _repository;

  Future<Result<StaffMember>> call(String staffId) {
    return _repository.getStaffDetail(staffId);
  }
}
