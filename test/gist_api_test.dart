import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/modules/gist_backup/gist_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<RequestOptions> requests;
  late List<_Reply> replies;
  late Dio dio;
  late GistApi api;

  String file(String stamp) => '${GistApi.filePrefix}$stamp${GistApi.fileSuffix}';

  Map<String, dynamic> fileEntry(String stamp, {int size = 12, String content = '{}'}) => {
    'size': size,
    'content': content,
  };

  setUp(() {
    requests = [];
    replies = [];
    dio = Dio();
    dio.httpClientAdapter = _FakeAdapter((options) {
      requests.add(options);
      return replies.removeAt(0);
    });
    api = GistApi(token: 'token', dio: dio);
  });

  test('token verification rejects a non-user payload', () async {
    replies.add(_Reply(200, jsonEncode({'login': 'octocat'})));
    await api.verifyToken();
    expect(requests.single.path, 'https://api.github.com/user');
    expect(requests.single.headers['Authorization'], 'Bearer token');

    replies.add(_Reply(200, jsonEncode({'message': 'nope'})));
    expect(() => api.verifyToken(), throwsA(isA<GistApiException>()));
  });

  test('an unauthorized response is reported as a permission failure', () async {
    replies.add(_Reply(401, jsonEncode({'message': 'Bad credentials'})));
    try {
      await api.ensureBackupGist();
      fail('expected a GistApiException');
    } on GistApiException catch (error) {
      expect(error.isUnauthorized, isTrue);
      expect(error.statusCode, 401);
      expect(error.detail, 'Bad credentials');
    }
  });

  test('the backup gist is reused when its description matches', () async {
    replies.add(
      _Reply(
        200,
        jsonEncode([
          {'id': 'other', 'description': 'unrelated'},
          {'id': 'mine', 'description': GistApi.description},
        ]),
      ),
    );

    expect(await api.ensureBackupGist(), 'mine');
    expect(requests, hasLength(1), reason: '已存在时不再创建');
  });

  test('a missing backup gist is created as a private gist', () async {
    replies.add(_Reply(200, jsonEncode([])));
    replies.add(_Reply(201, jsonEncode({'id': 'fresh'})));

    expect(await api.ensureBackupGist(), 'fresh');
    final create = requests.last;
    expect(create.method, 'POST');
    final body = jsonDecode(create.data as String) as Map<String, dynamic>;
    expect(body['public'], isFalse);
    expect(body['description'], GistApi.description);
  });

  test('gist paging stops at the first short page', () async {
    replies.add(_Reply(200, jsonEncode(_unrelatedPage(GistApi.pageSize))));
    replies.add(_Reply(200, jsonEncode([{'id': 'mine', 'description': GistApi.description}])));

    expect(await api.ensureBackupGist(), 'mine');
    expect(requests.map((item) => item.uri.queryParameters['page']), ['1', '2']);
  });

  test('only timestamped backup files become snapshots, newest first', () async {
    replies.add(
      _Reply(
        200,
        jsonEncode({
          'files': {
            '${GistApi.filePrefix}README${GistApi.fileSuffix}': fileEntry('README'),
            'notes.md': {'size': 3, 'content': 'hi'},
            file('20260101_100000'): fileEntry('20260101_100000', size: 10),
            file('20260301_100000'): fileEntry('20260301_100000', size: 20),
          },
        }),
      ),
    );

    final snapshots = await api.listSnapshots('gist-1');

    expect(snapshots.map((item) => item.fileName), [file('20260301_100000'), file('20260101_100000')]);
    expect(snapshots.first.size, 20);
    expect(snapshots.first.savedAt, DateTime(2026, 3, 1, 10, 0, 0));
    expect(snapshots.first.displayTime, '2026-03-01 10:00:00');
  });

  test('a truncated snapshot falls back to its raw url', () async {
    replies.add(
      _Reply(
        200,
        jsonEncode({
          'files': {
            file('20260101_100000'): {'size': 9000, 'content': '', 'raw_url': 'https://raw.example/1'},
          },
        }),
      ),
    );
    replies.add(_Reply(200, '{"backupVersion":3}'));

    expect(await api.readSnapshot('gist-1', file('20260101_100000')), '{"backupVersion":3}');
    expect(requests.last.uri.toString(), 'https://raw.example/1');
  });

  test('missing snapshot content is reported instead of silently succeeding', () async {
    replies.add(_Reply(200, jsonEncode({'files': {}})));
    expect(() => api.readSnapshot('gist-1', file('20260101_100000')), throwsA(isA<GistApiException>()));
  });

  test('writing a snapshot and rotating old files use a single PATCH', () async {
    replies.add(_Reply(200, jsonEncode({'id': 'gist-1'})));

    await api.writeSnapshot(
      'gist-1',
      fileName: file('20260928_103000'),
      content: '{"backupVersion":3}',
      removeFileNames: [file('20260101_100000')],
    );

    final request = requests.single;
    expect(request.method, 'PATCH');
    expect(request.path, 'https://api.github.com/gists/gist-1');
    final body = jsonDecode(request.data as String) as Map<String, dynamic>;
    expect(body['files'], {
      file('20260928_103000'): {'content': '{"backupVersion":3}'},
      file('20260101_100000'): null,
    });
  });

  test('deleting a snapshot sends a null file entry', () async {
    replies.add(_Reply(200, jsonEncode({'id': 'gist-1'})));

    await api.deleteSnapshot('gist-1', file('20260101_100000'));

    final body = jsonDecode(requests.single.data as String) as Map<String, dynamic>;
    expect(body['files'], {file('20260101_100000'): null});
  });

  test('snapshot file names never collide within the same second', () {
    final time = DateTime(2026, 9, 28, 10, 30, 0);
    final first = GistApi.snapshotFileName(time, {});
    expect(first, file('20260928_103000'));

    final second = GistApi.snapshotFileName(time, {first});
    expect(second, '${GistApi.filePrefix}20260928_103000-1${GistApi.fileSuffix}');

    final third = GistApi.snapshotFileName(time, {first, second});
    expect(third, '${GistApi.filePrefix}20260928_103000-2${GistApi.fileSuffix}');
  });

  test('snapshot file parsing rejects foreign file names', () {
    expect(GistApi.isSnapshotFile(file('20260928_103000')), isTrue);
    expect(GistApi.isSnapshotFile('${GistApi.filePrefix}README${GistApi.fileSuffix}'), isFalse);
    expect(GistApi.isSnapshotFile('purelive_backup_2026.json'), isFalse);
    expect(GistApi.isSnapshotFile('notes.md'), isFalse);
  });
}

List<Map<String, dynamic>> _unrelatedPage(int count) =>
    List.generate(count, (index) => {'id': 'x$index', 'description': 'other'});

class _Reply {
  _Reply(this.statusCode, this.body);

  final int statusCode;
  final String body;
}

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.handler);

  final _Reply Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final reply = handler(options);
    return ResponseBody.fromString(
      reply.body,
      reply.statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
