import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../network/binary_download.dart';

/// Phones hand the file to the system share sheet (save to Photos/Files,
/// send, print from another app); web downloads it; desktop asks where to
/// save it.
enum FileExportMode { share, download }

abstract interface class FileExporter {
  FileExportMode get mode;

  /// Returns false when the person cancelled or nothing handled the file.
  Future<bool> export(DownloadedFile file, {Rect? origin});
}

final fileExporterProvider = Provider<FileExporter>(
  (ref) => const PlatformFileExporter(),
);

class PlatformFileExporter implements FileExporter {
  const PlatformFileExporter();

  @override
  FileExportMode get mode =>
      !kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.android ||
              defaultTargetPlatform == TargetPlatform.iOS)
      ? FileExportMode.share
      : FileExportMode.download;

  @override
  Future<bool> export(DownloadedFile file, {Rect? origin}) async {
    if (mode == FileExportMode.share) {
      final result = await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              file.bytes,
              name: file.fileName,
              mimeType: file.mimeType,
            ),
          ],
          fileNameOverrides: [file.fileName],
          sharePositionOrigin: origin,
        ),
      );
      return result.status != ShareResultStatus.dismissed;
    }
    final mimeType = file.mimeType == 'image/png'
        ? MimeType.png
        : MimeType.custom;
    final customMimeType = mimeType == MimeType.custom ? file.mimeType : null;
    final canChoose =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.macOS);
    if (canChoose) {
      final path = await FileSaver.instance.saveAs(
        name: file.baseName,
        bytes: file.bytes,
        fileExtension: file.extension,
        mimeType: mimeType,
        customMimeType: customMimeType,
      );
      return path != null && path.isNotEmpty;
    }
    await FileSaver.instance.saveFile(
      name: file.baseName,
      bytes: file.bytes,
      fileExtension: file.extension,
      mimeType: mimeType,
      customMimeType: customMimeType,
    );
    return true;
  }
}
