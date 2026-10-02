import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/core/auth/access_policy.dart';
import 'package:pos_saas_app/features/auth/domain/entities/user_role.dart';

import '../../helpers/auth_fakes.dart';

void main() {
  test('missing permission blocks a protected route', () {
    final session = makeAppSession(
      role: UserRole.waiter,
      permissions: const {},
      features: {'TABLE_MANAGEMENT'},
    );
    expect(AccessPolicy.canOpenRoute(session, '/app/home'), isFalse);
    expect(AccessPolicy.initialRouteFor(session), '/no-accessible-feature');
  });

  test('missing feature routes kitchen to no accessible feature', () {
    final session = makeAppSession(
      role: UserRole.kitchen,
      permissions: {'KITCHEN_VIEW'},
      features: const {},
    );
    expect(AccessPolicy.canOpenRoute(session, '/kitchen/orders'), isFalse);
    expect(AccessPolicy.initialRouteFor(session), '/no-accessible-feature');
  });

  test('deep link is accepted only when access policy allows it', () {
    final allowed = makeAppSession(
      role: UserRole.waiter,
      permissions: {'TABLE_VIEW'},
      features: {'TABLE_MANAGEMENT'},
    );
    final denied = makeAppSession(
      role: UserRole.waiter,
      permissions: {'ORDER_VIEW'},
      features: const {},
    );

    expect(AccessPolicy.canOpenRoute(allowed, '/app/home'), isTrue);
    expect(AccessPolicy.canOpenRoute(denied, '/app/home'), isFalse);
  });
}
