import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/app/providers.dart';
import 'package:pos_saas_app/app/router/app_router.dart';
import 'package:pos_saas_app/app/router/app_routes.dart';
import 'package:pos_saas_app/app/theme/app_theme.dart';
import 'package:pos_saas_app/core/errors/failure.dart';
import 'package:pos_saas_app/core/network/binary_download.dart';
import 'package:pos_saas_app/core/platform/file_exporter.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/features/auth/domain/entities/login_credentials.dart';
import 'package:pos_saas_app/features/auth/domain/entities/user_role.dart';
import 'package:pos_saas_app/features/settings/domain/entities/public_menu_link.dart';
import 'package:pos_saas_app/features/settings/domain/entities/restaurant_profile.dart';
import 'package:pos_saas_app/features/settings/domain/entities/transfer_account.dart';
import 'package:pos_saas_app/features/settings/domain/repositories/settings_repository.dart';
import 'package:pos_saas_app/features/settings/domain/repositories/transfer_account_repository.dart';
import 'package:pos_saas_app/features/settings/presentation/providers/settings_providers.dart';
import 'package:pos_saas_app/features/settings/presentation/screens/settings_screen.dart';
import 'package:pos_saas_app/features/subscription/domain/entities/entitlement.dart';
import 'package:pos_saas_app/features/subscription/domain/entities/package_feature.dart';

import '../../helpers/auth_fakes.dart';
import '../../helpers/qr_fakes.dart';
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
  PublicMenuLink? link;
  final calls = <String>[];

  PublicMenuLink _link(String token) => PublicMenuLink(
    menuToken: token,
    menuPath: '/menu/$token',
    menuUrl: 'https://pos.example.com/menu/$token',
  );

  @override
  Future<Result<PublicMenuLink?>> getMenuLink() async {
    calls.add('get');
    return Success(link);
  }

  @override
  Future<Result<PublicMenuLink>> createMenuLink() async {
    calls.add('create');
    return Success(link = _link('AAAA'));
  }

  @override
  Future<Result<PublicMenuLink>> rotateMenuLink() async {
    calls.add('rotate');
    if (link == null) {
      return const Error(
        Failure(
          type: FailureType.notFound,
          code: 'PUBLIC_MENU_LINK_NOT_INITIALIZED',
          message: 'Nhà hàng chưa tạo link menu cho khách.',
        ),
      );
    }
    return Success(link = _link('BBBB'));
  }

  @override
  Future<Result<DownloadedFile>> menuLinkQrCard() async {
    calls.add('card:${link?.menuToken}');
    return Success(
      DownloadedFile(
        bytes: tinyPng,
        fileName: 'the-qr-menu.png',
        mimeType: 'image/png',
      ),
    );
  }

  @override
  Future<Result<DownloadedFile>> menuLinkQrImage() async {
    calls.add('image:${link?.menuToken}');
    return Success(
      DownloadedFile(
        bytes: tinyPng,
        fileName: 'qr-menu.png',
        mimeType: 'image/png',
      ),
    );
  }

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

class _FakeTransferAccounts implements TransferAccountRepository {
  TransferAccount? account;
  final saved = <TransferAccountDraft>[];
  var removes = 0;

  @override
  Future<Result<TransferAccount?>> get() async => Success(account);

  @override
  Future<Result<TransferAccount>> save(TransferAccountDraft draft) async {
    saved.add(draft);
    final json = draft.toJson();
    return Success(
      account = TransferAccount(
        bankBin: json['bankBin'] as String,
        accountNumber: json['accountNumber'] as String,
        accountName: json['accountName'] as String,
        updatedAt: DateTime(2026, 11, 11),
      ),
    );
  }

