import '../../../../core/result/result.dart';
import '../../domain/entities/table_entities.dart';
import '../../domain/entities/table_inputs.dart';
import '../../domain/entities/table_query.dart';
import '../../domain/repositories/restaurant_table_repository.dart';
import '../data_sources/tables_remote_data_source.dart';
import 'table_result.dart';

class RestaurantTableRepositoryImpl implements RestaurantTableRepository {
  RestaurantTableRepositoryImpl(this.remote);
  final TablesRemoteDataSource remote;
  @override
  Future<Result<TablePage<RestaurantTable>>> list(TableQuery query) =>
      tableResult(() => remote.restaurantTableList(query));
  @override
  Future<Result<RestaurantTable>> detail(String id) =>
      tableResult(() => remote.restaurantTableDetail(id));
  @override
  Future<Result<RestaurantTable>> create(CreateRestaurantTableInput input) =>
      tableResult(() => remote.restaurantTableCreate(input));
  @override
  Future<Result<RestaurantTable>> update(
    String id,
    UpdateRestaurantTableInput input,
  ) => tableResult(() => remote.restaurantTableUpdate(id, input));
  @override
  Future<Result<RestaurantTable>> setStatus(
    String id,
    TableStatus status,
    int version,
  ) => tableResult(() => remote.restaurantTableSetStatus(id, status, version));
  @override
  Future<Result<RestaurantTable>> assignArea(
    String id,
    String? areaId,
    int version,
  ) => tableResult(() => remote.restaurantTableAssignArea(id, areaId, version));
  @override
  Future<Result<void>> delete(String id, int version) =>
      tableResult(() => remote.restaurantTableDelete(id, version));
  @override
  Future<Result<TableQrPayload>> qr(String id) =>
      tableResult(() => remote.restaurantTableQr(id));
  @override
  Future<Result<TableQrPayload>> rotateQr(String id, int version) =>
      tableResult(() => remote.restaurantTableRotateQr(id, version));
}
