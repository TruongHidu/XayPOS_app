import 'package:pos_saas_app/core/auth/app_session.dart';
import 'package:pos_saas_app/features/tables/presentation/controllers/table_events.dart';
import 'table_fakes.dart';
import 'package:pos_saas_app/features/tables/domain/use_cases/table_area_use_cases.dart';
import 'package:pos_saas_app/features/tables/presentation/controllers/table_area_controller.dart';
import 'package:pos_saas_app/features/tables/domain/use_cases/restaurant_table_use_cases.dart';
import 'package:pos_saas_app/features/tables/presentation/controllers/restaurant_table_controller.dart';
import 'package:pos_saas_app/features/tables/domain/use_cases/table_session_use_cases.dart';
import 'package:pos_saas_app/features/tables/presentation/controllers/table_session_controller.dart';

RestaurantTableController tablesController(
  TableServer s,
  AppSession? Function() session,
  TableEvents events,
) => RestaurantTableController(
  session: session,
  events: events,
  list: ListRestaurantTable(s.tables),
  get: DetailRestaurantTable(s.tables),
  createTable: CreateRestaurantTable(s.tables),
  updateTable: UpdateRestaurantTable(s.tables),
  statusTable: SetStatusRestaurantTable(s.tables),
  assignTable: AssignAreaRestaurantTable(s.tables),
  deleteTable: DeleteRestaurantTable(s.tables),
);
TableAreaController areasController(
  TableServer s,
  AppSession? Function() session,
  TableEvents events,
) => TableAreaController(
  session: session,
  events: events,
  list: ListTableArea(s.areas),
  get: DetailTableArea(s.areas),
  createArea: CreateTableArea(s.areas),
  updateArea: UpdateTableArea(s.areas),
  statusArea: SetStatusTableArea(s.areas),
  deleteArea: DeleteTableArea(s.areas),
);
TableSessionController sessionsController(
  TableServer s,
  AppSession? Function() session,
  TableEvents events,
) => TableSessionController(
  session: session,
  events: events,
  tableId: 't1',
  list: ListTableSession(s.sessions),
  get: DetailTableSession(s.sessions),
  getCurrent: CurrentTableSession(s.sessions),
  openSession: OpenTableSession(s.sessions),
  updateSession: UpdateTableSession(s.sessions),
  cancelSession: CancelTableSession(s.sessions),
);