  @override
  Future<Result<void>> remove() async {
    removes++;
    account = null;
    return const Success(null);
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
  _FakeTransferAccounts? transferAccounts,
  UserRole role = UserRole.owner,
  Set<String> permissions = _ownerPermissions,
  String location = AppRoutes.settings,
  ({String privacy, String terms}) links = (
    privacy: 'https://xaypos.test/privacy',
    terms: '',
  ),
  List<Uri>? opened,
  FakeFileExporter? exporter,
  Size size = const Size(1200, 2200),
}) async {
  tester.view.physicalSize = size;
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
      transferAccountRepositoryProvider.overrideWithValue(
        transferAccounts ?? _FakeTransferAccounts(),
      ),
      appVersionProvider.overrideWith((ref) async => '1.0.0 (1)'),
      legalLinksProvider.overrideWithValue(links),
      externalLinkOpenerProvider.overrideWithValue((uri) async {
        opened?.add(uri);
        return true;
      }),
      fileExporterProvider.overrideWithValue(exporter ?? FakeFileExporter()),
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

/// Scrolling Cài đặt to the end and back on a phone must not refetch anything.
Future<void> _scrollThrough(WidgetTester tester) async {
  final list = find.descendant(
    of: find.byType(SettingsScreen),
    matching: find.byType(Scrollable),
  );
  for (final dy in [-3000.0, 3000.0, -3000.0, 3000.0]) {
    await tester.drag(list.first, Offset(0, dy));
    await tester.pumpAndSettle();
  }
}

Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  // Lay out the scrolled list before hit-testing the new position.
  await tester.pump();
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

  testWidgets('owner creates, saves and rotates the takeaway menu QR', (
    tester,
  ) async {
    final exporter = FakeFileExporter();
    final (_, settings) = await _pump(tester, exporter: exporter);

    expect(_inSettings('QR menu mang đi'), findsOneWidget);
    expect(find.byTooltip('Đổi link menu'), findsNothing);
    await _tap(tester, find.text('Tạo link menu'));
    expect(settings.calls, ['get', 'create', 'get', 'card:AAAA']);
    expect(find.text('Đã tạo link menu.'), findsOneWidget);
    expect(find.text('https://pos.example.com/menu/AAAA'), findsOneWidget);

    await _tap(tester, find.text('Tải thẻ in'));
    expect(exporter.exported.single.fileName, 'the-qr-menu.png');

    // Rotating asks first, then fetches a card for the new token.
    await _tap(tester, find.byTooltip('Đổi link menu'));
    expect(find.text('Đổi link menu?'), findsOneWidget);
    await _tap(tester, find.text('Huỷ'));
    expect(settings.calls, isNot(contains('rotate')));
    await _tap(tester, find.byTooltip('Đổi link menu'));
    await _tap(tester, find.widgetWithText(FilledButton, 'Đổi link'));
    expect(settings.calls.skip(4), ['rotate', 'get', 'card:BBBB']);
    expect(find.text('https://pos.example.com/menu/BBBB'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('menu QR needs RESTAURANT_PROFILE_UPDATE', (tester) async {
    final (_, settings) = await _pump(
      tester,
      role: UserRole.manager,
      permissions: const {
        'MENU_VIEW',
        'RESTAURANT_PROFILE_VIEW',
        'SUBSCRIPTION_VIEW',
      },
    );

    expect(_inSettings('Nhà hàng'), findsOneWidget);
    expect(_inSettings('QR menu mang đi'), findsNothing);
    expect(settings.calls, isEmpty);
  });

  testWidgets('owner adds a transfer account with a normalized body', (
    tester,
  ) async {
    final accounts = _FakeTransferAccounts();
    await _pump(tester, transferAccounts: accounts);

    expect(_inSettings('Tài khoản nhận chuyển khoản'), findsOneWidget);
    await _tap(tester, find.text('Thêm tài khoản'));
    await _tap(tester, find.text('Lưu'));
    expect(find.text('Hãy chọn ngân hàng.'), findsOneWidget);
    expect(find.text('Nhập số tài khoản.'), findsOneWidget);
    expect(accounts.saved, isEmpty);

    // The picker searches without diacritics.
    await _tap(tester, find.byKey(const ValueKey('transfer-account-bank')));
    await tester.enterText(
      find.byKey(const ValueKey('bank-search')),
      'ngoai thuong',
    );
    await tester.pumpAndSettle();
    expect(find.text('Techcombank'), findsNothing);
    await _tap(tester, find.text('Vietcombank'));
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Số tài khoản'),
      '0123 456 789',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Tên chủ tài khoản'),
      'Nguyễn Văn Đức',
    );
    await tester.pumpAndSettle();
    expect(find.text('Sẽ lưu là: NGUYEN VAN DUC'), findsOneWidget);
    await _tap(tester, find.text('Lưu'));

    expect(accounts.saved.single.toJson(), {
      'bankBin': '970436',
      'accountNumber': '0123456789',
      'accountName': 'NGUYEN VAN DUC',
    });
    expect(find.text('Đã lưu tài khoản nhận chuyển khoản.'), findsOneWidget);
    expect(
      find.text('Vietcombank · Ngân hàng TMCP Ngoại thương Việt Nam'),
      findsOneWidget,
    );
    expect(find.text('0123456789'), findsOneWidget);
    expect(find.text('NGUYEN VAN DUC'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('removing the transfer account asks first', (tester) async {
    final accounts = _FakeTransferAccounts()
      ..account = const TransferAccount(
        bankBin: '970422',
        accountNumber: '9999',
        accountName: 'QUAN PHO',
      );
    await _pump(tester, transferAccounts: accounts);

    expect(find.text('9999'), findsOneWidget);
    await _tap(tester, find.text('Gỡ tài khoản'));
    expect(find.text('Gỡ tài khoản nhận chuyển khoản?'), findsOneWidget);
    await _tap(tester, find.text('Huỷ'));
    expect(accounts.removes, 0);
    expect(find.text('9999'), findsOneWidget);

    await _tap(tester, find.text('Gỡ tài khoản'));
    await _tap(tester, find.widgetWithText(FilledButton, 'Gỡ tài khoản'));
    expect(accounts.removes, 1);
    expect(find.text('Đã gỡ tài khoản nhận chuyển khoản.'), findsOneWidget);
    expect(find.text('9999'), findsNothing);
    expect(find.text('Thêm tài khoản'), findsOneWidget);
  });

  testWidgets('transfer account is read-only without profile update right', (
    tester,
  ) async {
    final accounts = _FakeTransferAccounts()
      ..account = const TransferAccount(
        bankBin: '970999',
        accountNumber: '9999',
        accountName: 'QUAN PHO',
      );
    final (container, _) = await _pump(
      tester,
      role: UserRole.manager,
      permissions: const {'MENU_VIEW', 'RESTAURANT_PROFILE_VIEW'},
      transferAccounts: accounts,
    );

    expect(_inSettings('Tài khoản nhận chuyển khoản'), findsOneWidget);
    expect(find.text('BIN 970999'), findsOneWidget);
    expect(find.byTooltip('Sửa tài khoản nhận chuyển khoản'), findsNothing);
    expect(find.text('Gỡ tài khoản'), findsNothing);

    accounts.account = null;
    container.invalidate(transferAccountProvider);
    await tester.pumpAndSettle();
    expect(
      find.text('Nhà hàng chưa cài tài khoản nhận chuyển khoản.'),
      findsOneWidget,
    );
    expect(find.text('Thêm tài khoản'), findsNothing);
    expect(accounts.saved, isEmpty);
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

  testWidgets('scrolling a phone-sized Cài đặt never reloads its sections', (
    tester,
  ) async {
    final (_, settings) = await _pump(tester, size: const Size(400, 700));
    final before = List.of(settings.calls);
    expect(before, isNotEmpty);
    await _scrollThrough(tester);
    expect(settings.calls, before);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
