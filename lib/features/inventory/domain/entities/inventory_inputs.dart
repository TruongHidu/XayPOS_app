import 'inventory_quantity.dart';

class CreateWarehouseInput {
  const CreateWarehouseInput({required this.code, required this.name});
  final String code, name;
  String get normalizedCode => code.trim().toUpperCase();
}

class UpdateWarehouseInput {
  const UpdateWarehouseInput({
    required this.expectedVersion,
    this.code,
    this.name,
  });
  final int expectedVersion;
  final String? code, name;
}

class SetWarehouseStatusInput {
  const SetWarehouseStatusInput(this.expectedVersion, this.active);
  final int expectedVersion;
  final bool active;
}

class WarehouseVersionInput {
  const WarehouseVersionInput(this.expectedVersion);
  final int expectedVersion;
}

class UpdateInventoryThresholdInput {
  const UpdateInventoryThresholdInput(this.expectedVersion, this.minQuantity);
  final int? expectedVersion;
  final InventoryQuantity minQuantity;
}
