import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/common/http_client.dart' as shared;
import 'package:pure_live/core/common/request_scope.dart';
import 'package:pure_live/core/site/zhanqi/zhanqi_api.dart';

typedef _Read = Future<Object?> Function(CancelToken?);
typedef _Case = ({String name, _Read read, String body, int cap});
final _cases = <_Case>[
  (
    name: 'Zhanqi',
    read: (c) => ZhanqiApi().directory(cancel: c),
    body: '{"code":0,"data":{"cnt":0,"rooms":[]}}',
    cap: ZhanqiApi.responseLimit,
  ),
];

String _kind(Object? error) => switch (error) {
  ZhanqiException e => e.kind.name,
  _ => '${error.runtimeType}',
};
Matcher _failure(String kind) => throwsA(predicate<Object>((e) => _kind(e) == kind, kind));

class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);
  final Future<ResponseBody> Function(RequestOptions) respond;
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) =>
      respond(options);
  @override
  void close({bool force = false}) {}
}

class _Source {
  _Source({List<int>? initial}) {
    controller = StreamController<Uint8List>(
      onListen: () {
        listened.complete();
        if (initial != null) controller.add(Uint8List.fromList(initial));
      },
      onCancel: () {
        cancellations++;
      },
    );
  }
  late final StreamController<Uint8List> controller;
  final listened = Completer<void>();
  int cancellations = 0;
  ResponseBody body(int status) => ResponseBody(controller.stream, status);
  void add(String text) => controller.add(Uint8List.fromList(utf8.encode(text)));
  Future<void> close() => controller.close();
}

Future<void> _withDio(Future<ResponseBody> Function(RequestOptions) respond, Future<void> Function() run) async {
  final original = shared.HttpClient.instance.dio;
  final dio = Dio(BaseOptions(receiveTimeout: const Duration(seconds: 60)))..httpClientAdapter = _Adapter(respond);
  shared.HttpClient.instance.dio = dio;
  try {
    await run();
  } finally {
    shared.HttpClient.instance.dio = original;
    dio.close();
  }
}

void main() {
  test('request scope cancels before dispatch when caller is already cancelled', () async {
    final caller = CancelToken()..cancel();
    await withRequestCancellation(caller, (transport) async {
      expect(transport.isCancelled, isTrue);
      expect(identical(transport, caller), isFalse);
    });
  });

  test('request scope preserves original synchronous failure and closes only its token', () async {
    final caller = CancelToken();
    final error = StateError('fixture');
    CancelToken? scoped;
    await expectLater(
      withRequestCancellation<void>(caller, (transport) {
        scoped = transport;
        throw error;
      }),
      throwsA(same(error)),
    );
    expect(scoped!.isCancelled, isTrue);
    expect(caller.isCancelled, isFalse);
  });

  for (final platform in _cases) {
    test('${platform.name}: HTTP error closes upstream, not just transformed stream', () async {
      final source = _Source();
      final caller = CancelToken();
      try {
        await _withDio((_) async => source.body(403), () async {
          await expectLater(platform.read(caller), _failure('access'));
          expect(source.cancellations, 1);
          expect(caller.isCancelled, isFalse);
        });
      } finally {
        await source.close();
      }
    });

    test('${platform.name}: byte overflow closes upstream and preserves caller token', () async {
      final source = _Source(initial: Uint8List(platform.cap + 1));
      final caller = CancelToken();
      try {
        await _withDio((_) async => source.body(200), () async {
          await expectLater(platform.read(caller), _failure('schema'));
          expect(source.cancellations, 1);
          expect(caller.isCancelled, isFalse);
        });
      } finally {
        await source.close();
      }
    });

    test('${platform.name}: completed response preserves shared caller and supports next request', () async {
      final caller = CancelToken();
      final tokens = <CancelToken?>[];
      await _withDio(
        (options) async {
          tokens.add(options.cancelToken);
          return ResponseBody.fromString(platform.body, 200);
        },
        () async {
          expect(await platform.read(caller), isNotNull);
          expect(caller.isCancelled, isFalse);
          expect(await platform.read(caller), isNotNull);
          expect(caller.isCancelled, isFalse);
          expect(tokens, hasLength(2));
          expect(identical(tokens.first, tokens.last), isFalse);
          expect(tokens.every((token) => token?.isCancelled == true), isTrue);
        },
      );
    });

    test('${platform.name}: a failed sibling does not stop an in-flight shared-token request', () async {
      final failure = _Source();
      final pending = _Source();
      final caller = CancelToken();
      var calls = 0;
      try {
        await _withDio((_) async => ++calls == 1 ? pending.body(200) : failure.body(503), () async {
          final waiting = platform.read(caller);
          await pending.listened.future;
          await expectLater(platform.read(caller), _failure('service'));
          expect(pending.cancellations, 0);
          expect(caller.isCancelled, isFalse);
          pending.add(platform.body);
          await pending.close();
          expect(await waiting, isNotNull);
        });
      } finally {
        await failure.close();
        await pending.close();
      }
    });

    test('${platform.name}: caller cancellation reaches stalled upstream', () async {
      final source = _Source();
      final caller = CancelToken();
      try {
        await _withDio((_) async => source.body(200), () async {
          final check = expectLater(platform.read(caller), _failure('cancelled'));
          await source.listened.future;
          caller.cancel();
          await check;
          expect(source.cancellations, 1);
        });
      } finally {
        await source.close();
      }
    });

    test('${platform.name}: already cancelled caller dispatches no adapter request', () async {
      var calls = 0;
      await _withDio(
        (_) async {
          calls++;
          return ResponseBody.fromString(platform.body, 200);
        },
        () async {
          await expectLater(platform.read(CancelToken()..cancel()), _failure('cancelled'));
          expect(calls, 0);
        },
      );
    });
  }

  test('continuous small chunks obey total body deadline and close all upstream sources', () async {
    // A 60-second inactivity timeout cannot explain termination of a response
    // that emits a chunk every second. Exercise each API's real 20-second cap.
    final sources = <_Source>[];
    final timers = <Timer>[];
    final failures = <String>[];
    try {
      await _withDio(
        (_) async {
          final source = _Source(initial: [32]);
          sources.add(source);
          timers.add(
            Timer.periodic(const Duration(seconds: 1), (_) {
              source.add(' ');
            }),
          );
          return source.body(200);
        },
        () async {
          await Future.wait(
            _cases.map((platform) async {
              Object? result;
              try {
                await platform.read(null).timeout(const Duration(seconds: 24));
              } catch (error) {
                result = error;
              }
              if (_kind(result) != 'transport') failures.add('${platform.name}: ${_kind(result)}');
            }),
          );
          expect(failures, isEmpty);
          expect(sources, hasLength(_cases.length));
          expect(sources.map((s) => s.cancellations), everyElement(1));
        },
      );
    } finally {
      for (final timer in timers) {
        timer.cancel();
      }
      for (final source in sources) {
        await source.close();
      }
    }
  }, timeout: const Timeout(Duration(seconds: 40)));
}
