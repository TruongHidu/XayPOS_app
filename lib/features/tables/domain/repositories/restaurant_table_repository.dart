import '../../../../core/result/result.dart';
import '../entities/table_entities.dart';
import '../entities/table_inputs.dart';
import '../entities/table_query.dart';

abstract interface class RestaurantTableRepository {
  Future<Result<TablePage<RestaurantTable>>> list(TableQuery query);
  Future<Result<RestaurantTable>> detail(String id);
  Future<Result<RestaurantTable>> create(CreateRestaurantTableInput input);
  Future<Result<RestaurantTable>> update(
    String id,
    UpdateRestaurantTableInput input,
  );
  Future<Result<RestaurantTable>> setStatus(
    String id,
    TableStatus status,
    int version,
  );
  Future<Result<RestaurantTable>> assignArea(
    String id,
    String? areaId,
    int version,
  );
  Future<Result<void>> delete(String id, int version);
  Future<Result<TableQrPayload>> qr(String id);
  Future<Result<TableQrPayload>> rotateQr(String id, int version);
}
