import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/app/providers.dart';
import 'package:pos_saas_app/app/router/app_router.dart';
import 'package:pos_saas_app/app/router/app_routes.dart';
import 'package:pos_saas_app/app/theme/app_theme.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/features/auth/domain/entities/login_credentials.dart';
import 'package:pos_saas_app/features/auth/domain/entities/user_role.dart';
import 'package:pos_saas_app/features/settings/domain/entities/restaurant_profile.dart';
import 'package:pos_saas_app/features/settings/domain/repositories/settings_repository.dart';
import 'package:pos_saas_app/features/settings/presentation/providers/settings_providers.dart';
import 'package:pos_saas_app/features/settings/presentation/screens/settings_screen.dart';
import 'package:pos_saas_app/features/subscription/domain/entities/entitlement.dart';
import 'package:pos_saas_app/features/subscription/domain/entities/package_feature.dart';

import '../../helpers/auth_fakes.dart';
import '../../helpers/realtime_fakes.dart';

class _FakeSettings implements SettingsRepository {
  RestaurantProfile profile = const RestaurantProfile(
    id: 'r-1',
    code: 'NH01',
    name: 'Quán Phở',
    phone: '0909123456',
    address: '1 Lê Lợi',
    timezone: 'Asia/Ho_Chi_Minh',
    currencyCode: 'VND',
    status: 'ACTIVE',
  );
  final updates = <RestaurantProfileUpdate>[];

  @override
  Future<Result<RestaurantProfile>> getRestaurant() async => Success(profile);

  @override
  Future<Result<RestaurantProfile>> updateRestaurant(
    RestaurantProfileUpdate update,
  ) async {
    updates.add(update);
    profile = RestaurantProfile(
      id: profile.id,
      code: profile.code,
      name: update.name.trim(),
      phone: update.phone,
      address: update.address,
      status: profile.status,
    );
    return Success(profile);
  }
}

const _ownerPermissions = {
  'MENU_VIEW',
  'RESTAURANT_PROFILE_VIEW',
  'RESTAURANT_PROFILE_UPDATE',
  'SUBSCRIPTION_VIEW',
};

Future<(ProviderContainer, _FakeSettings)> _pump(
  WidgetTester tester, {
  UserRole role = UserRole.owner,
  Set<String> permissions = _ownerPermissions,
  String location = AppRoutes.settings,
  ({String privacy, String terms}) links = (
    privacy: 'https://xaypos.test/privacy',
    terms: '',
  ),
  List<Uri>? opened,
}) async {
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final entitlement = FakeEntitlementRepository()
    ..result = Success(
      Entitlement(
        subscriptionId: 'sub-1',
        packageCode: 'PRO',
        packageName: 'Gói Chuyên nghiệp',
        status: SubscriptionStatus.active,
        startAt: DateTime(2026, 10, 1),
        endAt: DateTime(2026, 12, 1),
        daysRemaining: 26,
        maxStaff: 10,
        features: const [
          PackageFeature(code: 'MENU_MANAGEMENT'),
          PackageFeature(code: 'LOW_STOCK_ALERT'),
          PackageFeature(code: 'NEW_FEATURE'),
        ],
      ),
    );
  final auth = makeController(
    authRepository: FakeAuthRepository()
      ..loginResult = Success(
        makeAuthSession(role: role, permissions: permissions),
      ),
    entitlementRepository: entitlement,
  );
  await auth.login(
    const LoginCredentials(email: 'owner@example.com', password: 'password'),
  );
  final settings = _FakeSettings();
  final container = ProviderContainer(
    overrides: [
      authControllerProvider.overrideWith((ref) => auth),
      entitlementRepositoryProvider.overrideWithValue(entitlement),
      settingsRepositoryProvider.overrideWithValue(settings),
      appVersionProvider.overrideWith((ref) async => '1.0.0 (1)'),
      legalLinksProvider.overrideWithValue(links),
      externalLinkOpenerProvider.overrideWithValue((uri) async {
        opened?.add(uri);
        return true;
      }),
      realtimePreferenceStorageProvider.overrideWithValue(
        MemoryRealtimePreferenceStorage(false),
      ),
    ],
  );
  addTearDown(container.dispose);
  final router = container.read(appRouterProvider)..go(location);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return (container, settings);
}

