import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/core/auth/session_events.dart';
import 'package:pos_saas_app/core/network/auth_interceptor.dart';

import '../../helpers/auth_fakes.dart';

void main() {
  test('concurrent 401 responses trigger only one token refresh', () async {
    final storage = FakeTokenStorage(makeTokens(accessToken: 'old-access'));
    final mainAdapter = ProtectedAdapter();
    final refreshAdapter = RefreshAdapter();
    final client = Dio()..httpClientAdapter = mainAdapter;
    final refreshClient = Dio()..httpClientAdapter = refreshAdapter;
    client.interceptors.add(
      AuthInterceptor(
        client: client,
        refreshClient: refreshClient,
        tokenStorage: storage,
        sessionEvents: SessionEvents(),
      ),
    );

    final responses = await Future.wait([
      client.get<Map<String, dynamic>>('/protected/one'),
      client.get<Map<String, dynamic>>('/protected/two'),
    ]);

    expect(responses.every((item) => item.statusCode == 200), isTrue);
    expect(refreshAdapter.calls, 1);
    expect(storage.tokens?.refreshToken, 'new-refresh');
  });

  test('retried request does not create an infinite refresh loop', () async {
    final storage = FakeTokenStorage(makeTokens(accessToken: 'old-access'));
    final mainAdapter = ProtectedAdapter(alwaysUnauthorized: true);
    final refreshAdapter = RefreshAdapter();
    final client = Dio()..httpClientAdapter = mainAdapter;
    final refreshClient = Dio()..httpClientAdapter = refreshAdapter;
    client.interceptors.add(
      AuthInterceptor(
        client: client,
        refreshClient: refreshClient,
        tokenStorage: storage,
        sessionEvents: SessionEvents(),
      ),
    );

    await expectLater(
      client.get<void>('/protected'),
      throwsA(isA<DioException>()),
    );
    expect(refreshAdapter.calls, 1);
    expect(mainAdapter.calls, 2);
  });
}

class ProtectedAdapter implements HttpClientAdapter {
  ProtectedAdapter({this.alwaysUnauthorized = false});

  final bool alwaysUnauthorized;
  int calls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls++;
    final authorization = options.headers['Authorization'];
    if (alwaysUnauthorized || authorization != 'Bearer new-access') {
      return _jsonBody({'code': 'UNAUTHORIZED'}, 401);
    }
    return _jsonBody({'success': true}, 200);
  }

  @override
  void close({bool force = false}) {}
}

class RefreshAdapter implements HttpClientAdapter {
  int calls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls++;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    return _jsonBody({
      'accessToken': 'new-access',
      'refreshToken': 'new-refresh',
      'expiresIn': 900,
      'user': {
        'id': 'user-1',
        'restaurantId': 'restaurant-1',
        'restaurantCode': 'NH01',
        'restaurantName': 'Nhà hàng',
        'name': 'Owner',
        'email': 'owner@example.com',
        'phone': null,
        'role': 'OWNER',
        'permissions': ['MENU_VIEW'],
      },
    }, 200);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _jsonBody(Map<String, dynamic> json, int statusCode) {
  return ResponseBody.fromString(
    jsonEncode(json),
    statusCode,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}
