import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/core/auth/access_policy.dart';
import 'package:pos_saas_app/core/errors/failure.dart';
import 'package:pos_saas_app/core/network/api_error_mapper.dart';
import 'package:pos_saas_app/features/auth/domain/entities/user_role.dart';
import 'package:pos_saas_app/features/staff/data/data_sources/staff_remote_data_source.dart';
import 'package:pos_saas_app/features/subscription/data/dto/entitlement_dto.dart';
import '../../helpers/auth_fakes.dart';
import 'staff_fakes.dart';

void main() {
  test('staff permission/feature/actor matrix and protected targets', () {
    for (final role in UserRole.values) {
      for (final permission in staffPermissions.where(
        (p) => p.startsWith('STAFF_'),
      )) {
        for (final hasPermission in [true, false]) {
          for (final management in [true, false]) {
            for (final overrides in [true, false]) {
              final session = makeAppSession(
                role: role,
                permissions: hasPermission ? {permission} : {},
                features: {
                  if (management) 'STAFF_MANAGEMENT',
                  if (overrides) 'STAFF_PERMISSION',
                },
              );
              final allowed =
                  (role == UserRole.owner || role == UserRole.manager) &&
                  hasPermission &&
                  management &&
                  (permission != 'STAFF_PERMISSION_MANAGE' || overrides);
              expect(
                AccessPolicy.canStaff(session, permission),
                allowed,
                reason:
                    '$role $permission $hasPermission $management $overrides',
              );
              expect(
                AccessPolicy.canManageStaff(
                  session,
                  permission,
                  'user-1',
                  'WAITER',
                ),
                false,
              );
              for (final target in ['OWNER', 'SUPER_ADMIN', 'CUSTOM']) {
                expect(
                  AccessPolicy.canManageStaff(
                    session,
                    permission,
                    'target',
                    target,
                  ),
                  false,
                );
              }
              expect(
                AccessPolicy.canManageStaff(
                  session,
                  permission,
                  'target',
                  'MANAGER',
                ),
                allowed && role == UserRole.owner,
              );
              expect(
                AccessPolicy.canManageStaff(
                  session,
                  permission,
                  'target',
                  'WAITER',
                ),
                allowed,
              );
            }
          }
        }
      }
    }
    expect(AccessPolicy.canOpenRoute(staffSession(), '/app/staff'), true);
    expect(AccessPolicy.canOpenRoute(makeAppSession(), '/app/staff'), false);
  });
  test(
    'maxStaff is nullable and comes from entitlement root, not package/features',
    () {
      final dto = EntitlementDto.fromJson({
        'status': 'ACTIVE',
        'packageCode': 'BASIC',
        'maxStaff': null,
        'features': [
          {
            'code': 'STAFF_MANAGEMENT',
            'limits': {'maxStaff': 3},
          },
        ],
      });
      expect(dto.toDomain().maxStaff, isNull);
      expect(EntitlementDto.fromJson({'maxStaff': 10}).toDomain().maxStaff, 10);
    },
  );
  test('all staff error codes retain correct category and field errors', () {
    final groups = <FailureType, List<String>>{
      FailureType.validation: [
        'VALIDATION_ERROR',
        'EMPTY_UPDATE_REQUEST',
        'STAFF_ROLE_NOT_ALLOWED',
        'PERMISSION_EFFECT_CONFLICT',
        'PERMISSION_NOT_FOUND',
        'PERMISSION_NOT_ASSIGNABLE',
      ],
      FailureType.unauthorized: ['UNAUTHORIZED', 'ACCOUNT_INACTIVE'],
      FailureType.forbidden: [
        'FORBIDDEN',
        'TENANT_ACCESS_DENIED',
        'OWNER_ACCOUNT_PROTECTED',
        'STAFF_SELF_MANAGEMENT_NOT_ALLOWED',
        'STAFF_TARGET_FORBIDDEN',
        'PERMISSION_ESCALATION_NOT_ALLOWED',
      ],
      FailureType.subscriptionNotActive: ['SUBSCRIPTION_NOT_ACTIVE'],
      FailureType.featureNotEntitled: ['FEATURE_NOT_ENTITLED'],
      FailureType.notFound: ['USER_NOT_FOUND', 'ROLE_NOT_FOUND'],
      FailureType.conflict: [
        'EMAIL_EXISTS',
        'STAFF_LIMIT_REACHED',
        'INVALID_STAFF_LIMIT_CONFIG',
        'CONCURRENT_STAFF_UPDATE',
      ],
    };
    for (final group in groups.entries) {
      for (final code in group.value) {
        final request = RequestOptions(path: '/api/v1/staff');
        final failure = ApiErrorMapper.fromException(
          DioException(
            requestOptions: request,
            response: Response(
              requestOptions: request,
              data: {
                'success': false,
                'code': code,
                'message': 'server message',
                'fieldErrors': {'email': 'Invalid'},
              },
            ),
          ),
        );
        expect(failure.type, group.key, reason: code);
        expect(failure.code, code);
        expect(failure.fieldErrors, {'email': 'Invalid'});
      }
    }
  });
  test(
    'Dio contract for list/create/partial patch/status and replacement PUT',
    () async {
      final dio = Dio();
      final requests = <RequestOptions>[];
      final staff = {
        'id': 'A',
        'name': 'Alice',
        'email': 'alice@example.com',
        'phone': null,
        'active': true,
        'role': {'id': 'role', 'code': 'WAITER', 'name': 'Waiter'},
        'createdAt': '2026-01-01T00:00:00Z',
        'updatedAt': '2026-01-01T00:00:00Z',
        'lastLoginAt': null,
      };
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests.add(options);
            Object data = staff;
            if (options.path.endsWith('/permissions')) {
              data = {
                'staffId': 'A',
                'roleCode': 'WAITER',
                'rolePermissions': [],
                'grants': [],
                'denies': [],
                'effectivePermissions': [],
              };
            }
            if (options.method == 'GET' && options.path == '/api/v1/staff') {
              data = {
                'content': [staff],
                'page': 1,
                'size': 10,
                'totalElements': 11,
                'totalPages': 2,
              };
            }
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: options.method == 'POST' ? 201 : 200,
                data: data,
              ),
            );
          },
        ),
      );
      final remote = StaffRemoteDataSourceImpl(dio);
      final result = await remote.getStaffList(
        query: ' alice ',
        roleCode: 'WAITER',
        active: false,
        page: 1,
        size: 10,
        sortBy: 'name',
        direction: 'asc',
      );
      expect(result.toEntity().totalElements, 11);
      expect(requests.last.queryParameters, {
        'q': 'alice',
        'roleCode': 'WAITER',
        'active': false,
        'page': 1,
        'size': 10,
        'sortBy': 'name',
        'direction': 'asc',
      });
      await remote.createStaff(
        name: 'Alice',
        email: 'alice@example.com',
        phone: '0900',
        roleCode: 'WAITER',
        initialPassword: 'Password123',
      );
      expect(requests.last.data, {
        'name': 'Alice',
        'email': 'alice@example.com',
        'phone': '0900',
        'roleCode': 'WAITER',
        'initialPassword': 'Password123',
      });
      await remote.updateStaff(staffId: 'A', phone: '');
      expect(requests.last.data, {'phone': ''});
      await remote.toggleStaffStatus(
        staffId: 'A',
        active: false,
        reason: ' Left ',
      );
      expect(requests.last.data, {'active': false, 'reason': 'Left'});
      await remote.toggleStaffStatus(
        staffId: 'A',
        active: true,
        reason: 'ignored',
      );
      expect(requests.last.data, {'active': true});
      await remote.updateStaffPermissions(
        staffId: 'A',
        grants: ['ORDER_CANCEL'],
        denies: ['ORDER_VIEW'],
      );
      expect(requests.last.method, 'PUT');
      expect(requests.last.data, {
        'grants': ['ORDER_CANCEL'],
        'denies': ['ORDER_VIEW'],
      });
      await remote.updateStaffPermissions(staffId: 'A', grants: [], denies: []);
      expect(requests.last.data, {'grants': [], 'denies': []});
      for (final request in requests) {
        expect(request.queryParameters.containsKey('restaurantId'), false);
        expect(
          (request.data as Map?)?.containsKey('restaurantId') ?? false,
          false,
        );
      }
      dio.close();
    },
  );
}
