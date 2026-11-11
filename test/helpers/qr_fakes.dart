import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:pos_saas_app/core/network/binary_download.dart';
import 'package:pos_saas_app/core/platform/file_exporter.dart';

/// A valid 1×1 PNG so `Image.memory` decodes without errors.
final tinyPng = Uint8List.fromList(
  base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
  ),
);

class FakeFileExporter implements FileExporter {
  FakeFileExporter([this.mode = FileExportMode.download]);

  @override
  final FileExportMode mode;
  final exported = <DownloadedFile>[];

  @override
  Future<bool> export(DownloadedFile file, {Rect? origin}) async {
    exported.add(file);
    return true;
  }
}
