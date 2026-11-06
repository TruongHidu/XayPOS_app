enum UserRole {
  superAdmin,
  owner,
  manager,
  waiter,
  kitchen,
  cashier,
  unsupported;

  factory UserRole.fromJson(String? value) {
    return switch (value?.toUpperCase()) {
      'SUPER_ADMIN' => UserRole.superAdmin,
      'OWNER' => UserRole.owner,
      'MANAGER' => UserRole.manager,
      'WAITER' => UserRole.waiter,
      'KITCHEN' => UserRole.kitchen,
      'CASHIER' => UserRole.cashier,
      _ => UserRole.unsupported,
    };
  }

  /// Vietnamese name shown to people.
  String get label => switch (this) {
    UserRole.cashier => 'Thu ngân',
    UserRole.owner => 'Chủ nhà hàng',
    UserRole.manager => 'Quản lý',
    UserRole.waiter => 'Phục vụ',
    UserRole.kitchen => 'Bếp',
    UserRole.superAdmin => 'Super Admin',
    UserRole.unsupported => name,
  };
}
