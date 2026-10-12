import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../../../../app/providers.dart';
import '../../../../core/auth/access_policy.dart';
import '../../../../core/errors/failure.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../data/data_sources/tables_remote_data_source.dart';
import '../../data/table_transfer_key_generator.dart';
import '../controllers/table_events.dart';
import '../controllers/table_area_controller.dart';
import '../controllers/restaurant_table_controller.dart';
import '../controllers/table_session_controller.dart';
import '../controllers/table_transfer_controller.dart';
import '../controllers/table_detail_controller.dart';
import '../../data/repositories/table_area_repository_impl.dart';
import '../../domain/repositories/table_area_repository.dart';
import '../../domain/use_cases/table_area_use_cases.dart';
import '../../data/repositories/restaurant_table_repository_impl.dart';
import '../../domain/repositories/restaurant_table_repository.dart';
import '../../domain/use_cases/restaurant_table_use_cases.dart';
import '../../data/repositories/table_session_repository_impl.dart';
import '../../domain/repositories/table_session_repository.dart';
import '../../domain/entities/table_inputs.dart';
import '../../domain/use_cases/table_session_use_cases.dart';

final tablesRemoteProvider = Provider(
  (ref) => TablesRemoteDataSource(ref.watch(apiClientsProvider).authenticated),
);
final tableScopeProvider = Provider<Object?>(
  (ref) => ref.watch(
    authControllerProvider.select(
      (a) => AccessPolicy.tableScope(a.state.session),
    ),
  ),
);
final tableEventsProvider = ChangeNotifierProvider((ref) {
  ref.watch(tableScopeProvider);
  return TableEvents();
});
final tableNoticeProvider = StateProvider<String?>((ref) => null);

class TableAccessRecovery {
  TableAccessRecovery(this.auth, this.notice);
  final AuthController auth;
  final void Function(String) notice;
  final Set<Object?> _handled = {};
  Future<void>? _pending;
  Future<void> handle(Failure failure) async {
    notice(failure.message);
    final scope = AccessPolicy.tableScope(auth.state.session);
    if (!_handled.add(scope)) return;
    if (_pending != null) {
      await _pending;
      return;
    }
    final future = auth.restore();
    _pending = future;
    try {
      await future;
    } finally {
      _pending = null;
    }
  }
}

final tableRecoveryProvider = Provider(
  (ref) => TableAccessRecovery(
    ref.read(authControllerProvider),
    (m) => ref.read(tableNoticeProvider.notifier).state = m,
  ),
);
final tableAreaRepositoryProvider = Provider<TableAreaRepository>(
  (ref) => TableAreaRepositoryImpl(ref.watch(tablesRemoteProvider)),
);
final restaurantTableRepositoryProvider = Provider<RestaurantTableRepository>(
  (ref) => RestaurantTableRepositoryImpl(ref.watch(tablesRemoteProvider)),
);
final tableSessionRepositoryProvider = Provider<TableSessionRepository>(
  (ref) => TableSessionRepositoryImpl(ref.watch(tablesRemoteProvider)),
);
final tableTransferKeyGeneratorProvider = Provider<TableTransferKeyGenerator>(
  (ref) => SecureTableTransferKeyGenerator(),
);
final tableAreaControllerProvider = ChangeNotifierProvider<TableAreaController>(
  (ref) {
    ref.watch(tableScopeProvider);
    final auth = ref.read(authControllerProvider);
    final repository = ref.watch(tableAreaRepositoryProvider);
    final controller = TableAreaController(
      session: () => auth.state.session,
      events: ref.read(tableEventsProvider),
      onAccessDenied: ref.read(tableRecoveryProvider).handle,
      list: ListTableArea(repository),
      get: DetailTableArea(repository),
      createArea: CreateTableArea(repository),
      updateArea: UpdateTableArea(repository),
      statusArea: SetStatusTableArea(repository),
      deleteArea: DeleteTableArea(repository),
    );
    Future.microtask(controller.load);
    return controller;
  },
);
final restaurantTableControllerProvider =
    ChangeNotifierProvider<RestaurantTableController>((ref) {
      ref.watch(tableScopeProvider);
      final auth = ref.read(authControllerProvider);
      final repository = ref.watch(restaurantTableRepositoryProvider);
      final controller = RestaurantTableController(
        session: () => auth.state.session,
        events: ref.read(tableEventsProvider),
        onAccessDenied: ref.read(tableRecoveryProvider).handle,
        list: ListRestaurantTable(repository),
        get: DetailRestaurantTable(repository),
        createTable: CreateRestaurantTable(repository),
        updateTable: UpdateRestaurantTable(repository),
        statusTable: SetStatusRestaurantTable(repository),
        assignTable: AssignAreaRestaurantTable(repository),
        deleteTable: DeleteRestaurantTable(repository),
      );
      Future.microtask(controller.load);
      return controller;
    });
