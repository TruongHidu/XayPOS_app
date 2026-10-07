import 'package:dio/dio.dart';
import 'package:pos_saas_app/features/tables/data/data_sources/tables_remote_data_source.dart';
import 'package:pos_saas_app/features/tables/data/repositories/table_area_repository_impl.dart';
import 'package:pos_saas_app/features/tables/data/repositories/restaurant_table_repository_impl.dart';
import 'package:pos_saas_app/features/tables/data/repositories/table_session_repository_impl.dart';

const tablePermissions = {
  'TABLE_VIEW',
  'TABLE_CREATE',
  'TABLE_UPDATE',
  'TABLE_OPEN',
  'TABLE_CLOSE',
};
Map<String, dynamic> areaJson({
  String id = 'a1',
  int version = 7,
  bool active = true,
}) => {
  'id': id,
  'name': 'Floor 1',
  'description': null,
  'displayOrder': 0,
  'active': active,
  'version': version,
  'createdAt': '2026-10-06T03:00:00Z',
  'updatedAt': '2026-10-06T10:00:00+07:00',
};
Map<String, dynamic> tableJson({
  String id = 't1',
  int version = 9,
  bool occupied = false,
  bool canOpen = true,
}) => {
  'id': id,
  'code': 'B01',
  'name': 'Window table',
  'capacity': 4,
  'displayOrder': 0,
  'status': 'AVAILABLE',
  'area': {'id': 'a1', 'name': 'Floor 1', 'active': true},
  'occupied': occupied,
  'canOpen': canOpen,
  'currentSession': occupied
      ? {
          'id': 's1',
          'sessionCode': 'TS-1',
          'guestCount': 6,
          'openedAt': '2026-10-06T03:00:00Z',
          'version': 3,
        }
      : null,
  'version': version,
  'createdAt': '2026-10-06T03:00:00Z',
  'updatedAt': '2026-10-06T03:00:00Z',
};
Map<String, dynamic> sessionJson({
  String id = 's1',
  int version = 3,
  String status = 'OPEN',
}) => {
  'id': id,
  'sessionCode': 'TS-1',
  'tableId': 't1',
  'tableCode': 'B01',
  'tableName': 'Window table',
  'status': status,
  'guestCount': 6,
  'note': null,
  'openedBy': 'u1',
  'openedAt': '2026-10-06T03:00:00Z',
  'closedBy': null,
  'closedAt': null,
  'cancelReason': null,
  'version': version,
  'createdAt': '2026-10-06T03:00:00Z',
  'updatedAt': '2026-10-06T03:00:00Z',
};
Map<String, dynamic> qrJson({int version = 9}) => {
  'tableId': 't1',
  'qrToken': 'secret',
  'qrPath': '/menu/qr/secret',
  'version': version,
};
Map<String, dynamic> pageJson(
  List<Object> content, {
  int page = 0,
  int pages = 1,
  int? total,
}) => {
  'content': content,
  'page': page,
  'size': 20,
  'totalPages': pages,
  'totalElements': total ?? content.length,
};

class TableServer {
  final dio = Dio(BaseOptions(baseUrl: 'https://tables.invalid'));
  final requests = <RequestOptions>[];
  late final remote = TablesRemoteDataSource(dio);
  late final areas = TableAreaRepositoryImpl(remote);
  late final tables = RestaurantTableRepositoryImpl(remote);
  late final sessions = TableSessionRepositoryImpl(remote);
  Future<Response<dynamic>> Function(RequestOptions)? respond;
  bool empty = false;
  Map<String, dynamic> table = tableJson(),
      area = areaJson(),
      session = sessionJson();
  TableServer() {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (r, h) async {
          requests.add(r);
          try {
            h.resolve(respond != null ? await respond!(r) : response(r));
          } on DioException catch (e) {
            h.reject(e);
          }
        },
      ),
    );
  }
  Response<dynamic> response(RequestOptions r) {
    final path = r.path;
    Object? data;
    var status = 200;
    if (r.method == 'DELETE' || path.endsWith('/current-session')) {
      status = 204;
    } else if (path.endsWith('/qr') || path.endsWith('/qr/rotate')) {
      data = qrJson(version: path.endsWith('rotate') ? 10 : 9);
    } else if (r.method == 'GET' &&
        const [
          '/api/v1/tables',
          '/api/v1/table-areas',
          '/api/v1/table-sessions',
        ].contains(path)) {
      data = pageJson(
        empty
            ? []
            : [
                path.endsWith('table-areas')
                    ? area
                    : path.endsWith('table-sessions')
                    ? session
                    : table,
              ],
        page: r.queryParameters['page'] as int? ?? 0,
      );
    } else {
      data = path.contains('table-areas')
          ? area
          : path.contains('table-sessions') || path.endsWith('/sessions')
          ? session
          : table;
    }
    return Response(requestOptions: r, statusCode: status, data: data);
  }

  void close() => dio.close(force: true);
}
