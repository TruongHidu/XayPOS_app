import '../../../core/network/api_error_mapper.dart';
import '../../../core/result/result.dart';
import '../domain/entities/transfer_account.dart';
import '../domain/repositories/transfer_account_repository.dart';
import 'transfer_account_remote_data_source.dart';

class TransferAccountRepositoryImpl implements TransferAccountRepository {
  const TransferAccountRepositoryImpl(this._remote);

  final TransferAccountRemoteDataSource _remote;

  @override
  Future<Result<TransferAccount?>> get() => _guard(_remote.get);

  @override
  Future<Result<TransferAccount>> save(TransferAccountDraft draft) =>
      _guard(() => _remote.save(draft));

  @override
  Future<Result<void>> remove() => _guard(_remote.remove);

  static Future<Result<T>> _guard<T>(Future<T> Function() call) async {
    try {
      return Success(await call());
    } on Object catch (error) {
      return Error(ApiErrorMapper.fromException(error));
    }
  }
}
