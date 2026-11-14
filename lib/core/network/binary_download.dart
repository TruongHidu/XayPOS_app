import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../result/result.dart';
import '../values/vietnamese_text.dart';
import 'api_error_mapper.dart';

/// A file the API generated on request (e.g. a QR image). Never cached:
/// the bytes live only as long as whoever holds this object.
class DownloadedFile {
  const DownloadedFile({
    required this.bytes,
    required this.fileName,
    required this.mimeType,
  });

  final Uint8List bytes;
  final String fileName;
  final String mimeType;

  /// [fileName] without its extension, and the extension alone.
  String get baseName {
    final dot = fileName.lastIndexOf('.');
    return dot > 0 ? fileName.substring(0, dot) : fileName;
  }

  String get extension {
    final dot = fileName.lastIndexOf('.');
    return dot > 0 ? fileName.substring(dot + 1) : '';
  }
}

/// GETs [path] as raw bytes. JSON error bodies are decoded before mapping so
/// the API error code survives. The file name comes from
/// `Content-Disposition` when the browser exposes it, else [fallbackName].
Future<Result<DownloadedFile>> getBinary(
  Dio dio,
  String path, {
  Map<String, dynamic>? query,
  required String fallbackName,
}) async {
  try {
    final response = await dio.get<List<int>>(
      path,
      queryParameters: query,
      options: Options(
        responseType: ResponseType.bytes,
        headers: {'Accept': 'image/png, application/json'},
      ),
    );
    final data = response.data;
    if (response.statusCode != 200 || data == null || data.isEmpty) {
      throw const FormatException('Empty file response');
    }
    return Success(
      DownloadedFile(
        bytes: data is Uint8List ? data : Uint8List.fromList(data),
        fileName:
            fileNameFromDisposition(
              response.headers.value('content-disposition'),
            ) ??
            fallbackName,
        mimeType:
            response.headers
                .value(Headers.contentTypeHeader)
                ?.split(';')
                .first
                .trim() ??
            'image/png',
      ),
    );
  } on Object catch (error) {
    if (error is DioException) {
      final body = error.response?.data;
      if (body is List<int>) {
        try {
          error.response!.data = jsonDecode(utf8.decode(body));
        } on FormatException {
          error.response!.data = null;
        }
      }
    }
    return Error(ApiErrorMapper.fromException(error));
  }
}

/// Reads `filename="..."` (or bare `filename=...`) from a Content-Disposition
/// header. Returns null when absent or not a safe plain file name.
String? fileNameFromDisposition(String? header) {
  if (header == null) return null;
  final match = RegExp(
    r'''filename\s*=\s*"?([^";]+)"?''',
    caseSensitive: false,
  ).firstMatch(header);
  final name = match?.group(1)?.trim();
  if (name == null || name.isEmpty) return null;
  if (name.contains('/') || name.contains('\\') || name.startsWith('.')) {
    return null;
  }
  return name;
}

/// ASCII file-name slug: drops Vietnamese diacritics, lowercases and joins
/// words with `-` (`BÀN 7` → `ban-7`). Never empty.
String asciiSlug(String value) {
  final slug = removeVietnameseDiacritics(
    value.toLowerCase(),
  ).replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
  return slug.isEmpty ? 'qr' : slug;
}
