import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/ui/images/image_sizing.dart';
import '../providers/menu_image_picker.dart';
import '../providers/menu_providers.dart';
import 'menu_details.dart';

/// Shows the item's photo and lets the user replace it. A new photo stays on
/// the device as [pending] until the form saves the item.
class MenuImageField extends ConsumerStatefulWidget {
  const MenuImageField({
    super.key,
    required this.url,
    required this.pending,
    required this.enabled,
    required this.onPicked,
    required this.onCleared,
    this.errorText,
  });

  final String url;
  final PickedMenuImage? pending;
  final bool enabled;
  final ValueChanged<PickedMenuImage> onPicked;
  final VoidCallback onCleared;
  final String? errorText;

  @override
  ConsumerState<MenuImageField> createState() => _MenuImageFieldState();
}

class _MenuImageFieldState extends ConsumerState<MenuImageField> {
  String? _error;

  Future<bool> _cameraAllowed() async {
    final access = await ref.read(menuCameraPermissionProvider).request();
    if (!mounted) return false;
    switch (access) {
      case CameraAccess.granted:
        return true;
      case CameraAccess.denied:
        setState(() => _error = 'Cần cho phép dùng máy ảnh để chụp ảnh món.');
      case CameraAccess.blocked:
        await _offerSettings();
    }
    return false;
  }

  Future<void> _offerSettings() async {
    final open = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cần quyền máy ảnh'),
        content: const Text(
          'Ứng dụng đang bị chặn dùng máy ảnh. Hãy bật lại trong Cài đặt để chụp ảnh món.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Để sau'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Mở Cài đặt'),
          ),
        ],
      ),
    );
    if (open == true && mounted) {
      await ref.read(menuCameraPermissionProvider).openSettings();
    }
  }

  Future<void> _pick(ImageSource source) async {
    setState(() => _error = null);
    if (source == ImageSource.camera && !await _cameraAllowed()) return;
    if (!mounted) return;
    final PickedMenuImage? picked;
    try {
      picked = await ref.read(menuImagePickerProvider)(source);
    } on PlatformException catch (error) {
      if (!mounted) return;
      if (error.code == 'camera_access_denied') {
        await _offerSettings();
        return;
      }
      setState(
        () => _error = source == ImageSource.camera
            ? 'Không mở được máy ảnh. Vui lòng thử lại.'
            : 'Không mở được thư viện ảnh. Hãy cấp quyền cho ứng dụng trong Cài đặt.',
      );
      return;
    }
    if (picked == null || !mounted) return;
    widget.onPicked(picked);
  }

  void _clear() {
    setState(() => _error = null);
    widget.onCleared();
  }

  Widget get _preview {
    final pending = widget.pending;
    if (pending == null) {
      return MenuImage(url: widget.url, aspectRatio: 4 / 3, borderRadius: 10);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: AspectRatio(
        aspectRatio: 4 / 3,
        // A freshly taken photo can be 12 MP: decode it at the preview size.
        child: LayoutBuilder(
          builder: (context, constraints) => Image(
            image: ResizeImage.resizeIfNeeded(
              decodeExtent(
                constraints.maxWidth,
                MediaQuery.devicePixelRatioOf(context),
              ),
              null,
              MemoryImage(pending.bytes),
            ),
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) =>
                const MenuImage(url: null, aspectRatio: 4 / 3, borderRadius: 0),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pending = widget.pending;
    final enabled = widget.enabled;
    final error = _error ?? widget.errorText;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 96, child: _preview),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Ảnh món', style: theme.textTheme.labelLarge),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  OutlinedButton.icon(
                    key: const ValueKey('menu-image-gallery'),
                    onPressed: enabled
                        ? () => _pick(ImageSource.gallery)
                        : null,
                    icon: const Icon(Icons.photo_library_outlined, size: 18),
                    label: const Text('Chọn ảnh'),
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('menu-image-camera'),
                    onPressed: enabled ? () => _pick(ImageSource.camera) : null,
                    icon: const Icon(Icons.photo_camera_outlined, size: 18),
                    label: const Text('Chụp ảnh'),
                  ),
                  if (pending != null || widget.url.isNotEmpty)
                    TextButton.icon(
                      key: const ValueKey('menu-image-clear'),
                      onPressed: enabled ? _clear : null,
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('Xóa ảnh'),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                error ??
                    (pending != null
                        ? 'Ảnh sẽ được tải lên khi lưu món.'
                        : 'JPG, PNG hoặc WebP, tối đa 5 MB.'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: error != null
                      ? AppColors.danger
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
