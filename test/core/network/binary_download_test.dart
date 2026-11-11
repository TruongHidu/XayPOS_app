import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/core/errors/failure.dart';
import 'package:pos_saas_app/core/network/binary_download.dart';
import 'package:pos_saas_app/core/result/result.dart';

import '../../helpers/qr_fakes.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);

  final ResponseBody Function(RequestOptions options) respond;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return respond(options);
  }

  @override
  void close({bool force = false}) {}
}

Dio _dio(ResponseBody Function(RequestOptions) respond) =>
    Dio(BaseOptions(baseUrl: 'https://pos.test'))
      ..httpClientAdapter = _Adapter(respond);

ResponseBody _error(int status, String code) => ResponseBody.fromString(
  jsonEncode({
    'success': false,
    'code': code,
    'message': 'server text',
    'timestamp': '2026-11-09T00:00:00Z',
  }),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

void main() {
  test('returns bytes, mime type and the server file name', () async {
    final dio = _dio(
      (_) => ResponseBody.fromBytes(
        tinyPng,
        200,
        headers: {
          Headers.contentTypeHeader: ['image/png'],
          'content-disposition': ['attachment; filename="qr-ban-ban-7.png"'],
        },
      ),
    );
    final result = await getBinary(
      dio,
      '/api/v1/tables/t1/qr/image',
      query: {'format': 'png', 'size': 1024},
      fallbackName: 'fallback.png',
    );
    final file = (result as Success<DownloadedFile>).value;
    expect(file.bytes, tinyPng);
    expect(file.fileName, 'qr-ban-ban-7.png');
    expect(file.mimeType, 'image/png');
    expect(file.baseName, 'qr-ban-ban-7');
    expect(file.extension, 'png');
  });

  test('falls back to the client name when the header is hidden', () async {
    final dio = _dio(
      (_) => ResponseBody.fromBytes(
        tinyPng,
        200,
        headers: {
          Headers.contentTypeHeader: ['image/png'],
        },
      ),
    );
    final result = await getBinary(dio, '/x', fallbackName: 'the-qr-menu.png');
    expect(
      (result as Success<DownloadedFile>).value.fileName,
      'the-qr-menu.png',
    );
  });

  for (final (status, code, type) in [
    (404, 'TABLE_NOT_FOUND', FailureType.notFound),
    (404, 'PUBLIC_MENU_LINK_NOT_INITIALIZED', FailureType.notFound),
    (403, 'FEATURE_NOT_ENTITLED', FailureType.featureNotEntitled),
    (400, 'VALIDATION_ERROR', FailureType.validation),
  ]) {
    test('decodes a JSON error body sent to a bytes request ($code)', () async {
      final result = await getBinary(
        _dio((_) => _error(status, code)),
        '/x',
        fallbackName: 'x.png',
      );
      final failure = (result as Error<DownloadedFile>).failure;
      expect(failure.code, code);
      expect(failure.type, type);
    });
  }

  test('non-JSON error body still yields a failure', () async {
    final result = await getBinary(
      _dio((_) => ResponseBody.fromString('<html>oops</html>', 502)),
      '/x',
      fallbackName: 'x.png',
    );
    expect(result, isA<Error<DownloadedFile>>());
  });

  test('file name parsing rejects paths', () {
    expect(
      fileNameFromDisposition('inline; filename=qr-menu.png'),
      'qr-menu.png',
    );
    expect(
      fileNameFromDisposition('attachment; filename="../evil.png"'),
      isNull,
    );
    expect(fileNameFromDisposition(null), isNull);
  });

  test('asciiSlug drops Vietnamese diacritics', () {
    expect(asciiSlug('BÀN 7'), 'ban-7');
    expect(asciiSlug('Đường số 1'), 'duong-so-1');
    expect(asciiSlug('Ba\u0300n  VIP!'), 'ban-vip');
    expect(asciiSlug('   '), 'qr');
  });
}