/// Text inside Cài đặt; the sidebar header also shows the restaurant name.
Finder _inSettings(String text) =>
    find.descendant(of: find.byType(SettingsScreen), matching: find.text(text));

Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('owner sees restaurant, package, account and app sections', (
    tester,
  ) async {
    final opened = <Uri>[];
    await _pump(tester, opened: opened);

    expect(find.byType(SettingsScreen), findsOneWidget);
    for (final title in [
      'Nhà hàng',
      'Gói dịch vụ',
      'Tài khoản của tôi',
      'Ứng dụng',
    ]) {
      expect(_inSettings(title), findsOneWidget);
    }
    expect(find.text('Quán Phở'), findsOneWidget);
    expect(find.text('NH01'), findsOneWidget);
    expect(find.text('Gói Chuyên nghiệp'), findsOneWidget);
    expect(find.text('26 ngày'), findsOneWidget);
    expect(find.text('01/12/2026'), findsOneWidget);
    expect(find.text('Quản lý thực đơn'), findsOneWidget);
    expect(find.text('Cảnh báo tồn thấp'), findsOneWidget);
    expect(find.text('NEW_FEATURE'), findsOneWidget);
    // The app never sells or prices a package.
    expect(find.textContaining('Nâng cấp'), findsNothing);
    expect(find.textContaining('₫'), findsNothing);
    expect(find.text('Chủ nhà hàng'), findsWidgets);
    expect(find.text('1.0.0 (1)'), findsOneWidget);

    expect(find.text('Điều khoản sử dụng'), findsNothing);
    await _tap(tester, find.text('Chính sách quyền riêng tư'));
    expect(opened, [Uri.parse('https://xaypos.test/privacy')]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('owner edits the restaurant profile', (tester) async {
    final (_, settings) = await _pump(tester);

    await _tap(tester, find.byTooltip('Sửa thông tin nhà hàng'));
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Tên nhà hàng'),
      'X',
    );
    await _tap(tester, find.text('Lưu'));
    expect(find.text('Tên cần ít nhất 2 ký tự.'), findsOneWidget);
    expect(settings.updates, isEmpty);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Tên nhà hàng'),
      'Quán Bún',
    );
    await _tap(tester, find.text('Lưu'));
    expect(settings.updates.single.name, 'Quán Bún');
    expect(find.text('Đã lưu thông tin nhà hàng.'), findsOneWidget);
    expect(find.text('Quán Bún'), findsOneWidget);
  });

  testWidgets('staff without permissions keep only their own sections', (
    tester,
  ) async {
    await _pump(
      tester,
      role: UserRole.waiter,
      permissions: const {'MENU_VIEW'},
    );

    expect(_inSettings('Nhà hàng'), findsNothing);
    expect(_inSettings('Gói dịch vụ'), findsNothing);
    expect(_inSettings('Tài khoản của tôi'), findsOneWidget);
    expect(_inSettings('Ứng dụng'), findsOneWidget);
    expect(find.text('Phục vụ'), findsWidgets);
    expect(find.text('Xóa tài khoản'), findsNothing);
  });

  testWidgets('Cài đặt is in the menu, Tổng quan is not', (tester) async {
    final (container, _) = await _pump(tester);

    await _tap(tester, find.byTooltip('Menu'));
    expect(find.text('Tổng quan'), findsNothing);
    expect(find.text('Cài đặt nhà hàng'), findsNothing);
    expect(find.widgetWithText(ListTile, 'Cài đặt'), findsOneWidget);
    expect(
      container.read(appRouterProvider).routeInformationProvider.value.uri.path,
      AppRoutes.settings,
    );
  });
}
