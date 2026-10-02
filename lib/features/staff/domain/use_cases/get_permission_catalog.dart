import '../../../../core/result/result.dart';
import '../entities/permission_catalog_item.dart';
import '../repositories/staff_repository.dart';

class GetPermissionCatalog {
  const GetPermissionCatalog(this._repository);

  final StaffRepository _repository;

  Future<Result<List<PermissionCatalogItem>>> call() {
    return _repository.getPermissionCatalog();
  }
}
