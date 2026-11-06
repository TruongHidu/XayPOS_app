class RestaurantProfile {
  const RestaurantProfile({
    required this.id,
    required this.code,
    required this.name,
    this.legalName,
    this.phone,
    this.address,
    this.timezone,
    this.currencyCode,
    this.status,
  });

  final String id;
  final String code;
  final String name;
  final String? legalName;
  final String? phone;
  final String? address;
  final String? timezone;
  final String? currencyCode;
  final String? status;
}

/// Editable profile fields; an empty string clears an optional field.
class RestaurantProfileUpdate {
  const RestaurantProfileUpdate({
    required this.name,
    required this.legalName,
    required this.phone,
    required this.address,
  });

  final String name;
  final String legalName;
  final String phone;
  final String address;

  Map<String, dynamic> toJson() => {
    'name': name.trim(),
    'legalName': legalName.trim(),
    'phone': phone.trim(),
    'address': address.trim(),
  };
}
