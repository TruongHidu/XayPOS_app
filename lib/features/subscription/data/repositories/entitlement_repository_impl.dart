import '../../../../core/network/api_error_mapper.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/entitlement.dart';
import '../../domain/repositories/entitlement_repository.dart';
import '../data_sources/entitlement_remote_data_source.dart';

class EntitlementRepositoryImpl implements EntitlementRepository {
  const EntitlementRepositoryImpl(this._remote);

  final EntitlementRemoteDataSource _remote;

  @override
  Future<Result<Entitlement>> getCurrentEntitlements() async {
    try {
      final response = await _remote.getCurrent();
      return Success(response.toDomain());
    } on Object catch (error) {
      return Error(ApiErrorMapper.fromException(error));
    }
  }
}
