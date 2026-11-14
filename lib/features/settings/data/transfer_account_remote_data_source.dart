import 'package:dio/dio.dart';

import '../domain/entities/transfer_account.dart';

class TransferAccountRemoteDataSource {
  const TransferAccountRemoteDataSource(this._dio);

  final Dio _dio;

  static const path = '/api/v1/restaurants/me/transfer-account';

  Future<TransferAccount?> get() async {
    final response = await _dio.get<Map<String, dynamic>>(path);
    return parse(response.data);
  }

  Future<TransferAccount> save(TransferAccountDraft draft) async {
    final response = await _dio.put<Map<String, dynamic>>(
      path,
      data: draft.toJson(),
    );
    return parse(response.data) ??
        (throw const FormatException('Saved account missing'));
  }

  Future<void> remove() async {
    await _dio.delete<Object?>(path);
  }

  /// `{configured:false}` → null.
  static TransferAccount? parse(Map<String, dynamic>? json) {
    final configured = json?['configured'];
    if (configured == false) return null;
    final bin = json?['bankBin'];
    final number = json?['accountNumber'];
    final name = json?['accountName'];
    if (configured != true ||
        bin is! String ||
        bin.isEmpty ||
        number is! String ||
        number.isEmpty ||
        name is! String ||
        name.isEmpty) {
      throw const FormatException('Invalid transfer account');
    }
    final updatedAt = json?['updatedAt'];
    return TransferAccount(
      bankBin: bin,
      accountNumber: number,
      accountName: name,
      updatedAt: updatedAt is String ? DateTime.tryParse(updatedAt) : null,
    );
  }
}
