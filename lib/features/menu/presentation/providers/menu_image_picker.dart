import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

class PickedMenuImage {
  const PickedMenuImage(this.bytes, this.name);
  final Uint8List bytes;
  final String name;
}

typedef MenuImagePicker = Future<PickedMenuImage?> Function(ImageSource source);

/// Downscaled here so a phone photo stays well under the server's 5 MB limit.
Future<PickedMenuImage?> pickMenuImage(ImageSource source) async {
  final file = await ImagePicker().pickImage(
    source: source,
    maxWidth: 1280,
    maxHeight: 1280,
    imageQuality: 80,
  );
  if (file == null) return null;
  return PickedMenuImage(await file.readAsBytes(), file.name);
}

enum CameraAccess { granted, denied, blocked }

/// The gallery goes through the system picker, which needs no permission.
class MenuCameraPermission {
  const MenuCameraPermission();

  Future<CameraAccess> request() async {
    // iOS asks by itself when image_picker opens the camera.
    if (defaultTargetPlatform != TargetPlatform.android) {
      return CameraAccess.granted;
    }
    final status = await Permission.camera.request();
    if (status.isGranted) return CameraAccess.granted;
    return status.isPermanentlyDenied
        ? CameraAccess.blocked
        : CameraAccess.denied;
  }

  Future<bool> openSettings() => openAppSettings();
}
