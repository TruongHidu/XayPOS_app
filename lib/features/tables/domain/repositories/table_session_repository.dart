import '../../../../core/result/result.dart';
import '../entities/table_entities.dart';
import '../entities/table_inputs.dart';
import '../entities/table_query.dart';

abstract interface class TableSessionRepository {
  Future<Result<TablePage<TableSession>>> list(TableQuery query);
  Future<Result<TableSession>> detail(String id);
  Future<Result<TableSession?>> current(String id);
  Future<Result<TableSession>> open(String id, OpenTableSessionInput input);
  Future<Result<TableSession>> update(String id, UpdateTableSessionInput input);
  Future<Result<TableSession>> cancel(String id, String reason, int version);
}
