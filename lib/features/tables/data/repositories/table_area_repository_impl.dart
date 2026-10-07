import '../../../../core/result/result.dart';
import '../../domain/entities/table_entities.dart';
import '../../domain/entities/table_inputs.dart';
import '../../domain/entities/table_query.dart';
import '../../domain/repositories/table_area_repository.dart';
import '../data_sources/tables_remote_data_source.dart';
import 'table_result.dart';

class TableAreaRepositoryImpl implements TableAreaRepository {
  TableAreaRepositoryImpl(this.remote);
  final TablesRemoteDataSource remote;
  @override
  Future<Result<TablePage<TableArea>>> list(TableQuery query) =>
      tableResult(() => remote.tableAreaList(query));
  @override
  Future<Result<TableArea>> detail(String id) =>
      tableResult(() => remote.tableAreaDetail(id));
  @override
  Future<Result<TableArea>> create(CreateTableAreaInput input) =>
      tableResult(() => remote.tableAreaCreate(input));
  @override
  Future<Result<TableArea>> update(String id, UpdateTableAreaInput input) =>
      tableResult(() => remote.tableAreaUpdate(id, input));
  @override
  Future<Result<TableArea>> setStatus(String id, bool active, int version) =>
      tableResult(() => remote.tableAreaSetStatus(id, active, version));
  @override
  Future<Result<void>> delete(String id, int version) =>
      tableResult(() => remote.tableAreaDelete(id, version));
}
