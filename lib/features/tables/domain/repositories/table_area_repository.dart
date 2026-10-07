import '../../../../core/result/result.dart';
import '../entities/table_entities.dart';
import '../entities/table_inputs.dart';
import '../entities/table_query.dart';

abstract interface class TableAreaRepository {
  Future<Result<TablePage<TableArea>>> list(TableQuery query);
  Future<Result<TableArea>> detail(String id);
  Future<Result<TableArea>> create(CreateTableAreaInput input);
  Future<Result<TableArea>> update(String id, UpdateTableAreaInput input);
  Future<Result<TableArea>> setStatus(String id, bool active, int version);
  Future<Result<void>> delete(String id, int version);
}
