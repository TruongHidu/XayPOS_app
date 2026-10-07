import '../../domain/entities/table_inputs.dart';

abstract final class TableRequests {
  static Map<String, dynamic> createTableArea(CreateTableAreaInput input) => {
    'name': input.name,
    'description': input.description,
    'displayOrder': input.displayOrder,
    'active': input.active,
  };
  static Map<String, dynamic> updateTableArea(UpdateTableAreaInput input) => {
    if (input.name != null) 'name': input.name,
    if (input.description != null) 'description': input.description,
    if (input.displayOrder != null) 'displayOrder': input.displayOrder,
    'expectedVersion': input.expectedVersion,
  };
  static Map<String, dynamic> createRestaurantTable(
    CreateRestaurantTableInput input,
  ) => {
    'code': input.code,
    'name': input.name,
    'areaId': input.areaId,
    'capacity': input.capacity,
    'displayOrder': input.displayOrder,
    'status': input.status.code,
  };
  static Map<String, dynamic> updateRestaurantTable(
    UpdateRestaurantTableInput input,
  ) => {
    if (input.code != null) 'code': input.code,
    if (input.name != null) 'name': input.name,
    if (input.capacity != null) 'capacity': input.capacity,
    if (input.displayOrder != null) 'displayOrder': input.displayOrder,
    'expectedVersion': input.expectedVersion,
  };
  static Map<String, dynamic> openTableSession(OpenTableSessionInput input) => {
    'guestCount': input.guestCount,
    'note': input.note,
    'expectedVersion': input.expectedVersion,
  };
  static Map<String, dynamic> updateTableSession(
    UpdateTableSessionInput input,
  ) => {
    if (input.guestCount != null) 'guestCount': input.guestCount,
    if (input.note != null) 'note': input.note,
    'expectedVersion': input.expectedVersion,
  };
  static Map<String, dynamic> assignment(String? areaId, int version) => {
    'areaId': areaId,
    'expectedVersion': version,
  };
}
