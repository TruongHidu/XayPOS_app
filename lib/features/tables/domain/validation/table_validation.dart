import '../entities/table_inputs.dart';

abstract final class TableValidation {
  // Versions must remain exact when encoded as JSON on both native and web.
  static const _maxVersion = 9007199254740991; // 2^53 - 1

  static String? text(String? value, int max, {bool required = false}) =>
      required && (value == null || value.trim().isEmpty)
      ? 'Không được để trống.'
      : value != null && value.length > max
      ? 'Tối đa $max ký tự.'
      : null;
  static String? number(int? value, {int min = 0, int max = 2147483647}) =>
      value == null || value < min || value > max
      ? 'Nhập số nguyên từ $min đến $max.'
      : null;
  static Map<String, String> input(Object input) {
    final errors = <String, String>{};
    void add(String key, String? error) {
      if (error != null) errors[key] = error;
    }

    switch (input) {
      case CreateTableAreaInput():
        add('name', text(input.name, 100, required: true));
        add('description', text(input.description, 2000));
        add('displayOrder', number(input.displayOrder));
      case UpdateTableAreaInput():
        if (input.name != null) {
          add('name', text(input.name, 100, required: true));
        }
        add('description', text(input.description, 2000));
        if (input.displayOrder != null) {
          add('displayOrder', number(input.displayOrder));
        }
        add('expectedVersion', number(input.expectedVersion, max: _maxVersion));
      case CreateRestaurantTableInput():
        add('code', text(input.code, 50, required: true));
        add('name', text(input.name, 100, required: true));
        add('capacity', number(input.capacity, min: 1, max: 32767));
        add('displayOrder', number(input.displayOrder));
      case UpdateRestaurantTableInput():
        if (input.code != null) {
          add('code', text(input.code, 50, required: true));
        }
        if (input.name != null) {
          add('name', text(input.name, 100, required: true));
        }
        if (input.capacity != null) {
          add('capacity', number(input.capacity, min: 1, max: 32767));
        }
        if (input.displayOrder != null) {
          add('displayOrder', number(input.displayOrder));
        }
        add('expectedVersion', number(input.expectedVersion, max: _maxVersion));
      case OpenTableSessionInput():
        add('guestCount', number(input.guestCount, min: 1, max: 32767));
        add('note', text(input.note, 2000));
        add('expectedVersion', number(input.expectedVersion, max: _maxVersion));
      case UpdateTableSessionInput():
        if (input.guestCount != null) {
          add('guestCount', number(input.guestCount, min: 1, max: 32767));
        }
        add('note', text(input.note, 2000));
        add('expectedVersion', number(input.expectedVersion, max: _maxVersion));
      case TransferTableSessionInput():
        add('targetTableId', text(input.targetTableId, 100, required: true));
        add('reason', text(input.reason, 1000));
        add('expectedVersion', number(input.expectedVersion, max: _maxVersion));
    }
    return errors;
  }
}
