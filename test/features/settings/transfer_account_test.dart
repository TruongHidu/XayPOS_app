import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/core/errors/failure.dart';
import 'package:pos_saas_app/core/network/api_error_mapper.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/features/settings/data/transfer_account_remote_data_source.dart';
import 'package:pos_saas_app/features/settings/data/transfer_account_repository_impl.dart';
import 'package:pos_saas_app/features/settings/domain/entities/transfer_account.dart';

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

ResponseBody _json(Object body, [int status = 200]) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

(TransferAccountRepositoryImpl, _Adapter) _repository(
  ResponseBody Function(RequestOptions options) respond,
) {
  final adapter = _Adapter(respond);
  final dio = Dio(BaseOptions(baseUrl: 'https://pos.test'))
    ..httpClientAdapter = adapter;
  return (
    TransferAccountRepositoryImpl(TransferAccountRemoteDataSource(dio)),
    adapter,
  );
}

const _configured = {
  'configured': true,
  'bankBin': '970436',
  'accountNumber': '0123456789',
  'accountName': 'NGUYEN VAN A',
  'updatedAt': '2026-11-10T03:00:00Z',
};

void main() {
  group('TransferAccountDraft', () {
    test('normalizes the account name to uppercase ASCII', () {
      expect(
        TransferAccountDraft.normalizeAccountName('  Nguyễn   Văn  Đức '),
        'NGUYEN VAN DUC',
      );
      expect(
        TransferAccountDraft.normalizeAccountName('Công ty Phở Hà Nội 2'),
        'CONG TY PHO HA NOI 2',
      );
      expect(
        TransferAccountDraft.normalizeAccountNumber(' 0123 456 789 '),
        '0123456789',
      );
    });

    test('validates BIN, account number and name', () {
      expect(TransferAccountDraft.validateBankBin('970436'), isNull);
      expect(TransferAccountDraft.validateBankBin(''), isNotNull);
      expect(TransferAccountDraft.validateBankBin('97043'), isNotNull);
      expect(TransferAccountDraft.validateBankBin('97043A'), isNotNull);

      expect(TransferAccountDraft.validateAccountNumber('1'), isNull);
      expect(TransferAccountDraft.validateAccountNumber('AB12 34'), isNull);
      expect(TransferAccountDraft.validateAccountNumber('1' * 19), isNull);
      expect(
        TransferAccountDraft.validateAccountNumber('1' * 20),
        'Số tài khoản tối đa 19 ký tự.',
      );
      expect(TransferAccountDraft.validateAccountNumber('  '), isNotNull);
      expect(TransferAccountDraft.validateAccountNumber('0123-456'), isNotNull);

      expect(TransferAccountDraft.validateAccountName('Trần Thị Bé'), isNull);
      expect(TransferAccountDraft.validateAccountName('A' * 50), isNull);
      expect(TransferAccountDraft.validateAccountName('A' * 51), isNotNull);
      expect(TransferAccountDraft.validateAccountName('   '), isNotNull);
      expect(
        TransferAccountDraft.validateAccountName('NGUYEN & CO'),
        isNotNull,
      );
    });

    test('toJson sends the normalized shape and errors lists bad fields', () {
      const draft = TransferAccountDraft(
        bankBin: ' 970436 ',
        accountNumber: '0123 456 789',
        accountName: 'Nguyễn Văn A',
      );
      expect(draft.isValid, isTrue);
      expect(draft.toJson(), {
        'bankBin': '970436',
        'accountNumber': '0123456789',
        'accountName': 'NGUYEN VAN A',
      });
      const bad = TransferAccountDraft(
        bankBin: '',
        accountNumber: '',
        accountName: 'Phở#1',
      );
      expect(bad.errors.keys, ['bankBin', 'accountNumber', 'accountName']);
    });
  });

  group('TransferAccountRepositoryImpl', () {
    test('reads configured and empty accounts', () async {
      var body = <String, Object?>{..._configured};
      final (repository, adapter) = _repository((_) => _json(body));
      final account = await repository.get();
      expect(account, isA<Success<TransferAccount?>>());
      final value = (account as Success<TransferAccount?>).value!;
      expect(value.bankBin, '970436');
      expect(value.accountNumber, '0123456789');
      expect(value.accountName, 'NGUYEN VAN A');
      expect(value.updatedAt, DateTime.utc(2026, 11, 10, 3));
      expect(
        adapter.requests.single.path,
        '/api/v1/restaurants/me/transfer-account',
      );

      body = {'configured': false};
      final empty = await repository.get();
      expect((empty as Success<TransferAccount?>).value, isNull);
    });

    test(
      'saves with PUT and the normalized body, removes with DELETE',
      () async {
        final (repository, adapter) = _repository(
          (options) => options.method == 'DELETE'
              ? _json({'configured': false})
              : _json(_configured),
        );
        final saved = await repository.save(
          const TransferAccountDraft(
            bankBin: '970436',
            accountNumber: '0123 456 789',
            accountName: 'nguyễn văn a',
          ),
        );
        expect(saved, isA<Success<TransferAccount>>());
        expect(adapter.requests.first.method, 'PUT');
        expect(adapter.requests.first.data, {
          'bankBin': '970436',
          'accountNumber': '0123456789',
          'accountName': 'NGUYEN VAN A',
        });
        expect(await repository.remove(), isA<Success<void>>());
        expect(adapter.requests.last.method, 'DELETE');
      },
    );

    test(
      'maps server validation and malformed responses to failures',
      () async {
        final (repository, _) = _repository(
          (_) => _json({
            'code': 'INVALID_TRANSFER_ACCOUNT',
            'message': 'invalid',
            'fieldErrors': {'accountNumber': 'Số tài khoản không hợp lệ.'},
          }, 400),
        );
        final result = await repository.save(
          const TransferAccountDraft(
            bankBin: '970436',
            accountNumber: '1',
            accountName: 'A',
          ),
        );
        final failure = (result as Error<TransferAccount>).failure;
        expect(failure.code, 'INVALID_TRANSFER_ACCOUNT');
        expect(failure.type, FailureType.validation);
        expect(failure.message, contains('tài khoản nhận chuyển khoản'));

        final (broken, _) = _repository(
          (_) => _json({'configured': true, 'bankBin': '970436'}),
        );
        expect(await broken.get(), isA<Error<TransferAccount?>>());
      },
    );
  });

  test('new transfer error codes have Vietnamese messages', () {
    for (final (code, status) in [
      ('TRANSFER_ACCOUNT_NOT_CONFIGURED', 409),
      ('ORDER_NOT_PAYABLE', 409),
      ('TRANSFER_QR_CURRENCY_UNSUPPORTED', 422),
      ('INVALID_TRANSFER_ACCOUNT', 400),
    ]) {
      final request = RequestOptions(path: '/x');
      final failure = ApiErrorMapper.fromException(
        DioException(
          requestOptions: request,
          type: DioExceptionType.badResponse,
          response: Response(
            requestOptions: request,
            statusCode: status,
            data: {'code': code, 'message': 'english'},
          ),
        ),
      );
      expect(failure.code, code);
      expect(failure.message, isNot('english'));
      expect(failure.message, isNot(contains('Đã xảy ra lỗi')));
    }
  });
}
