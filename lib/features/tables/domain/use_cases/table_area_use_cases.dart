import '../../../../core/result/result.dart';
import '../entities/table_entities.dart';
import '../entities/table_inputs.dart';
import '../entities/table_query.dart';
import '../repositories/table_area_repository.dart';

class ListTableArea {
  const ListTableArea(this.repository);
  final TableAreaRepository repository;
  Future<Result<TablePage<TableArea>>> call(TableQuery query) =>
      repository.list(query);
}

class DetailTableArea {
  const DetailTableArea(this.repository);
  final TableAreaRepository repository;
  Future<Result<TableArea>> call(String id) => repository.detail(id);
}

class CreateTableArea {
  const CreateTableArea(this.repository);
  final TableAreaRepository repository;
  Future<Result<TableArea>> call(CreateTableAreaInput input) =>
      repository.create(input);
}

class UpdateTableArea {
  const UpdateTableArea(this.repository);
  final TableAreaRepository repository;
  Future<Result<TableArea>> call(String id, UpdateTableAreaInput input) =>
      repository.update(id, input);
}

class SetStatusTableArea {
  const SetStatusTableArea(this.repository);
  final TableAreaRepository repository;
  Future<Result<TableArea>> call(String id, bool active, int version) =>
      repository.setStatus(id, active, version);
}

class DeleteTableArea {
  const DeleteTableArea(this.repository);
  final TableAreaRepository repository;
  Future<Result<void>> call(String id, int version) =>
      repository.delete(id, version);
}
