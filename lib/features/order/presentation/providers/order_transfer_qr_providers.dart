import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../core/result/result.dart';
import '../../data/data_sources/order_transfer_qr_remote_data_source.dart';
import '../../data/repositories/order_transfer_qr_repository_impl.dart';
import '../../domain/entities/order_transfer_qr.dart';
import '../../domain/repositories/order_transfer_qr_repository.dart';
import '../../domain/use_cases/order_use_cases.dart';

final orderTransferQrRepositoryProvider = Provider<OrderTransferQrRepository>(
  (ref) => OrderTransferQrRepositoryImpl(
    OrderTransferQrRemoteDataSource(
      ref.watch(apiClientsProvider).authenticated,
    ),
  ),
);

/// Keyed by version so a changed order (new amount) reads a fresh code.
typedef OrderTransferQrKey = ({String orderId, int orderVersion});

/// The VietQR for paying an order by transfer; null when the restaurant has
/// no receiving account. Read once per key: it is never polled, and a failed
/// read waits for the cashier to retry.
final orderTransferQrProvider = FutureProvider.autoDispose
    .family<OrderTransferQrCode?, OrderTransferQrKey>((ref, key) async {
      ref.watch(orderScopeProvider);
      final get = GetOrderTransferQr(
        ref.watch(orderTransferQrRepositoryProvider),
      );
      return switch (await get(key.orderId)) {
        Success(:final value) => value,
        Error(:final failure) => throw failure,
      };
    }, retry: (_, _) => null);
