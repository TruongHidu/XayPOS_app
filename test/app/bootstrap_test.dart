import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/app/bootstrap.dart';
import 'package:pos_saas_app/app/providers.dart';

void main() {
  testWidgets(
    'bootstrap waits for .env before providers read REST and WebSocket config',
    (tester) async {
      dotenv = DotEnv();
      rootBundle.evict('.env');
      final envAsset = Completer<ByteData>();
      var requests = 0, builds = 0;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMessageHandler('flutter/assets', (message) async {
        final name = utf8.decode(
          message!.buffer.asUint8List(
            message.offsetInBytes,
            message.lengthInBytes,
          ),
        );
        if (name != '.env') return null;
        requests++;
        return envAsset.future;
      });
      addTearDown(() {
        messenger.setMockMessageHandler('flutter/assets', null);
        rootBundle.evict('.env');
        dotenv = DotEnv();
      });

      final startup = bootstrap(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Consumer(
            builder: (context, ref, _) {
              builds++;
              final api = ref.watch(apiClientsProvider);
              final realtime = ref.watch(realtimeConfigProvider);
              return Text(
                '${api.authenticated.options.baseUrl}\n${realtime.endpoint}',
              );
            },
          ),
        ),
      );
      await tester.pump();
      expect(requests, 1);
      expect(builds, 0);

      envAsset.complete(
        ByteData.sublistView(
          Uint8List.fromList(
            utf8.encode('''
API_BASE_URL=http://192.0.2.15:8080
REALTIME_ENABLED=true
REALTIME_TRANSPORT=websocket
REALTIME_URL=
'''),
          ),
        ),
      );
      await tester.pump();
      await startup;
      await tester.pump();

      expect(builds, greaterThan(0));
      expect(
        find.text('http://192.0.2.15:8080\nws://192.0.2.15:8080/ws'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final missing in [true, false]) {
    testWidgets(
      '${missing ? 'missing' : 'empty'} .env blocks providers and can recover on retry',
      (tester) async {
        dotenv = DotEnv();
        rootBundle.evict('.env');
        var available = false, builds = 0, requests = 0;
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMessageHandler('flutter/assets', (message) async {
          final name = utf8.decode(
            message!.buffer.asUint8List(
              message.offsetInBytes,
              message.lengthInBytes,
            ),
          );
          if (name != '.env') return null;
          requests++;
          if (!available) return missing ? null : ByteData(0);
          return ByteData.sublistView(
            Uint8List.fromList(
              utf8.encode('API_BASE_URL=http://192.0.2.20:8080\n'),
            ),
          );
        });
        addTearDown(() {
          messenger.setMockMessageHandler('flutter/assets', null);
          rootBundle.evict('.env');
          dotenv = DotEnv();
        });

        await bootstrap(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Consumer(
              builder: (context, ref, _) {
                builds++;
                final api = ref.watch(apiClientsProvider);
                final realtime = ref.watch(realtimeConfigProvider);
                return Text(
                  '${api.authenticated.options.baseUrl}\n${realtime.endpoint}',
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Không tải được cấu hình'), findsOneWidget);
        expect(find.byType(ProviderScope), findsNothing);
        expect(builds, 0);
        expect(tester.takeException(), isNull);

        available = true;
        await tester.tap(find.text('Thử lại'));
        await tester.pumpAndSettle();
        expect(requests, 2);
        expect(builds, greaterThan(0));
        expect(
          find.text('http://192.0.2.20:8080\nws://192.0.2.20:8080/ws'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
