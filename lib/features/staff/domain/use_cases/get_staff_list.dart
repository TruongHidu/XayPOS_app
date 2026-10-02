import '../../../../core/result/result.dart';
import '../entities/paginated_staff_result.dart';
import '../repositories/staff_repository.dart';

class GetStaffList {
  const GetStaffList(this._repository);

  final StaffRepository _repository;

  Future<Result<PaginatedStaffResult>> call({
    String? query,
    String? roleCode,
    bool? active,
    int page = 0,
    int size = 20,
    String sortBy = 'createdAt',
    String direction = 'desc',
  }) {
    return _repository.getStaffList(
      query: query,
      roleCode: roleCode,
      active: active,
      page: page,
      size: size,
      sortBy: sortBy,
      direction: direction,
    );
  }
}
