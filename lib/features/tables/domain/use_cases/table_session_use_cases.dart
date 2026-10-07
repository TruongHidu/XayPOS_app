import '../../../../core/result/result.dart';
import '../entities/table_entities.dart';
import '../entities/table_inputs.dart';
import '../entities/table_query.dart';
import '../repositories/table_session_repository.dart';

class ListTableSession {
  const ListTableSession(this.repository);
  final TableSessionRepository repository;
  Future<Result<TablePage<TableSession>>> call(TableQuery query) =>
      repository.list(query);
}

class DetailTableSession {
  const DetailTableSession(this.repository);
  final TableSessionRepository repository;
  Future<Result<TableSession>> call(String id) => repository.detail(id);
}

class CurrentTableSession {
  const CurrentTableSession(this.repository);
  final TableSessionRepository repository;
  Future<Result<TableSession?>> call(String id) => repository.current(id);
}

class OpenTableSession {
  const OpenTableSession(this.repository);
  final TableSessionRepository repository;
  Future<Result<TableSession>> call(String id, OpenTableSessionInput input) =>
      repository.open(id, input);
}

class UpdateTableSession {
  const UpdateTableSession(this.repository);
  final TableSessionRepository repository;
  Future<Result<TableSession>> call(String id, UpdateTableSessionInput input) =>
      repository.update(id, input);
}

class CancelTableSession {
  const CancelTableSession(this.repository);
  final TableSessionRepository repository;
  Future<Result<TableSession>> call(String id, String reason, int version) =>
      repository.cancel(id, reason, version);
}
