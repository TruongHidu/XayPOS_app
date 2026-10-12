import '../../../../core/result/result.dart';
import '../../domain/entities/table_entities.dart';
import '../../domain/entities/table_inputs.dart';
import '../../domain/entities/table_query.dart';
import '../../domain/repositories/table_session_repository.dart';
import '../data_sources/tables_remote_data_source.dart';
import 'table_result.dart';

class TableSessionRepositoryImpl implements TableSessionRepository {
  TableSessionRepositoryImpl(this.remote);
  final TablesRemoteDataSource remote;
  @override
  Future<Result<TablePage<TableSession>>> list(TableQuery query) =>
      tableResult(() => remote.tableSessionList(query));
  @override
  Future<Result<TableSession>> detail(String id) =>
      tableResult(() => remote.tableSessionDetail(id));
  @override
  Future<Result<TableSession?>> current(String id) =>
      tableResult(() => remote.tableSessionCurrent(id));
  @override
  Future<Result<TableSession>> open(String id, OpenTableSessionInput input) =>
      tableResult(() => remote.tableSessionOpen(id, input));
  @override
  Future<Result<TableSession>> update(
    String id,
    UpdateTableSessionInput input,
  ) => tableResult(() => remote.tableSessionUpdate(id, input));
  @override
  Future<Result<TableSession>> cancel(String id, String reason, int version) =>
      tableResult(() => remote.tableSessionCancel(id, reason, version));
  @override
  Future<Result<TableSessionTransferResult>> transfer(
    String id,
    TransferTableSessionInput input,
    String idempotencyKey,
  ) =>
      tableResult(() => remote.tableSessionTransfer(id, input, idempotencyKey));
  @override
  Future<Result<TablePage<TableSessionTransferHistoryEntry>>> transfers(
    String id, {
    required int page,
    required int size,
  }) => tableResult(
    () => remote.tableSessionTransfers(id, page: page, size: size),
  );
}
