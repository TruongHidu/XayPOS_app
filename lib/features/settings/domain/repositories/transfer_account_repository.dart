import '../../../../core/result/result.dart';
import '../entities/transfer_account.dart';

/// The restaurant's receiving bank account for transfer payments.
abstract interface class TransferAccountRepository {
  /// Null while the restaurant has not set an account.
  Future<Result<TransferAccount?>> get();

  Future<Result<TransferAccount>> save(TransferAccountDraft draft);

  Future<Result<void>> remove();
}
