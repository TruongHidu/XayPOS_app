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
}
