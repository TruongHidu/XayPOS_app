import '../../../../core/result/result.dart';
import '../entities/table_entities.dart';
import '../entities/table_inputs.dart';
import '../entities/table_query.dart';
import '../repositories/restaurant_table_repository.dart';

class ListRestaurantTable {
  const ListRestaurantTable(this.repository);
  final RestaurantTableRepository repository;
  Future<Result<TablePage<RestaurantTable>>> call(TableQuery query) =>
      repository.list(query);
}

class DetailRestaurantTable {
  const DetailRestaurantTable(this.repository);
  final RestaurantTableRepository repository;
  Future<Result<RestaurantTable>> call(String id) => repository.detail(id);
}

class CreateRestaurantTable {
  const CreateRestaurantTable(this.repository);
  final RestaurantTableRepository repository;
  Future<Result<RestaurantTable>> call(CreateRestaurantTableInput input) =>
      repository.create(input);
}

class UpdateRestaurantTable {
  const UpdateRestaurantTable(this.repository);
  final RestaurantTableRepository repository;
  Future<Result<RestaurantTable>> call(
    String id,
    UpdateRestaurantTableInput input,
  ) => repository.update(id, input);
}

class SetStatusRestaurantTable {
  const SetStatusRestaurantTable(this.repository);
  final RestaurantTableRepository repository;
  Future<Result<RestaurantTable>> call(
    String id,
    TableStatus status,
    int version,
  ) => repository.setStatus(id, status, version);
}

class AssignAreaRestaurantTable {
  const AssignAreaRestaurantTable(this.repository);
  final RestaurantTableRepository repository;
  Future<Result<RestaurantTable>> call(
    String id,
    String? areaId,
    int version,
  ) => repository.assignArea(id, areaId, version);
}

class DeleteRestaurantTable {
  const DeleteRestaurantTable(this.repository);
  final RestaurantTableRepository repository;
  Future<Result<void>> call(String id, int version) =>
      repository.delete(id, version);
}

class QrRestaurantTable {
  const QrRestaurantTable(this.repository);
  final RestaurantTableRepository repository;
  Future<Result<TableQrPayload>> call(String id) => repository.qr(id);
}

class RotateQrRestaurantTable {
  const RotateQrRestaurantTable(this.repository);
  final RestaurantTableRepository repository;
  Future<Result<TableQrPayload>> call(String id, int version) =>
      repository.rotateQr(id, version);
}
