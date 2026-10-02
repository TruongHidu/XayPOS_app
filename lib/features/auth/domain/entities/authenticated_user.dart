import 'user_role.dart';

class AuthenticatedUser {
  const AuthenticatedUser({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.permissions,
    this.restaurantId,
    this.restaurantCode,
    this.restaurantName,
    this.phone,
  });

  final String id;
  final String? restaurantId;
  final String? restaurantCode;
  final String? restaurantName;
  final String name;
  final String email;
  final String? phone;
  final UserRole role;
  final Set<String> permissions;
}