final tableAreaSelectorProvider = ChangeNotifierProvider.autoDispose
    .family<TableAreaSelectorController, bool>((ref, id) {
      ref.watch(tableScopeProvider);
      final auth = ref.read(authControllerProvider);
      final repository = ref.watch(tableAreaRepositoryProvider);
      final controller = TableAreaSelectorController(
        session: () => auth.state.session,
        events: ref.read(tableEventsProvider),
        onAccessDenied: ref.read(tableRecoveryProvider).handle,
        list: ListTableArea(repository),
        activeOnly: id,
      );
      Future.microtask(controller.load);
      return controller;
    });
final tableSessionControllerProvider = ChangeNotifierProvider.autoDispose
    .family<TableSessionController, String>((ref, id) {
      ref.watch(tableScopeProvider);
      final auth = ref.read(authControllerProvider);
      final repository = ref.watch(tableSessionRepositoryProvider);
      final controller = TableSessionController(
        session: () => auth.state.session,
        events: ref.read(tableEventsProvider),
        onAccessDenied: ref.read(tableRecoveryProvider).handle,
        tableId: id,
        list: ListTableSession(repository),
        get: DetailTableSession(repository),
        getCurrent: CurrentTableSession(repository),
        openSession: OpenTableSession(repository),
        updateSession: UpdateTableSession(repository),
        cancelSession: CancelTableSession(repository),
      );
      return controller;
    });
final tableTransferControllerProvider = ChangeNotifierProvider.autoDispose
    .family<TableTransferController, String>((ref, sessionId) {
      ref.watch(tableScopeProvider);
      final auth = ref.read(authControllerProvider);
      final sessionRepository = ref.watch(tableSessionRepositoryProvider);
      final controller = TableTransferController(
        session: () => auth.state.session,
        events: ref.read(tableEventsProvider),
        onAccessDenied: ref.read(tableRecoveryProvider).handle,
        sessionId: sessionId,
        getSession: DetailTableSession(sessionRepository),
        listTables: ListRestaurantTable(
          ref.watch(restaurantTableRepositoryProvider),
        ),
        transferSession: TransferTableSession(sessionRepository),
        keys: ref.watch(tableTransferKeyGeneratorProvider),
      );
      void Function()? release;
      void retainIntent() {
        if (controller.busy || controller.uncertain) {
          release ??= ref.keepAlive().close;
        } else {
          release?.call();
          release = null;
        }
      }

      controller.addListener(retainIntent);
      ref.onDispose(() => controller.removeListener(retainIntent));
      Future.microtask(controller.loadSession);
      return controller;
    });
final tableTransferHistoryControllerProvider = ChangeNotifierProvider
    .autoDispose
    .family<TableTransferHistoryController, String>((ref, sessionId) {
      ref.watch(tableScopeProvider);
      final auth = ref.read(authControllerProvider);
      final controller = TableTransferHistoryController(
        session: () => auth.state.session,
        events: ref.read(tableEventsProvider),
        onAccessDenied: ref.read(tableRecoveryProvider).handle,
        sessionId: sessionId,
        getTransfers: GetTableSessionTransfers(
          ref.watch(tableSessionRepositoryProvider),
        ),
      );
      return controller;
    });
final tableDetailControllerProvider = ChangeNotifierProvider.autoDispose
    .family<TableDetailController, String>((ref, id) {
      ref.watch(tableScopeProvider);
      final auth = ref.read(authControllerProvider);
      final repository = ref.watch(restaurantTableRepositoryProvider);
      final controller = TableDetailController(
        session: () => auth.state.session,
        events: ref.read(tableEventsProvider),
        onAccessDenied: ref.read(tableRecoveryProvider).handle,
        id: id,
        get: DetailRestaurantTable(repository),
      );
      Future.microtask(controller.load);
      return controller;
    });
final tableQrControllerProvider = ChangeNotifierProvider.autoDispose
    .family<TableQrController, String>((ref, id) {
      ref.watch(tableScopeProvider);
      final auth = ref.read(authControllerProvider);
      final repository = ref.watch(restaurantTableRepositoryProvider);
      final controller = TableQrController(
        session: () => auth.state.session,
        events: ref.read(tableEventsProvider),
        onAccessDenied: ref.read(tableRecoveryProvider).handle,
        id: id,
        get: QrRestaurantTable(repository),
        rotate: RotateQrRestaurantTable(repository),
      );
      Future.microtask(controller.load);
      return controller;
    });
