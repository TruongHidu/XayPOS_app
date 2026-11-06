import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:pos_saas_app/app/providers.dart';
import 'package:pos_saas_app/core/errors/failure.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/features/auth/domain/entities/login_credentials.dart';
import 'package:pos_saas_app/features/menu/domain/entities/menu_item.dart';
import 'package:pos_saas_app/features/menu/presentation/providers/menu_image_picker.dart';
import 'package:pos_saas_app/features/menu/presentation/widgets/menu_dialogs.dart';
import 'package:pos_saas_app/features/menu/presentation/widgets/menu_item_form.dart';
import 'menu_fakes.dart' hide group;
import '../../helpers/auth_fakes.dart';

class _FakeCamera implements MenuCameraPermission {
  CameraAccess access = CameraAccess.granted;
  int requests = 0;
  int settingsOpened = 0;

  @override
  Future<CameraAccess> request() async {
    requests++;
    return access;
  }

  @override
  Future<bool> openSettings() async {
    settingsOpened++;
    return true;
  }
}

final _photo = PickedMenuImage(Uint8List.fromList([1, 2, 3]), 'mon.jpg');
const _gallery = ValueKey('menu-image-gallery');
const _camera = ValueKey('menu-image-camera');
const _clear = ValueKey('menu-image-clear');

