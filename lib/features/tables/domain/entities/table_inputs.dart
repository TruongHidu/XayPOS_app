import 'table_entities.dart';

class CreateTableAreaInput {
  const CreateTableAreaInput({
    required this.name,
    this.description,
    this.displayOrder = 0,
    this.active = true,
  });
  final String name;
  final String? description;
  final int displayOrder;
  final bool active;
}

class UpdateTableAreaInput {
  const UpdateTableAreaInput({
    this.name,
    this.description,
    this.displayOrder,
    required this.expectedVersion,
  });
  final String? name;
  final String? description;
  final int? displayOrder;
  final int expectedVersion;
  bool get isEmpty =>
      name == null && description == null && displayOrder == null;
}

class CreateRestaurantTableInput {
  const CreateRestaurantTableInput({
    required this.code,
    required this.name,
    this.areaId,
    this.capacity = 4,
    this.displayOrder = 0,
    this.status = TableStatus.available,
  });
  final String code;
  final String name;
  final String? areaId;
  final int capacity;
  final int displayOrder;
  final TableStatus status;
}

class UpdateRestaurantTableInput {
  const UpdateRestaurantTableInput({
    this.code,
    this.name,
    this.capacity,
    this.displayOrder,
    required this.expectedVersion,
  });
  final String? code;
  final String? name;
  final int? capacity;
  final int? displayOrder;
  final int expectedVersion;
  bool get isEmpty =>
      code == null && name == null && capacity == null && displayOrder == null;
}

class OpenTableSessionInput {
  const OpenTableSessionInput({
    this.guestCount = 1,
    this.note,
    required this.expectedVersion,
  });
  final int guestCount;
  final String? note;
  final int expectedVersion;
}

class UpdateTableSessionInput {
  const UpdateTableSessionInput({
    this.guestCount,
    this.note,
    required this.expectedVersion,
  });
  final int? guestCount;
  final String? note;
  final int expectedVersion;
  bool get isEmpty => guestCount == null && note == null;
}