void main() {
  late FakeMenuItems items;
  late _FakeCamera camera;
  setUp(() {
    items = FakeMenuItems();
    camera = _FakeCamera();
  });

  Future<void> pumpForm(
    WidgetTester tester, {
    MenuItem? initial,
    MenuImagePicker? picker,
  }) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final auth = makeController(
      authRepository: FakeAuthRepository()
        ..loginResult = Success(makeAuthSession(permissions: menuPermissions)),
    );
    await auth.login(
      const LoginCredentials(email: 'a@b.com', password: 'password'),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith((ref) => auth),
          menuItemRepositoryProvider.overrideWithValue(items),
          menuGroupRepositoryProvider.overrideWithValue(FakeMenuGroups()),
          menuImagePickerProvider.overrideWithValue(
            picker ?? (_) async => _photo,
          ),
          menuCameraPermissionProvider.overrideWithValue(camera),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, child) => TextButton(
                onPressed: () => showMenuDialog<void>(
                  context,
                  ref,
                  permission: initial == null ? 'MENU_CREATE' : 'MENU_UPDATE',
                  child: MenuItemForm(initial: initial),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  Future<void> fillRequired(WidgetTester tester) async {
    await tester.enterText(find.byKey(const ValueKey('menu-item-name')), 'Trà');
    await tester.enterText(
      find.byKey(const ValueKey('menu-item-baseUnit')),
      'ly',
    );
    await tester.enterText(
      find.byKey(const ValueKey('menu-item-salePrice')),
      '35000',
    );
    await tester.pump();
  }

  FilledButton submit(WidgetTester tester, String label) =>
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, label));

  testWidgets('a chosen photo is uploaded only when the item is saved', (
    tester,
  ) async {
    await pumpForm(tester);
    await fillRequired(tester);
    await tester.tap(find.byKey(_gallery));
    await tester.pumpAndSettle();
    expect(find.text('Ảnh sẽ được tải lên khi lưu món.'), findsOneWidget);
    expect(items.uploadedImages, isEmpty);

    await tester.tap(find.widgetWithText(FilledButton, 'Tạo món'));
    await tester.pumpAndSettle();
    expect(items.uploadedImages, ['mon.jpg']);
    expect(items.lastCreate?.imageUrl, 'https://cdn.test/mon.jpg');
  });

  testWidgets('closing the form leaves nothing on the server', (tester) async {
    await pumpForm(tester);
    await tester.tap(find.byKey(_gallery));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Đóng'));
    await tester.pumpAndSettle();
    expect(find.byType(MenuItemForm), findsNothing);
    expect(items.uploadedImages, isEmpty);
  });

  testWidgets('only the last chosen photo is uploaded', (tester) async {
    final photos = [
      PickedMenuImage(_photo.bytes, 'dau.jpg'),
      PickedMenuImage(_photo.bytes, 'sau.jpg'),
    ];
    var picks = 0;
    await pumpForm(tester, picker: (_) async => photos[picks++]);
    await fillRequired(tester);
    await tester.tap(find.byKey(_gallery));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(_gallery));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Tạo món'));
    await tester.pumpAndSettle();
    expect(items.uploadedImages, ['sau.jpg']);
  });

  testWidgets('each button asks for its own source', (tester) async {
    final sources = <ImageSource>[];
    await pumpForm(
      tester,
      picker: (source) async {
        sources.add(source);
        return null;
      },
    );
    await tester.tap(find.byKey(_camera));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(_gallery));
    await tester.pumpAndSettle();
    expect(sources, [ImageSource.camera, ImageSource.gallery]);
  });

  testWidgets('backing out of the picker uploads nothing', (tester) async {
    await pumpForm(tester, picker: (_) async => null);
    await tester.tap(find.byKey(_gallery));
    await tester.pumpAndSettle();
    expect(items.uploadedImages, isEmpty);
    expect(find.byKey(_clear), findsNothing);
  });

  testWidgets('the item is saved only after the upload finishes', (
    tester,
  ) async {
    final upload = Completer<Result<String>>();
    items.onUploadImage = () => upload.future;
    await pumpForm(tester);
    await fillRequired(tester);
    await tester.tap(find.byKey(_gallery));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Tạo món'));
    await tester.pump();
    expect(items.uploadedImages, ['mon.jpg']);
    expect(items.writes, isEmpty);
    expect(find.text('Đang tải ảnh lên…'), findsOneWidget);

    upload.complete(const Success('https://cdn.test/a.jpg'));
    await tester.pumpAndSettle();
    expect(items.lastCreate?.imageUrl, 'https://cdn.test/a.jpg');
  });

  testWidgets('a spinner covers the middle of the screen while saving', (
    tester,
  ) async {
    final save = Completer<Result<MenuItem>>();
    items.onWrite = () => save.future;
    await pumpForm(tester);
    await fillRequired(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Tạo món'));
    await tester.pump();

    expect(find.text('Đang thêm món…'), findsOneWidget);
    final spinner = find.byType(CircularProgressIndicator);
    expect(spinner, findsOneWidget);
    final center = tester.getCenter(spinner);
    expect(center.dx, closeTo(450, 1));
    expect(center.dy, closeTo(700, 40));
    expect(find.byType(MenuBusyOverlay).hitTestable(), findsOneWidget);
    expect(find.byKey(_gallery).hitTestable(), findsNothing);

    save.complete(Success(item()));
    await tester.pumpAndSettle();
    expect(find.byType(MenuBusyOverlay), findsNothing);
  });

  testWidgets('a failed upload keeps the form and does not save the item', (
    tester,
  ) async {
    items.onUploadImage = () async => const Error(
      Failure(
        type: FailureType.validation,
        code: 'IMAGE_TOO_LARGE',
        message: 'Ảnh vượt quá 5 MB. Hãy chọn ảnh nhỏ hơn.',
      ),
    );
    await pumpForm(tester, initial: item(imageUrl: 'https://cdn.test/old.jpg'));
    await tester.tap(find.byKey(_gallery));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Lưu thay đổi'));
    await tester.pumpAndSettle();
    expect(
      find.text('Ảnh vượt quá 5 MB. Hãy chọn ảnh nhỏ hơn.'),
      findsOneWidget,
    );
    expect(items.writes, isEmpty);
    expect(submit(tester, 'Lưu thay đổi').onPressed, isNotNull);

    items.onUploadImage = null;
    await tester.tap(find.widgetWithText(FilledButton, 'Lưu thay đổi'));
    await tester.pumpAndSettle();
    expect(items.lastUpdate?.imageUrl, 'https://cdn.test/mon.jpg');
  });

  testWidgets('saving again after a failed save reuses the uploaded photo', (
    tester,
  ) async {
    items.onWrite = () async => const Error(
      Failure(
        type: FailureType.validation,
        code: 'VALIDATION_ERROR',
        message: 'Chưa lưu được.',
      ),
    );
    await pumpForm(tester);
    await fillRequired(tester);
    await tester.tap(find.byKey(_gallery));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Tạo món'));
    await tester.pumpAndSettle();
    expect(find.byType(MenuItemForm), findsOneWidget);

    items.onWrite = null;
    await tester.tap(find.widgetWithText(FilledButton, 'Tạo món'));
    await tester.pumpAndSettle();
    expect(items.uploadedImages, ['mon.jpg']);
    expect(items.lastCreate?.imageUrl, 'https://cdn.test/mon.jpg');
  });

  group('camera permission', () {
    var picks = 0;
    setUp(() => picks = 0);
    Future<PickedMenuImage?> countingPicker(ImageSource source) async {
      picks++;
      return _photo;
    }

    testWidgets('is asked before the camera opens', (tester) async {
      await pumpForm(tester, picker: countingPicker);
      await tester.tap(find.byKey(_camera));
      await tester.pumpAndSettle();
      expect(camera.requests, 1);
      expect(picks, 1);
    });

    testWidgets('is not needed for the gallery', (tester) async {
      await pumpForm(tester, picker: countingPicker);
      await tester.tap(find.byKey(_gallery));
      await tester.pumpAndSettle();
      expect(camera.requests, 0);
      expect(picks, 1);
    });

    testWidgets('a refusal keeps the camera closed and says why', (
      tester,
    ) async {
      camera.access = CameraAccess.denied;
      await pumpForm(tester, picker: countingPicker);
      await tester.tap(find.byKey(_camera));
      await tester.pumpAndSettle();
      expect(
        find.text('Cần cho phép dùng máy ảnh để chụp ảnh món.'),
        findsOneWidget,
      );
      expect(picks, 0);
    });

    testWidgets('when blocked it leads to Settings', (tester) async {
      camera.access = CameraAccess.blocked;
      await pumpForm(tester, picker: countingPicker);
      await tester.tap(find.byKey(_camera));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mở Cài đặt'));
      await tester.pumpAndSettle();
      expect(camera.settingsOpened, 1);
      expect(picks, 0);
    });

    testWidgets('Settings stays closed if the user declines', (tester) async {
      camera.access = CameraAccess.blocked;
      await pumpForm(tester, picker: countingPicker);
      await tester.tap(find.byKey(_camera));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Để sau'));
      await tester.pumpAndSettle();
      expect(find.text('Mở Cài đặt'), findsNothing);
      expect(camera.settingsOpened, 0);
    });

    testWidgets('a refusal from iOS also leads to Settings', (tester) async {
      await pumpForm(
        tester,
        picker: (_) async =>
            throw PlatformException(code: 'camera_access_denied'),
      );
      await tester.tap(find.byKey(_camera));
      await tester.pumpAndSettle();
      expect(find.text('Mở Cài đặt'), findsOneWidget);
      expect(items.uploadedImages, isEmpty);
    });
  });

  group('platform permission', () {
    const channel = MethodChannel('flutter.baseflow.com/permissions/methods');
    final messenger =
        TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger;
    void answer(int status) => messenger.setMockMethodCallHandler(
      channel,
      (call) async => {Permission.camera.value: status},
    );
    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    for (final (status, expected) in [
      (PermissionStatus.granted, CameraAccess.granted),
      (PermissionStatus.denied, CameraAccess.denied),
      (PermissionStatus.permanentlyDenied, CameraAccess.blocked),
    ]) {
      test('Android ${status.name} is ${expected.name}', () async {
        answer(status.index);
        expect(await const MenuCameraPermission().request(), expected);
      });
    }

    test('iOS is left to the camera itself', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      expect(
        await const MenuCameraPermission().request(),
        CameraAccess.granted,
      );
    });
  });

  testWidgets('clearing drops a photo that was not saved yet', (tester) async {
    await pumpForm(tester);
    await fillRequired(tester);
    await tester.tap(find.byKey(_gallery));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(_clear));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Tạo món'));
    await tester.pumpAndSettle();
    expect(items.uploadedImages, isEmpty);
    expect(items.lastCreate?.imageUrl, '');
  });

  testWidgets('clearing removes the photo from the item', (tester) async {
    await pumpForm(tester, initial: item(imageUrl: 'https://cdn.test/old.jpg'));
    await tester.tap(find.byKey(_clear));
    await tester.pumpAndSettle();
    expect(find.byKey(_clear), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, 'Lưu thay đổi'));
    await tester.pumpAndSettle();
    expect(items.lastUpdate?.imageUrl, '');
  });
}
